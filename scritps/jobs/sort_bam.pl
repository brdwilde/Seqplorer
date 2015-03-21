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
my $REMOVE   = $BitQC->getRunConfig('remove');

#Get command
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');

######################################################################################
# START SORTING BAM FILE
######################################################################################

my $bamname;
my $bampath;
( $bamname, $bampath, my $bamext ) = fileparse( $BAM_FILE, '\..*' );

my $input = $bampath.$bamname."-unsorted.bam";
rename ($BAM_FILE, $input);

$BitQC->run_and_log(
	message => "Sorting file $BAM_FILE",
	command => "$SAMTOOLS_COMMAND sort $input $bampath$bamname"
);

######################################################################################
# FINISH SCRIPT
######################################################################################

#Remove temporary files when argument is true
if ($REMOVE) {
	unlink($input);
	$BitQC->log_message(message => "Removed input $input file");
}

# finish logging
$BitQC->finish_log( message => "Job completed: $BAM_FILE sorted");
