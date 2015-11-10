#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use File::Copy;
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
		'vcf'			=> { type => 'string' },
		'db_config'   	=> { default => boolean::false, type => 'bool' },
		'name'			=> { type => 'string' }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $VCF 			= $BitQC->getRunConfig('vcf');
my $NAME 			= $BitQC->getRunConfig('name');
my $REMOVE     		= $BitQC->getRunConfig('remove');

my $BGZIP_COMMAND 	= $BitQC->getCommand('bgzip');
my $GZIP_COMMAND 	= $BitQC->getCommand('gzip');
my $GUNZIP_COMMAND 	= $BitQC->getCommand('gunzip');
my $TABIX_COMMAND 	= $BitQC->getCommand('tabix');
my $VCFSORT_COMMAND = $BitQC->getCommand('vcf-sort');

my $GATK_INDEX = $BitQC->getGenomeIndex('gatk');

my $GATK_DICT_INDEX = $GATK_INDEX;
$GATK_DICT_INDEX =~ s/fasta$/dict/;

######################################################################################
# START MERGING BAM FILES
######################################################################################

# add the right extension to the output file name
$NAME .= ".vcf.gz" unless ( $NAME =~ /\.vcf\.gz$/ );

# is the vcf file compressed?
# TODO: make this check more intelligent: is it bgzip compressed?
if ($VCF =~ /\.gz$/){
	# renome the input file
	move( $VCF, $NAME."-unsorted.vcf.gz" ) 
	or copy( $VCF, $NAME."-unsorted.vcf.gz" ) 
		or $BitQC->log_error(message => "Renaming/Copy of $VCF to $NAME failed");

	$BitQC->log_message(message => "VCF file $VCF appears compressed, uncompressing to $NAME-unsorted.vcf");

	$BitQC->run_and_log(
		message => "Uncompressing vcf file",
		command => "$GZIP_COMMAND -d $NAME-unsorted.vcf.gz"
	);
} else {
	# rename the input file
	move( $VCF, $NAME."-unsorted.vcf" ) 
		or copy( $VCF, $NAME."-unsorted.vcf.gz" )
			or $BitQC->log_error(message => "Renaming/Copy of $VCF to $NAME failed");
}

# needs to be sorted in the same order as the GATK reference (DICT file)
$BitQC->run_and_log(
	message => "Sort the vcf file",
	command => "$VCFSORT_COMMAND $GATK_DICT_INDEX $NAME-unsorted.vcf | $BGZIP_COMMAND -c > $NAME"
);

# index the vcf file generated
$BitQC->run_and_log(
	message => "Indexing vcf file",
	command => "$TABIX_COMMAND -p vcf $NAME"
);


######################################################################################
# FINISH SCRIPT
######################################################################################

unlink($NAME."-unsorted.vcf") if ($REMOVE);

# finish logging
$BitQC->finish_log( message => "Job completed: $VCF sorted, compressed and indexed" );
