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
		'vcf'			=> { type => 'string' }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $VCF 		= $BitQC->getRunConfig('vcf');
my $OUTPUT_DIR 	= $BitQC->getRunConfig('outdir');
my $REMOVE     	= $BitQC->getRunConfig('remove');
my $BUILD      	= $BitQC->getRunConfig('genomebuild');

#Get necessary executables and paths
my $GATK_COMMAND  = $BitQC->getCommand('gatk2');
my $BGZIP_COMMAND = $BitQC->getCommand('bgzip');

#Get fasta for given organismbuild
my $GATK_INDEX = $BitQC->getGenomeIndex('gatk');

#SNP databases
my $HAPMAP_SNP_VCF =
    $BitQC->{node_config}->{paths}->{genomedir}->{dir} 
  . $BUILD . "/"
  . $BitQC->{genome}->{files}->{hapmap}->{path};
my $OMNI_SNP_VCF =
    $BitQC->{node_config}->{paths}->{genomedir}->{dir} 
  . $BUILD . "/"
  . $BitQC->{genome}->{files}->{omni}->{path};
my $DBSNP_SNP_VCF =
    $BitQC->{node_config}->{paths}->{genomedir}->{dir} 
  . $BUILD . "/"
  . $BitQC->{genome}->{files}->{dbsnp}->{path};
my $MILLS_SNP_VCF =
    $BitQC->{node_config}->{paths}->{genomedir}->{dir} 
  . $BUILD . "/"
  . $BitQC->{genome}->{files}->{mills}->{path};
my $G1000_SNP_VCF =
    $BitQC->{node_config}->{paths}->{genomedir}->{dir} 
  . $BUILD . "/"
  . $BitQC->{genome}->{files}->{g1000}->{path};

######################################################################################
# START GATK RECALIBRATION OF VCF FILE
######################################################################################

my $vcfname;
my $vcfpath;
my $vcfext;
( $vcfname, $vcfpath, $vcfext ) = fileparse( $VCF, '\..*' );

if ( $VCF =~ /\.gz$/ ) {
	# vcf is compressed: uncompress and update file info
	$BitQC->run_and_log(
		message => "Uncompressing vcf file",
		command => "$BGZIP_COMMAND -d $VCF"
	);
	$VCF = $vcfpath . $vcfname . '.vcf';
	( $vcfname, $vcfpath, $vcfext ) = fileparse( $VCF, '\..*' );
}

my $norecal_snp_file = $vcfpath . $vcfname . "-norecal-snp.vcf";
my $norecal_indel_file = $vcfpath . $vcfname . "-norecal-indel.vcf";
my $snprecalfile    = $vcfpath . $vcfname . "_snp.recal";
my $recalfile    = $vcfpath . $vcfname . "_indel.recal";
my $snptranchesfile = $vcfpath . $vcfname . "._snp.tranches";
my $snpplotsfile    = $vcfpath . $vcfname . "_snp.plots";
my $tranchesfile = $vcfpath . $vcfname . "_indel.tranches";
my $plotsfile    = $vcfpath . $vcfname . "_indel.plots";

rename( $VCF, $norecal_snp_file );
$BitQC->log_message(
	message => "Performing variant quality recalibration for $VCF" );

#START WITH INDEL
$BitQC->run_and_log(
	message => "Creating Gaussian mixture model for SNP recalibration",
	command => "$GATK_COMMAND -l INFO "
	  . " -R $GATK_INDEX --input $norecal_snp_file"
	  . " -T VariantRecalibrator "
	  . " -resource:hapmap,known=false,training=true,truth=true,prior=15.0 $HAPMAP_SNP_VCF"
	  . " -resource:omni,known=false,training=true,truth=true,prior=12.0 $OMNI_SNP_VCF"
	  . " -resource:1000G,known=false,training=true,truth=false,prior=10.0 $G1000_SNP_VCF"
	  . " -resource:dbsnp,known=true,training=false,truth=false,prior=2.0 $DBSNP_SNP_VCF"
	  . " -an DP -an QD -an FS -an MQRankSum -an ReadPosRankSum "
	  . " -recalFile $snprecalfile -mode SNP"
	  . " -tranchesFile $snptranchesfile -rscriptFile $snpplotsfile"
);

$BitQC->run_and_log(
	message => "Recalibrating variants in SNP $VCF file.",
	command => "$GATK_COMMAND -T ApplyRecalibration -R $GATK_INDEX -input $norecal_snp_file"
    . " -mode SNP --ts_filter_level 99.9 -tranchesFile $snptranchesfile -recalFile $snprecalfile -o $norecal_indel_file"
);

#REPEAT FOR INDEL
$BitQC->run_and_log(
	message => "Creating Gaussian mixture model for INDEL recalibration",
	command => "$GATK_COMMAND -l INFO "
	  . " -R $GATK_INDEX --input $norecal_indel_file"
	  . " -T VariantRecalibrator"
	  . " -resource:mills,known=false,training=true,truth=true,prior=12.0 $MILLS_SNP_VCF"
	  . " -resource:dbsnp,known=true,training=false,truth=false,prior=2.0 $DBSNP_SNP_VCF"
	  . " -an DP -an FS -an MQRankSum -an ReadPosRankSum -mode INDEL"
	  . " --maxGaussians 4"
	  . " -recalFile $recalfile"
	  . " -tranchesFile $tranchesfile -rscriptFile $plotsfile"
);

$BitQC->run_and_log(
	message => "Recalibrating variants in INDEL $VCF file.",
	command => "$GATK_COMMAND -T ApplyRecalibration -R $GATK_INDEX -input $norecal_indel_file"
    . " -mode INDEL --ts_filter_level 99.9 -tranchesFile $tranchesfile -recalFile $recalfile -o $VCF"
);

$BitQC->run_and_log(
	message => "Compressing recalibrated vcf file.",
	command => "$BGZIP_COMMAND -c $VCF > $VCF.gz"
);


######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	$BitQC->log_message( message => "Removing temporary files." );
	#unlink($tranchesfile);
	unlink($norecal_snp_file);
	unlink($norecal_indel_file);
}

# finish logging
$BitQC->finish_log(
	message => "Job completed: variants recalibrated in $VCF" );
