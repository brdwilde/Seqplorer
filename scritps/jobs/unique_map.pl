#!/usr/bin/perl -w
use strict;
use warnings;
use JSON;
use BitQC;

######################################################################################
# INITIALISE BITQC MODULE
######################################################################################

# Make BitQC object
# settings will come from environment variables
my $BitQC = new BitQC();

# Load bitqc configuration from the given database
$BitQC->load(
	'script_args' => {
		'resultfile'	=> { type => 'string' },
		'key'			=> { type => 'string' }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $RESULTFILE 		= $BitQC->getRunConfig('resultfile');
my $KEY 			= $BitQC->getRunConfig('key');
my $REMOVE      	= $BitQC->getRunConfig('remove');
my $UNIQUECOLL      = $BitQC->getRunConfig('uniquecoll');
my $QUERY      		= decode_json($BitQC->getRunConfig('query'));
my $PARALLELKEY     = $BitQC->getRunConfig('parallelkey');

# hash of document keys to ignore

my %IGNOREKEYS = (
	'sa.PL' => 1,
);

#Get databaseadaptor
my $DATABASE_ADAPTOR = $BitQC->{DatabaseAdapter};

######################################################################################
# READ VARIANTS FROM VCF FILE
######################################################################################

# create mongodb connection
$MongoDB::Cursor::timeout = -1; # no timeout
my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();

my $variants_collection = $mongodb->$UNIQUECOLL;

# hold compassison results
my %result;

$QUERY->{$PARALLELKEY} = $KEY;

# build the query
my $cursor = $variants_collection->find($QUERY);

# make reading form slave nodes OK
$cursor->slave_okay(1);

my %variantfiles;
my @annotatecommands;

my $counter = 1;
my %results;
while (my $record = $cursor->next) {
	# add all values of this record to a hash
	%results = %{_print_keyvals($record,'',\%results)};
}

# encode result as json
my $json = encode_json(\%results);

# create local file object
my $resultsfile = $BitQC->{fileadapter}->createFile( {
	'compression' => 'gzip',
    'filetype' => 'txt',
	'file' => $RESULTFILE,
    'type' => 'local'
});
my $resultfilepointer = $resultsfile->getWritePointer();

#  print to result file
print $resultfilepointer $json;


# finish logging
$BitQC->finish_log(
	message => "End job: reduction job done." );


# function to reduce a mongo record to a single hash
# the data type and all
sub _print_keyvals {
	my ($record, $key, $return) = @_;

	my %return;
	%return = %{$return} if $return;

	if ($key){
		if (!ref($record)) {
			# determine the data type

			# once we found a text field, we stick with text...
			$return{$key}{type} = ($record =~ m/^[+\-]?(?:0|[1-9]\d*)(?:\.\d*)?(?:[eE][+\-]?\d+)?$/) ? 'numerical' : 'text' unless ($return{$key}{type} && $return{$key}{type} eq 'text');

			# count the unique occurrences of the values
			$return{$key}{values}{$record} += 1;
		} elsif (ref($record) eq 'HASH') {
			foreach my $subkey (keys %{$record} ){
				my $newkey = $key.'.'.$subkey;
				if (!$IGNOREKEYS{$newkey}) {
					%return = %{_print_keyvals($record->{$subkey}, $newkey, \%return)};
				} else {
					$return{$newkey}{type} = 'other';
				}
			}
		} elsif (ref($record) eq 'ARRAY') {
			foreach my $element (@{$record}){
				%return = %{_print_keyvals($element, $key, \%return)};
			}
		} elsif (ref($record) eq 'boolean') {
			$return{$key}{type} = 'bool';
		} elsif (ref($record) eq 'MongoDB::OID') {
			$return{$key}{type} = 'mongo_id';
		}
	} else {
		foreach my $key (keys %{$record} ){
			%return = %{_print_keyvals($record->{$key}, $key, \%return)};
		}
	}
	return \%return;
};
