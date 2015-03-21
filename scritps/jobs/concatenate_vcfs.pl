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
		'vcfchuncks'	=> { type => 'string', array => 1 }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $NAME            = $BitQC->getRunConfig('name');
my @VCF_CHUNCKS     = @{$BitQC->getRunConfig('vcfchuncks')};
my $REMOVE        	= $BitQC->getRunConfig('remove');

#Prepare commands
my $VCFCONCAT_COMMAND 	= $BitQC->getCommand('vcf-concat');
my $BGZIP_COMMAND 		= $BitQC->getCommand('bgzip');
my $TABIX_COMMAND 		= $BitQC->getCommand('tabix');
my $VCFSORT_COMMAND 	= $BitQC->getCommand('vcf-sort');

my $GATK_INDEX = $BitQC->getGenomeIndex('gatk');

my $GATK_DICT_INDEX = $GATK_INDEX;
$GATK_DICT_INDEX =~ s/fasta$/dict/;

######################################################################################
# START MERGING BAM FILES
######################################################################################

$NAME .= ".vcf.gz" unless ( $NAME =~ /\.vcf\.gz$/ );

my $vcfchuncks;
foreach (@VCF_CHUNCKS){
	$vcfchuncks .= " ".$_;
}

if ( @VCF_CHUNCKS > 1 ) {

	$BitQC->run_and_log(
		message => "Concatenating temporary vcf files.",
		command =>
"$VCFCONCAT_COMMAND $vcfchuncks > $NAME-unsorted.vcf"
	);

}
else {
	$vcfchuncks =~ s/\s$//g;    # removing whitespace from name

		$BitQC->log_message( message =>
"Only one vcf file: renaming $vcfchuncks to $NAME instead of concatenating."
	);

	rename( $vcfchuncks, $NAME . "-unsorted.vcf.gz" );

	$BitQC->run_and_log(
		message => "Uncompressing vcf file",
		command => "$BGZIP_COMMAND -d $NAME-unsorted.vcf.gz"
	);

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

if ($REMOVE) {
	$BitQC->log_message( message => "Removing concatenated vcf files." );

	foreach (@VCF_CHUNCKS) {
		unlink($_);
		unlink( $_ . ".tbi" );
	}
	unlink( $NAME . "-unsorted.vcf" );
}

# finish logging
$BitQC->finish_log( message => "Job completed: vcf files merged, sorted and indexed" );
