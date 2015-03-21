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

my $BAM 	= $BitQC->getRunConfig('bam');
my $REMOVE  = $BitQC->getRunConfig('remove');
my $BUILD   = $BitQC->getRunConfig('genomebuild');

#Get command
my $GATK_COMMAND = $BitQC->getCommand('gatk');
my $ANALYSECOVARIATE_COMMAND = $BitQC->getCommand('analysecovariate');


#Get necessary executables and paths  
my $BITQC_NODE_STORAGE = $BitQC->{node_config}->{paths}->{nodetempdir}->{dir};

#Get index for given organismbuild
my $GATK_INDEX = $BitQC->getGenomeIndex('gatk');

#SNP database
my $SNP_VCF =
    $BitQC->{node_config}->{paths}->{genomedir}->{dir} 
  . $BUILD . "/"
  . $BitQC->{genome}->{files}->{dbsnp}->{path};

######################################################################################
# START GATK RECALIBRATION OF FASTQ FILE
######################################################################################

my $bamname;
my $bampath;
( $bamname, $bampath, my $bamext ) = fileparse( $BAM, '\..*' );

# set some file names
my $infile         = $bampath . $bamname . "-norecal.bam";
my $pre_recalfile  = $bampath . $bamname . "-pre-recal-calmetrics.csv";
my $pre_recalfolder = $bampath . "covariate_plots_pre/";
mkdir $pre_recalfolder;
my $post_recalfile = $bampath . $bamname . "-post-recal-calmetrics.csv";
my $post_recalfolder = $bampath . "covariate_plots_post/";
mkdir $post_recalfolder;

# rename the input file (and its index)
rename( $BAM, $infile );
rename( $bampath . $bamname . ".bai", $bampath . $bamname . "-norecal.bai" );

$BitQC->log_message( message =>
	  "Performing base quality recalibration for $BAM" );

$BitQC->run_and_log(
	message => "Counting covariates",
	command =>
"$GATK_COMMAND -l INFO "
	  . "-R $GATK_INDEX --knownSites $SNP_VCF -I $infile "
	  . "-T CountCovariates -cov ReadGroupCovariate -cov QualityScoreCovariate "
	  . "-cov CycleCovariate -cov DinucCovariate -recalFile $pre_recalfile"
);

$BitQC->run_and_log(
	message => "Recalibrating quality scores",
	command =>
"$GATK_COMMAND -l INFO -R $GATK_INDEX -I $infile -T TableRecalibration --out $BAM -recalFile $pre_recalfile"
);

$BitQC->run_and_log(
	message => "Generating plots and reports.",
	command =>
"$ANALYSECOVARIATE_COMMAND --recal_file $pre_recalfile --output_dir $pre_recalfolder"
);

$BitQC->run_and_log(
	message => "Recounting covariates after recalibration",
	command =>
"$GATK_COMMAND -l INFO -R $GATK_INDEX --knownSites $SNP_VCF -I $BAM -T CountCovariates -cov ReadGroupCovariate -cov QualityScoreCovariate -cov CycleCovariate -cov DinucCovariate -recalFile $post_recalfile"
);

$BitQC->run_and_log(
	message => "Generating plots and reports.",
	command =>
"$ANALYSECOVARIATE_COMMAND --recal_file $post_recalfile --output_dir $post_recalfolder"
);

$BitQC->log_message( message =>
	  "Moving file from local to shared directory" );


######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	unlink($infile);
	unlink( $bampath . $bamname . "-norecal.bai" );
	$BitQC->log_message( message => "Removed input $infile file" );
}

# finish logging
$BitQC->finish_log(
	message => "Job completed: $BAM file recalibrated using the GATK" );
