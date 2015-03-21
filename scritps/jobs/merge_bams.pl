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
		'name'			=> { type => 'string' },
		'bamchuncks'    => { type => 'string', array => 1}
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $NAME 			= $BitQC->getRunConfig('name');
my $BAMCHUNCKS 		= $BitQC->getRunConfig('bamchuncks');
my $REMOVE          = $BitQC->getRunConfig('remove');

#Get command
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');


######################################################################################
# START MERGING BAM FILES
######################################################################################

my $bamname;
my $bampath;
( $bamname, $bampath, my $bamext ) = fileparse( $NAME, '\..*' );

if ( -e $NAME){
	# the output file already exists! we rename it first
	rename( $NAME, $bampath . $bamname . "-unmerged.bam" );
}

my $bam_chuncks;
foreach (@$BAMCHUNCKS) {
	$bam_chuncks .= $_." ";
}

if ( @$BAMCHUNCKS > 1 ) {

	$BitQC->run_and_log(
		message => "Merging temporary bam files.",
		command =>
		  "$SAMTOOLS_COMMAND merge $NAME $bam_chuncks"
	);

	$BitQC->log_message( message => "Removing temporary bam chuncks." );

	foreach (@$BAMCHUNCKS) {
		unlink($_) if ($REMOVE);
	}
}
else {

	$BitQC->log_message( message =>
"Only one bam file: renaming $bam_chuncks to $NAME instead of merging."
	);
	$bam_chuncks =~ s/\s$//g;
	rename( $bam_chuncks, "$NAME" );
}

######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	unlink($bampath . $bamname . "-unmerged.bam");
}

# finish logging
$BitQC->finish_log( message => "End job: merging bam files!" );
