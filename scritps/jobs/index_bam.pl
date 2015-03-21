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
		'bam'			=> { type => 'string' }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $BAM_FILE = $BitQC->getRunConfig('bam');

#Get samtools
my $BITQC_SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');

######################################################################################
# START INDEXING BAM FILE
######################################################################################

# get path and file name
my $bamname;
my $bampath;
( $bamname, $bampath, my $bamext ) = fileparse( $BAM_FILE, '\..*' );
# remove index if exists
unlink ("$bampath$bamname.bam.bai") if (-e "$bampath$bamname.bam.bai");

$BitQC->run_and_log(
	message => "Creating index for $bamname",
	command => "$BITQC_SAMTOOLS_COMMAND index $BAM_FILE $bampath$bamname.bam.bai"
);

######################################################################################
# FINISH SCRIPT
######################################################################################

# finish logging
$BitQC->finish_log( message => "Job completed: indexing of bam file $BAM_FILE" );
