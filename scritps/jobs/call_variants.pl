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
		'bamindex' 		=> { type => 'int'},
		'region'       	=> { type => 'string'},
		'outputfile'	=> { type => 'string'},
		'triofile'		=> { type => 'string'}
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

#config variables
my @BAM = @{ $BitQC->getRunConfig('files') };
my @PAIR;
@PAIR = @{ $BitQC->getRunConfig('bampair') } if ($BitQC->getRunConfig('bampair'));
my @TRIO;
@TRIO = @{ $BitQC->getRunConfig('bamtrio') } if ($BitQC->getRunConfig('bamtrio'));
my $REGION        = $BitQC->getRunConfig('region');
my $BAMINDEX      = $BitQC->getRunConfig('bamindex');
my $OUTPUTFILE    = $BitQC->getRunConfig('outputfile');
my $TRIOFILE 	  = $BitQC->getRunConfig('triofile');
my $OUTPUT_DIR    = $BitQC->getRunConfig('outputdir');
my $GENOMEBUILD   = $BitQC->getRunConfig('genomebuild');
my $MINQUAL       = $BitQC->getRunConfig('minqual');
my $MINCOV        = $BitQC->getRunConfig('mincov');
my $MINSAMPLEQUAL = $BitQC->getRunConfig('minsamplequal');
my $MINSAMPLECOV  = $BitQC->getRunConfig('minsamplecov');
my $ALGORITHM     = $BitQC->getRunConfig('algorithm');
my $CALLOPTIONS   = $BitQC->getRunConfig('calloptions');
my $FILTEROPTIONS = $BitQC->getRunConfig('filteroptions');
my $REMOVE        = $BitQC->getRunConfig('remove');

#Get command
my $SAMTOOLS_COMMAND 	= $BitQC->getCommand('samtools');
my $BCFTOOLS_COMMAND 	= $BitQC->getCommand('bcftools');
my $GATK_COMMAND  		= $BitQC->getCommand('gatk');
my $GATK2_COMMAND  		= $BitQC->getCommand('gatk2');
my $BGZIP_COMMAND 		= $BitQC->getCommand('bgzip');
my $VCFUTILS_COMMAND 	= $BitQC->getCommand('vcfutils');
my $TABIX_COMMAND 		= $BitQC->getCommand('tabix');


my $SAMTOOLS_INDEX = $BitQC->getGenomeIndex('samtools');
my $GATK_INDEX = $BitQC->getGenomeIndex('gatk');

#SNP database
my $POPULATION_BAMS;
$POPULATION_BAMS =
    $BitQC->{node_config}->{paths}->{genomedir}
  . $BitQC->{genome}->{files}->{population_bam}->{path}
  if ( $BitQC->{genome}->{files}->{population_bam}->{path} );

# add the population bams to the bam's to analyse unless they are undefined or we are doing single sample variant calling
push( @BAM, $POPULATION_BAMS ) if ( !$BAMINDEX && $POPULATION_BAMS );

######################################################################################
# EXTRACT VARIANTS TO VCF FILE
######################################################################################

my $callopts = "";

if ($CALLOPTIONS) {
	for my $opt ( keys %{$CALLOPTIONS} ) {
		if ( $CALLOPTIONS->{$opt} ) {
			$callopts .= $opt . " " . $CALLOPTIONS->{$opt} . " ";
		}
		else {
			$callopts .= $opt . " ";
		}
	}
}

my $filteropts = "";

if ($FILTEROPTIONS) {
	for my $opt ( keys %{$FILTEROPTIONS} ) {
		if ( $FILTEROPTIONS->{$opt} ) {
			$filteropts .= $opt . " " . $FILTEROPTIONS->{$opt} . " ";
		}
		else {
			$filteropts .= $opt . " ";
		}

	}
}

if ( $ALGORITHM eq "samtools" ) {
	my $bams = "";
	my $analysismode = "";
	#TODO: currently only works for local bam files
	if (defined($BAMINDEX)) {
		# simple diploid variant calling

#		print Dumper (@BAM,$BAM[$BAMINDEX]);
		my $bamfileobj = $BitQC->{fileadapter}->createFile($BAM[$BAMINDEX]);
		my $bamfile = $bamfileobj->getInfo('file');
		$bams = $bamfile." ";
		if ($PAIR[$BAMINDEX]) {
			# paired variant calling
			$analysismode = "-T pair ";
			my $pairfileobj = $BitQC->{fileadapter}->createFile($PAIR[$BAMINDEX]);
			my $pairfile = $pairfileobj->getInfo('file');
			$bams .= $pairfile." ";
		}
		if ($TRIO[$BAMINDEX]) {
			# trio variant calling
			$analysismode .= "-s $TRIOFILE ";
			my $triofileobj = $BitQC->{fileadapter}->createFile($TRIO[$BAMINDEX]);
			my $triofile = $triofileobj->getInfo('file');
			$bams .= $triofile." ";

		}
	} else {
		# pooled variant calling
		foreach my $bam (@BAM) {
			$bams .= $bam->{'file'} . " ";
		}
	}

	$BitQC->run_and_log(
		message =>
		  "Extract raw variants for bam files $bams for region $REGION",
		command =>
"$SAMTOOLS_COMMAND mpileup -DgSu -r $REGION -f $SAMTOOLS_INDEX $callopts $bams |$BCFTOOLS_COMMAND view -bvcg $analysismode - > $OUTPUTFILE.raw.bcf",
  log_stderr => 1
	);
	
	$BitQC->run_and_log(
		message => "Filter raw calls",
		command =>
"$BCFTOOLS_COMMAND view $OUTPUTFILE.raw.bcf | $VCFUTILS_COMMAND varFilter $filteropts | $BGZIP_COMMAND -c > $OUTPUTFILE",
  log_stderr => 1
	);
}
elsif ( $ALGORITHM eq "gatk" ) {

	my $bams       = "";
	my $stringbams = "";

	if (defined($BAMINDEX)) {
		# simple diploid variant calling

		my $bamfileobj = $BitQC->{fileadapter}->createFile($BAM[$BAMINDEX]);
		my $bamfile = $bamfileobj->getInfo('file');

		$bams .= "-I " . $bamfile . " ";
		$stringbams .= $bamfile . " ";

		if ($PAIR[$BAMINDEX]) {
			# paired variant calling to be implemented for gatk
		}
		if ($TRIO[$BAMINDEX]) {
			# trio variant calling to be implemented for gatk
		}
	} else {
		foreach my $bam (@BAM) {
			$bams .= "-I " . $bam->{'file'} . " ";
			$stringbams .= $bam->{'file'} . " ";
		}
	}

	$BitQC->run_and_log(
		message =>
		  "Extract raw variants for bam files $stringbams for region $REGION",
		command =>
"$GATK_COMMAND -l INFO -R $GATK_INDEX -T UnifiedGenotyper -glm BOTH -L $REGION $callopts $bams -o $OUTPUTFILE"
	);
}
elsif ( $ALGORITHM eq "gatk2_haplo" ) {

		my $bams       = "";
		my $stringbams = "";
		my $KNOWN_SNP_VCF =
		    $BitQC->{node_config}->{paths}->{genomedir}->{dir} 
		  . $GENOMEBUILD . "/"
		  . $BitQC->{genome}->{files}->{dbsnp}->{path};
		
		if (defined($BAMINDEX)) {
			# simple diploid variant calling

			my $bamfileobj = $BitQC->{fileadapter}->createFile($BAM[$BAMINDEX]);
			my $bamfile = $bamfileobj->getInfo('file');

			$bams .= "-I " . $bamfile . " ";
			$stringbams .= $bamfile . " ";

			if ($PAIR[$BAMINDEX]) {
				# paired variant calling to be implemented for gatk
			}
			if ($TRIO[$BAMINDEX]) {
				# trio variant calling to be implemented for gatk
			}
		} else {
			foreach my $bam (@BAM) {
				$bams .= "-I " . $bam->{'file'} . " ";
				$stringbams .= $bam->{'file'} . " ";
			}
		}
		$callopts .= " --dbsnp $KNOWN_SNP_VCF";
    $callopts .= " -stand_call_conf 30.0";
    $callopts .= " -stand_emit_conf 10.0";
		$callopts .= " -nct 4";
		$BitQC->run_and_log(
			message =>
			  "Extract raw variants for bam files $stringbams for region $REGION",
			command =>
	"$GATK2_COMMAND -l INFO -R $GATK_INDEX -T HaplotypeCaller $callopts -L $REGION $bams -o $OUTPUTFILE"
		);

} elsif ( $ALGORITHM eq "somaticsniper" ) {
	my $bams = "";

	my $bamfileobj = $BitQC->{fileadapter}->createFile($BAM[$BAMINDEX]);
	my $bamfile = $bamfileobj->getInfo('file');
	$bams = $bamfile." "; # makes $bamfile the Tumor sample!!!

	my $pairfileobj = $BitQC->{fileadapter}->createFile($PAIR[$BAMINDEX]);
	my $pairfile = $pairfileobj->getInfo('file');
	$bams = $pairfile." "; # makes $pairfile the Normal sample!!!

	$BitQC->run_and_log(
		message =>
		  "Extract raw variants for bam files $bams ",
		command =>
"bam-somaticsniper1.0.2 $callopts -F vcf -f $SAMTOOLS_INDEX $bams $OUTPUTFILE.raw.vcf",
  log_stderr => 1
	);
	
	$BitQC->run_and_log(
		message => "Compress raw calls",
		command =>
"cat $OUTPUTFILE.raw.vcf | $BGZIP_COMMAND -c > $OUTPUTFILE",
  log_stderr => 1
	);
}
else {
	$BitQC->log_error( message =>
		  "Unknown algorithm $ALGORITHM specified, use either gatk, mpileup or somaticsniper"
	);
}

# index the vcf file generated
$BitQC->run_and_log(
	message => "Indexing vcf file",
	command => "$TABIX_COMMAND -p vcf $OUTPUTFILE"
);

######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	unlink("$OUTPUTFILE.raw.bcf") if ( -e "$OUTPUTFILE.raw.bcf" );
	unlink("$OUTPUTFILE.raw.vcf") if ( -e "$OUTPUTFILE.raw.vcf" );
}

# finish logging
$BitQC->finish_log( message => "Variant calling completed succesfully for region $REGION" );
