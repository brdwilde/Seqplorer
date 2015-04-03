#!/usr/bin/perl -w

=head1 LICENSE

  No licence yet?

=head1 CONTACT

  Please email comments or questions to the 
  developer at <gbramdewilde@gmail.com>.

=cut

=head1 NAME

export.pl - Creates a delimited file from data out of the mongo database

=head1 SYNOPSIS

export.pl [options]

Use --help to see options, --man to see extended manual

by Bram de Wilde (gbramdewilde@gmail.com)

=head1 DESCRIPTION

B<export> a script to create an excell compatible delimited file with data form the mongo object oriented database.

=cut

use strict;
use warnings;
use MIME::Lite;
use JSON;
use BitQC;

######################################################################################
#CREATE A BiTQC OBJECT AND PREPARE THE ANALYSIS SERVER
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'columns'		=> { required => 1, type => "string", array => 1},
		'where' 		=> { required => 1, type => "string"},
		'exportcol'		=> { required => 1, type => "string", default => 'variants'},
		'uniquecol'		=> { type => "string", default => 'variants_unique'},
		'filename'		=> { type => "string"},
		'delimiter' 	=> { type => "string", default => "\t"},
		'export'		=> { type => "string"},
		'plotscoll'		=> { type => "string", default => "plots"}

	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#variables
my $WHERE = $BitQC->getRunConfig('where');
$WHERE = JSON->new->utf8->decode($WHERE) unless (ref($WHERE) eq 'HASH');
my $ADVANCEDFILTER = $BitQC->getRunConfig('filter');
my $EXPORTCOL = $BitQC->getRunConfig('exportcol');
my $UNIQUECOL = $BitQC->getRunConfig('uniquecol');
my $COLUMNS = $BitQC->getRunConfig('columns');
my $TO_EMAIL   = $BitQC->getRunConfig('email_to');
my $FROM_EMAIL = $BitQC->getRunConfig('email_from');
my $FILENAME = $BitQC->getRunConfig('filename');
my $DELIMITER = $BitQC->getRunConfig('delimiter');
my %DELIMITERS = (
	'comma'		=> ",",
	'tab'		=> "\t",
	'semicolon'	=> ";",
	'space'		=> " "
);
$DELIMITER = $DELIMITERS{$DELIMITER} if ($DELIMITERS{$DELIMITER});
my $EXPORT = $BitQC->getRunConfig('export');
my $PLOTSCOLL = $BitQC->getRunConfig('plotscoll');

# create and change to working dir
my $wd = $BitQC->workingDir();

# grab the current time
my @now = localtime();
my $timeStamp = sprintf("%04d-%02d-%02d_%02d:%02d:%02d", 
                        $now[5]+1900, $now[4]+1, $now[3],
                        $now[2],      $now[1],   $now[0]);
my $filename = $timeStamp;
$filename .= '_'.$FILENAME if ($FILENAME);
$filename .= '_export';
$filename =~ s/\s/_/g;

###########################################################################
# FETCHING RESULT DATA
###########################################################################

# timeout not usefull in this backend script
$MongoDB::Cursor::timeout = -1; # no timeout

my $columnscursor 	= $BitQC->{DatabaseAdapter}->findResult(
	collection 	=> $UNIQUECOL
);

my @mongoids;
my %columns;
my %requestcolumns;
my %datatypes;
my @factors;
my @numericals;
my @bools;

# get the columns for the query
while (my $column = $columnscursor->next) {
	my $dotnotation =  $column->{'_id'};
	my $colname = $column->{'name'};
	# if requested add the culumn and its name to the %columns hash
	$columns{$dotnotation} = $colname if (grep {$_ eq $dotnotation} @{$COLUMNS});
	# add all the requested columns and all the columns with a mongo id to the %requestcolumns hash
	$requestcolumns{$dotnotation} = 1 if ((grep {$_ eq $dotnotation} @{$COLUMNS}) || $column->{'type'} eq 'mongo_id');
	# create an array with all the mongoid columns
	push(@mongoids, $column->{'querykeys'}) if ($column->{'type'} eq 'mongo_id');
	push(@numericals, $column->{'querykeys'}) if ($column->{'type'} eq 'numerical');
	push(@bools, $column->{'querykeys'}) if ($column->{'type'} eq 'bool');
	# create an array with all the boolean and text field columns
	push (@factors, $dotnotation) if ($column->{'type'} eq 'bool' || $column->{'type'} eq 'text');
	$datatypes{$colname} = $column->{'type'};
}

if ($ADVANCEDFILTER && $ADVANCEDFILTER ne 'null'){
	$WHERE = _mergehash($WHERE,$ADVANCEDFILTER);
}

# turn the mongo id column into mongo id's in the query
my @querymongoids;
foreach my $mongoid (@mongoids){
	my @mongoid = @{$mongoid};
	my $id_val = _gethashbyarray($WHERE,$mongoid);
	if($id_val){
		my $ids = _createmongoid($id_val);
		_sethashbyarray($WHERE,$mongoid,$ids);
		push @querymongoids,\@mongoid;
	}
}

my @querybools;
foreach my $bool (@bools){
	my @bool=@{$bool};
	my $bool_val = _gethashbyarray($WHERE,$bool);
	if($bool_val){
		my $boolean = $bool_val ? boolean::true : boolean::false;
		_sethashbyarray($WHERE,$bool,$boolean);
		push (@querybools,\@bool);
	}
}

my @querynumericals;
foreach my $number (@numericals){
	my @number = @{$number};
	my $number_val = _gethashbyarray($WHERE,$number);
	if($number_val){
		if (ref($number_val) eq "HASH") {
			# if it is a hash we are probably using an operator to query (eg. $in, $nin, $all, $elemtmatch...)
			# so we convert each sub element to be numeric
			foreach my $operator (keys %{$number_val}) {
				if (ref($number_val->{$operator}) eq "ARRAY") {
					# replace each element of the array with its mongoid object 
					foreach my $value (@{$number_val->{$operator}}){
						my $newval += $value;
						$value += $newval;
					}
				} else  {
					# replace the number_val by its mongo object id
					my $newval += $number_val->{$operator};
					$number_val->{$operator} = $newval;
				}
			} 
		} else {
			my $newval += $number_val;
			$number_val = $newval;
		}
		_sethashbyarray($WHERE,$number,$number_val);
		push (@querynumericals,\@number);
	}
}

my $where = _objecttodotnotation($WHERE);

my $mongodb    = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
my $collection = $mongodb->$EXPORTCOL;

#print Dumper (%requestcolumns);

my $cursor = $collection->find($where);

# only get the requested columns
$cursor->fields(\%requestcolumns);
# allow reading form slave nodes
#$cursor->slave_okay(1);

###########################################################################
# WRITE RESULT TO A .CSV FILE OR THE MONGODATABASE
###########################################################################

my $outputfile;
my $outfile;
my %record;
if (!$EXPORT){
	# create local file object
	$outputfile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
	    'filetype' => 'csv',
		'file' => $wd.$filename.'.csv',
	    'type' => 'local'
	});
	$outfile = $outputfile->getWritePointer();

	#Create CSV-file from data
	# pritn header
	foreach my $column (@{$COLUMNS}){
		print $outfile $columns{$column}.$DELIMITER;
	}
	print $outfile "\n";
} elsif ($EXPORT eq 'mongodb'){

	my @header;
	
	$filename =~ s/_/ /g;

	my @recordfactors;

	foreach my $column (@{$COLUMNS}){
		# add column to the header
		my $colname = $columns{$column};
		$colname =~ s/\.//g;
		push (@header, $colname);
		#$title .= $columns{$column};
		push (@recordfactors , $colname) if (grep {$_ eq $column} @factors);
	}

	my @samples;
	foreach my $id (@{$where->{'sa.id'}->{'$in'}}){
		push (@samples,$id->value);
	}

	%record = (
		"sampleids" => \@samples,
		"data" => {},
		"factor" => \@recordfactors,
		"header" => \@header,
		"name" => $filename
	);
}

my $j = 1;
while (my $doc = $cursor->next) {
	# delete the _id field as we have not asked for it but always get it anyway
	delete $doc->{'_id'};

	print "Processed $j variants\n" unless ($j % 100);

	# remove samples we did not request
	if ($doc->{sa}){
		my @samples;
		foreach my $sample (@{$doc->{sa}}){ 
			foreach my $sampleid (@{$where->{'sa.id'}->{'$in'}}){
				if ($sample->{id}->value eq $sampleid){
					delete $sample->{'id'};
					push (@samples, $sample) ;
					last;
				}
			}
		}
		$doc->{sa} = \@samples;
	}

	# find the array fields in the response doc
	my $arrays = _getarrays($doc);
	# # convert $doc object into table
	my $table = _obj2table($doc,$arrays,\%columns);

	# remove identical rows from the table
	my %table;
	foreach my $row (@{$table}){
		my $line;
		# create a line to be used as a hash key (miking it unique)
		# values used depend on the output format requested
		foreach my $column (@{$COLUMNS}){
		#foreach my $column (sort(keys %columns)){
			if (!$EXPORT){
				my $printval = $row->{$column} ? $row->{$column} : "-";
				$printval = encode_json($printval) if (ref($printval));
				$line .= $printval.$DELIMITER;
			} elsif ($EXPORT eq 'mongodb'){
				my $printval = $row->{$column} ? $row->{$column} : "";
				$printval = encode_json($printval) if (ref($printval));
				$line .= $printval.$DELIMITER;
			}
		}
		$table{$line} = 1;
	}

	#print Dumper ($table, %table);

	foreach my $line (keys %table){		
		if (!$EXPORT){
			print $outfile $line."\n";
		} elsif ($EXPORT eq 'mongodb'){
			# split the line again and add it to the data frame under the right column
			my @line = split($DELIMITER,$line);
			my $i = 0;
			#foreach my $column (sort(keys %columns)){
			foreach my $column (@{$COLUMNS}){
				my $colname = $columns{$column};
				$colname =~ s/\.//g;
				my $value;
				if ($datatypes{$colname} eq 'numerical'){
					$value += $line[$i];
				} else {
					$value = $line[$i];
				}
				push (@{$record{data}{$colname}}, $line[$i]);
				$i++;
			}
		}
	}
	$j++;
}


if (!$EXPORT){
	#Close csv file
	close $outfile;

	my $filesize = (-s $wd.$filename.'.csv.gz')/1000000;

	my $file = $outputfile->getInfo('file');


	###########################################################################
	# SEND E-MAIL WITH THE RESULT
	###########################################################################
	foreach my $to_email ( @{$TO_EMAIL} ) {

		if($filesize <= 5){
			$BitQC->sendEmail(
				to 		=> $to_email,
				from 	=> $FROM_EMAIL,
				subject	=> "Table export - success",
				message	=> "Dear $to_email, <br><br>You requested a table export from Seqplorer.<br>Your results can be found in the included CSV-file.<br><br>Kind regards",
				filenames=> [ $file ]
			);
			#Delete temporary file
			#unlink($filename);
		}
		else {
			$BitQC->sendEmail(
				to 		=> $to_email,
				from 	=> $FROM_EMAIL,
				subject	=> "Table export - failed",
				message	=> "Dear $to_email, <br><br>You requested a table export from Seqplorer.<br>Unfortunately your results are too big to send by email. The result is available on the server with file name ".$wd.$filename.".csv.gz Please use a more strict filter to receive your results by mail.<br><br>Kind regards",
			);
		}

		$BitQC->log_message( message => "Notification sent to $to_email" );
	}

} elsif ($EXPORT eq 'mongodb'){

	my $plots_collection = $mongodb->$PLOTSCOLL;
	
	my $freqdistrecord = $plots_collection->insert( \%record, { safe => 1 } );

	print $freqdistrecord."\n";

	foreach my $to_email ( @{$TO_EMAIL} ) {
		$BitQC->sendEmail(
			to 		=> $to_email,
			from 	=> $FROM_EMAIL,
			subject	=> "Statistics export - success",
			message	=> "Dear $to_email, <br><br>The data you requested is avaialble for viewing.<br><br>Kind regards",
		);
		
		$BitQC->log_message( message => "Notification sent to $to_email" );
	}
}


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#SUBROUTINES														+
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

# Get all arrays that are not end-level
# Arrays with another array or hash as value
sub _getarrays{
	my $doc = shift;
	my $dotkey = shift;
	my $arrays = shift;
	my %arrays;

	%arrays = %{$arrays} if ($arrays);
 	
 	if (ref($doc) eq 'ARRAY'){
 		# get the number of . matches in the $dotkey
 		# this gives us the level of desnet into the doc
 		my $number =()= $dotkey =~ /\./g;

 		$arrays{$number}{$dotkey} +=1;

 		# get into the array;
 		foreach my $element (@{$doc}){
			%arrays = %{_getarrays($element,$dotkey,\%arrays)};
		}
 	} elsif (ref($doc) eq 'HASH'){
 		# get into the hash
		foreach my $key (keys %{$doc}){
			my $newkey = '';
			if ($dotkey){
				$newkey = $dotkey.'.'.$key;
			} else {
				$newkey = $key
			}
			my $return = _getarrays($doc->{$key},$newkey,\%arrays);
			%arrays = %{$return} if ($return);

		}
 	}
	return (\%arrays);
}

# descend in to a nested hash following the keys givven by an array and return the deepest result
sub _gethashbyarray{
	# a list of valid mongodb operators
	my @operators =('$ne','$in','$all','$nin','$elemMatch','$and','$or','$nor');

	my $hash = shift;
	my $array = shift;
	# we descend into the hash using the array values as keys
	foreach my $key (@{$array}){
		if (exists($hash->{$key})){
			# key exists in this hash, we continue with the new hash
			$hash = $hash->{$key}; # set the value attached to the key of the hash to be the new hash
		} else {
			# we could have received an operator query
			my $match = 0;
			foreach my $operator (@operators) {
				if ($hash->{$operator} && $hash->{$operator}->{$key}) {
					# valud operator found, we continue with the new hash
					$hash = $hash->{$operator}->{$key};
					$match =1;
					last; # we don't nee to check the others
				} 
			}
			# if we didn't get a match  we return false
			return (0) unless ($match);
		}
	}
	return ($hash);
}

# set the value of a nested hash to a certain value by following an array as keys
sub _sethashbyarray
{
	my $hash = shift;
	my $array = shift;
	my $set = shift;
	if (ref($hash) eq "HASH"){
		my %return;
		# buld a new hash identical to the input hash but when the key matches the first element of the input array
		# we desend into the hash and repeat the function
		my $first = shift(@{$array});
		foreach my $key (keys %{$hash}){
			if (defined($first) && $key eq $first){
				$return{$key} = _sethashbyarray($hash->{$key},$array,$set)
			} else {
				$return{$key} = $hash->{$key};
			}
		}
		# return a ref to the newly created hash
		return (\%return);
	} else {
		# if we did not receive a hash, we return the value we received
		return ($set);
	}
}

sub _createmongoid{
	my $value = shift;
	if (ref($value) eq "HASH") {
		# if it is a hash we are probably using an operator to query (eg. $in, $nin, $all, $elemtmatch...)
		# so we convert each sub element to be an mongoid
		foreach my $operator (keys %{$value}) {
			if (ref($value->{$operator}) eq "ARRAY") {
				# replace each element of the array with its mongoid object 
				foreach my $id (@{$value->{$operator}}){
					$id = MongoDB::OID->new(value => $id);
				}
			} else  {
				# replace the value by its mongo object id
				$value->{$operator} = MongoDB::OID->new(value => $value->{$operator});
			}
		} 
	} elsif (ref($value) eq "ARRAY") {
		# replace each element of the array with its mongoid object 
		foreach my $id (@{$value}){
			$id = MongoDB::OID->new(value => $id);
		}
	}else {
		# replace the value by its mongo object id
		$value = MongoDB::OID->new(value => $value);
	}
	return ($value);
}

sub _objecttodotnotation{
	my $value = shift;
	my $dotkey = shift;

	my $return; # hashref to contain the dotnotated object
	if (ref($value) eq "HASH") {
		foreach my $key (keys %{$value}) {
			# check if we are using an operator to query (eg. $in, $nin, $all, $elemtmatch...)
			# we convert each to its dot notation
			# my @operators =('$ne','$in','$all','$nin','$elemMatch','$and','$or','$nor');
			if ($key =~ /^\$/){
				my $returnobj = _objecttodotnotation($value->{$key}, '');
				# we leave the mongo operator in place and return the subobject
				$return->{$dotkey}->{$key} = $returnobj;
			} else {
				my $newkey = '';
				if ($dotkey){
					$newkey = $dotkey.'.'.$key;
				} else {
					$newkey = $key
				}
				my $returnobj = _objecttodotnotation($value->{$key}, $newkey);

				if (ref($returnobj) eq "HASH"){
					foreach my $objkey (keys $returnobj){
						$return->{$objkey} = $returnobj->{$objkey};
					}
				} elsif ($dotkey) {
					$return->{$dotkey} = $returnobj;
				} else {
					$return->{$newkey} = $returnobj;
				}
			}
		}
	} elsif (ref($value) eq "ARRAY") {
		# arrays can contain values but also hashes
		# we convert each element to its dot notation 
		foreach my $val (@{$value}){
			my $returnobj = _objecttodotnotation($val, '');
			push (@{$return}, $returnobj);
		}
	
	}elsif (ref($value) eq 'JSON::XS::Boolean'){
		# json boolean true is not the same as mongodb boolean true!
	    $value = $value ? boolean::true : boolean::false;
	    return($value);
	}
    else {
		return($value);	
	}
	return ($return);
}

sub _obj2table{
	my $obj = shift;
	my $arrays = shift;
	my $columns = shift;

	my @results = ($obj);
	foreach my $level (sort { $a <=> $b } keys(%{$arrays}) ){
		foreach my $key (keys %{$arrays->{$level}}){
			my @keys = split(/\./,$key);
			
			my $i=0;
			my @oldresults = @results;
			foreach my $line (@oldresults){
				my @newlines;
				my $arrayfield = _gethashbyarray($line,\@keys);
				foreach my $element (@{$arrayfield}){
					my $newline = $line;
					my @setkey = @keys;
					$newline = _sethashbyarray ($newline,\@setkey,$element);
					push (@newlines, $newline);
				}
				splice (@results,$i,1,@newlines);
				$i += @newlines;
			}
		}
	}
	foreach my $line (@results){
		$line = _dehash( $line, $columns);
	}
	return (\@results);
}

# Create a hash with dot-notation from nested hashes
sub _dehash{
    my $hash = shift;
    my $columns = shift;
    my $dotkey = shift;
    my %columns = %{$columns};

    my %result;
	if (ref($hash) eq 'HASH'){
		foreach my $key (keys %{$hash}){
			my $newkey = '';
			if ($dotkey){
				$newkey = $dotkey.'.'.$key;
			} else {
				$newkey = $key;
			}
			if ($columns{$newkey}){
				$result{$newkey} = $hash->{$key};
			} else {
				my $result = _dehash($hash->{$key},$columns,$newkey);
				foreach my $resultkey (keys %{$result}){
					$result{$resultkey} = $result->{$resultkey};
				}
			}
		}
		return \%result;
	} else {
		return $hash;
	}
    
}
sub _mergehash{
    my $hash = shift;
    my $mergehash = shift;

    #my %result = %{$hash};
	foreach my $key (keys %{$mergehash}){
		if (!$hash->{$key}){
			# add the missing key to the hash
			$hash->{$key} = $mergehash->{$key};
		} else {
			if (ref($mergehash->{$key}) eq 'HASH'){
				# merge the 2 subhashes
				$hash->{$key} = _mergehash ($hash->{$key},$mergehash->{$key});

			} elsif (ref($mergehash->{$key}) eq 'ARRAY'){
				foreach my $element (@{$mergehash->{$key}}){
					# add element if not already in the array
					push (@{$hash->{$key}}, $element) unless (grep {$_ eq $element} @{$hash->{$key}});
				}
			} else {
				# merge the query keys in in $in syntax uless they are the same
				unless ($hash->{$key} eq $mergehash->{$key}){
					my @queryarray;
					push (@queryarray,$hash->{$key});
					push (@queryarray,$mergehash->{$key});
					$hash->{$key} = {'$in' => \@queryarray};
				}
			}
		}
	}
	return $hash;
}
__END__

=head1 OPTIONS

=head3 export options:

=over 8

=item B<--columns>

The name of the column you want to export. Specify multiple times to export multiple columns.
(the default mongodb dot notation for complex columns) [required]

=item B<--where>

The query to search for the records to get exported, in json format. 
(hint: use single quotes to encapsulate json, mongoids can be specified as plain text strings)

=item B<--exportcol>

The collection to export records from [variants]

=item B<--uniquecol>

The collection that contains the unique column names for the export collection [variants_unique]

=item B<--filename>

The filename to store the variants in, will be prefixed with a time stamp and suffixed for _export.csv.gz

=item B<--delimiter>

The delimiter to use in the export file, defaults to tab, creating a tab delimited file.
For easy of command line operation the string version of some common delimiters can be used 
(tab, comma, semicolon, of space).[tab]

=back

=head3 BitQC options:

Options used to configure the BitQC module used for logging and script configuration

=over 8

=item B<-h --help>

Print a brief help message and exit.

=item B<-m --man>

Display the manual page.

=item B<-v --verbose>

Print more verbose information when running. Mostly for debug purposes. [false]

=item B<--email_to>	

A list of valid email addresses, specify multiple times for multiple emails to be sent.
An email will be sent to all adresses specified on success or failure.

=item B<--email_from>

The email address sending the notification emails.

=item B<--errormessage>

The error message to be sent when the script fails. either a text or html, the message or a file containing the message.

=item B<--errorsubject>

The subject of the mail being sent on error.

=item B<--config_id>

The mongodb script config id to use in this analysis.

=item B<--server_id>

The mongodb server id to perform the analysis with.

=item B<--bitqc_host>

host to running the BitQC database. [localhost]

=item B<--bitqc_port>

port the BitQC database is running on. [27017]

=item B<--bitqc_db>

The BitQC database name used. [bitqc]

=item B<--log_coll>

The BitQC logging collection. [log]

=item B<--server_coll>

The BitQC server collection. [servers]

=item B<--config_coll>

The BitQC config collection. [config]

=item B<--genome_coll>

The BitQC genomes collection. [genome]

=item B<--db_config>

whether to use the BitQC database for storing the run config. [true]

=item B<--startlog>

Whether to use the BitQC logging in the	database, if false logging will be printed to 
STDOUT. [true]

=back

=cut