#!/usr/bin/perl -w
use strict;
use warnings;
use JSON;
use Statistics::Descriptive;
use Statistics::RankCorrelation;
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
		'resultfile'	=> { type => 'string', array => 1 },
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my @RESULTFILE 		= @{$BitQC->getRunConfig('resultfile')};
my $REMOVE      	= $BitQC->getRunConfig('remove');
my $UNIQUECOLL      = $BitQC->getRunConfig('uniquecoll');
my $PLOTSCOL 		= $BitQC->getRunConfig('plotscol');
my $MAXLIST     	= $BitQC->getRunConfig('maxlist');

#Get databaseadaptor
my $DATABASE_ADAPTOR = $BitQC->{DatabaseAdapter};

######################################################################################
# READ FROM RESULTS FILES AND INTEGRATE
######################################################################################

# hash to hold all results
my %results;

foreach my $resultfile (@RESULTFILE) {
	# create local file object
	if (-f $resultfile){
	my $resultsfile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
	    'filetype' => 'txt',
		'file' => $resultfile,
	    'type' => 'local'
	});
	my $resultfilepointer = $resultsfile->getReadPointer();

	my $json = <$resultfilepointer>;

	my $result;
	$result = decode_json($json) if ($json);

	foreach my $key (keys %{$result}){
		if ($results{$key}){
			foreach my $record (keys %{$result->{$key}->{values}}){
				$results{$key}{values}{$record} += $result->{$key}{values}{$record};				
			}
			# once we got "text" we never go back
			$results{$key}{type} = $result->{$key}->{type} unless ($results{$key}{type} eq 'text')
		} else {

			$results{$key} = $result->{$key};
			my @dot = split(/\./, $key);
			$results{$key}{querykeys} = \@dot;
		}
	}
	}

	# remove file if requested
	#unlink($RESULTFILE) if ($REMOVE);
}

######################################################################################
# RETRIEVE EXISTING DATA FROM COLLECTION
######################################################################################

# create mongodb connection
$MongoDB::Cursor::timeout = -1; # no timeout
my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();

# get collections
my $storecoll = $UNIQUECOLL."_unique";
my $unique_collection = $mongodb->$storecoll;
my $plots_collection = $mongodb->$PLOTSCOL;

# build the query
my $cursor = $unique_collection->find();

# make reading form slave nodes OK
$cursor->slave_okay(1);

my $stats = Statistics::Descriptive::Full->new();

# hash to hold the database entries
my %records;

# get all records from the database
while (my $record = $cursor->next) {
	$records{$record->{'_id'}} = $record;
}

foreach my $id (keys %results){
	# take the name of the database if available
	$results{$id}{name} = $records{$id}->{'name'} ? $records{$id}->{'name'} : $id;

	# check if the number of unique elements for this key in the database is larger than max
#	print Dumper ($results{$id});
	if ($results{$id}{values}){

		my @uniquevalues = keys ($results{$id}{values});
		unless( $results{$id}->{'type'} eq 'text' && @uniquevalues > $MAXLIST ){
			
			# calculate some stats if numerical
			if ($results{$id}->{'type'} eq 'numerical'){

				# get all the values in the database (we stored all unique values and their count in the map step)
				my @values;

				# for all unique values
				foreach my $key (keys %{$results{$id}{values}}){
					for (my $count = 0; $count <= $results{$id}{values}{$key}; $count++) {
					 	push (@values, $key);
					}
				}

				$stats->add_data(@values);
				$results{$id}{'stats'}{'mean'} = $stats->mean();			
				$results{$id}{'stats'}{'max'} = $stats->quantile(4);
				$results{$id}{'stats'}{'min'} = $stats->quantile(0);
				$results{$id}{'stats'}{'median'} = $stats->quantile(2);
				$results{$id}{'stats'}{'Q1'} = $stats->quantile(1);
				$results{$id}{'stats'}{'Q3'} = $stats->quantile(3);
				$results{$id}{'stats'}{'stdev'} = $stats->standard_deviation();
				$stats->clear();
				undef @values;
			}
			
			# Limit to 1000 values or mongo document will become too large
			if(@uniquevalues <= 1000){
				my @graphvalues = [];
				my @graphcounts = [];
				# for all unique values
				foreach my $key (keys %{$results{$id}{values}}){
					push ( @graphvalues, $key);
					push ( @graphcounts, $results{$id}{values}{$key});
				}

				# create graph-data record
				my $graph_column_name = $results{$id}{name};
				$graph_column_name =~ s/\./_/g;

				my %graph = (
					data => {
						'values' => \@graphvalues,
						'counts' => \@graphcounts
					},
					header => ['values','counts'],
					name => $results{$id}{name}." database values"
				);

				$graph{factor} = ['values'] if ($results{$id}->{'type'} eq 'text');

				# update/store the graph data
				if ($records{$id}->{'graph'}){
					# update
					foreach my $argument (keys %graph){
						my $value = $graph{$argument};
						$plots_collection->update(
							{ _id    => $records{$id}->{'graph'}->{'_id'} },
							{ '$set' => { $argument => $value } }, {multiple => 1} );
					}
					$results{$id}{graph}{name} = $graph{name};
				} else {
					# store
					$results{$id}{graph}{_id} = $plots_collection->insert( \%graph, { safe => 1 } );
					$results{$id}{graph}{name} = $graph{name};
				}
			}

		}

		@uniquevalues = [] if (@uniquevalues > $MAXLIST);

		$results{$id}{values} = \@uniquevalues;
	}


	if ($records{$id}->{querykeys}){
		# update the database record:
		foreach my $argument (keys $results{$id}){
			my $value = $results{$id}{$argument};

			$unique_collection->update(
				{ _id    => $id },
				{ '$set' => { $argument => $value } }, {multiple => 1} );
		}
	} else {
		# insert the data in the database
		$results{$id}{'_id'} = $id;
		$unique_collection->insert( $results{$id}, { safe => 1 } );
	}
}


# finish logging
$BitQC->finish_log(
	message => "Reduction and storage of $UNIQUECOLL records completed." );

