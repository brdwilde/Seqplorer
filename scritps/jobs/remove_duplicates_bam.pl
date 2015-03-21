#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
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
		'bam'			=> { type => 'string' },
		'sampleid'		=> { type => 'string', array => 1}
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $BAM = $BitQC->getRunConfig('bam');
my $REMOVE = $BitQC->getRunConfig('remove');
my $SAMPLEIDS = $BitQC->getRunConfig('sampleid');

#Get command
my $PICARD_COMMAND = $BitQC->getCommand('picard_markduplicates');

######################################################################################
# START REMOVING DUPLICATES FROM BAM FILE
######################################################################################

my $wd = $BitQC->workingDir();

my $bamname;
my $bampath;
( $bamname, $bampath, my $bamext ) = fileparse( $BAM, '\..*' );

# create some file names
my $input      = $bampath . $bamname . "-duplicates.bam";
my $outfile    = "$bampath$bamname.bam";
my $dupmetrics = "$bampath$bamname-dupmetrics.txt";

# rename input
#rename( $BAM, $input );

#$BitQC->run_and_log(
#	message => "Removing duplicates from $bamname.bam",
#	command =>
#"$PICARD_COMMAND INPUT=$input TMP_DIR=$wd OUTPUT=$outfile METRICS_FILE=$dupmetrics REMOVE_DUPLICATES=false ASSUME_SORTED=true VALIDATION_STRINGENCY=LENIENT"
#);

######################################################################################
# STORE THE RESULTS IN THE MONGO DATABASE
######################################################################################

#if ($SAMPLEIDS){
	open(my $fh, "<", $dupmetrics);

	my %record = (
		"sampleids" => $SAMPLEIDS,
		"data" => {},
		"factor" => [],
		"header" => [],
		"roidata" => { 
			"Fold reads" => [],
			"Fold coverage" => [],
		},
		"roiheader" => ["Fold reads","Fold coverage"],
		"name" => "Duplicate read statistics for ".$bamname,
	);

	my $dataline = 0;
	my $histline = 0;

	while (<$fh>){
		$dataline = 0 if ( /^$/ || /^#/); # this is not a data line (anymore)
		next if ( /^$/ || /^#/); #skip blank and comment lines

		chop;

		my @line = split ('\t',$_);
		if ($line[0] eq 'LIBRARY'){
			$dataline = 1; # following lines will be data lines
			# create data array reference for each field in the %record hash
			foreach (@line){
				if ($_){
					$record{'data'}{$_} = [];
				}
			}
			$record{'header'} = \@line;
		} elsif ($dataline){
			my $i = 0;
			foreach (@line){
				if ($_){
					my $val += $_; # make sure we are in numeric context
					push (@{$record{'data'}}{$record{'header'}[$i]},$val);
				}
				$i++;
			}
		} elsif ($line[0] eq "BIN"){
			$histline = 1;
		} elsif ($histline){
			my $reads += $line[0]; # make sure we are in numeric context
			my $coverage += $line[1]; # make sure we are in numeric context
			push (@{$record{'roidata'}{"Fold reads"}}, $reads);
			push (@{$record{'roidata'}{"Fold coverage"}}, $coverage);
		}

	}

	use Data::Dumper::Simple;
	print Dumper (%record);

#	my $mongodb = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
#	my $plots_collection = $mongodb->$PLOTSCOLL;

	
#	my $freqdistrecord = $plots_collection->insert( \%freqdistrecord, { safe => 1 } );

	# add the plot id of the frequency distribution plot to the stats plot data
#	$plotrecord{cumulativeid} = $freqdistrecord->value;
#	my $plotrecord = $plots_collection->insert( \%plotrecord, { safe => 1 } );

#}

######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	unlink($input);
}

# finish logging
$BitQC->finish_log(
	message => "End job: removing duplicates of bam file: $BAM!" );

