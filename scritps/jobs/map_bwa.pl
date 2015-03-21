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
		'mappingcores'	=> { type => 'string' },
		'bamname'		=> { type => 'string' },
		'fastq'			=> { type => 'string' },
		'pair' 			=> { type => 'string' },
		'readgroupindex'=> { type => 'string' },
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

# set other vars
my $REMOVE     		= $BitQC->getRunConfig('remove');
my $BUILD      		= $BitQC->getRunConfig('genomebuild');
my $MAPOPTIONS 		= $BitQC->getRunConfig('mapoptions');
my $CORES           = $BitQC->getRunConfig('mappingcores');
my $BAMNAME			= $BitQC->getRunConfig('bamname');
my $FASTQ           = $BitQC->getRunConfig('fastq');
my $PAIR			= $BitQC->getRunConfig('pair');
my $READGROUPINDEX  = $BitQC->getRunConfig('readgroupindex');
my $READGROUP 		= $BitQC->getRunConfig('readgroup');

#Get command
my $BWA_COMMAND = $BitQC->getCommand('bwa');
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');

#Get index for given organismbuild
my $BWA_INDEX = $BitQC->getGenomeIndex('bwa');

######################################################################################
# START BWA MAPPING OF FASTQ FILE
######################################################################################

# get the fastq name
my $fastqname;
my $fastqpath;
( $fastqname, $fastqpath, my $fastqext ) = fileparse( $FASTQ, '\..*' );

my $readgroup = $BitQC->{run_config}->{readgroup}->{$READGROUPINDEX};

my $mapopts = "";
if ($MAPOPTIONS) {
	for my $opt ( keys %{$MAPOPTIONS} ) {
		if ( $MAPOPTIONS->{$opt} ) {
			$mapopts .= $opt . " " . $MAPOPTIONS->{$opt} . " ";
		}
		else {
			$mapopts .= $opt . " ";
		}

	}
}

$BitQC->run_and_log(
	message => "Generate index for $FASTQ",
	command =>
"$BWA_COMMAND aln -t $CORES $mapopts $BWA_INDEX $FASTQ > $fastqpath$fastqname.sai",
  log_stderr => 1
);

if ( -f $PAIR ) {

	# we do paired alignment!
	$BitQC->run_and_log(
		message => "Generate index for $FASTQ mate pairs.",
		command =>
"$BWA_COMMAND aln -t $CORES $mapopts $BWA_INDEX $PAIR > $fastqpath$fastqname.sai_2",
	log_stderr => 1);

	$BitQC->run_and_log(
		message => "Mapping reads from $FASTQ and pairs",
		command =>
"$BWA_COMMAND sampe -r '$readgroup' $BWA_INDEX $fastqpath$fastqname.sai $fastqpath$fastqname.sai_2 $FASTQ $PAIR | $SAMTOOLS_COMMAND view -bhSo $fastqpath$fastqname-unsorted.bam -",
  log_stderr => 1
	);
}
else {

	# we do single end alingment
	$BitQC->run_and_log(
		message => "Map reads from $FASTQ",
		command =>
"$BWA_COMMAND samse -r '$readgroup' $BWA_INDEX $fastqpath$fastqname.sai $FASTQ | $SAMTOOLS_COMMAND view -bhSo $fastqpath$fastqname-unsorted.bam -",
  log_stderr => 1
	);
}

$BitQC->run_and_log(
	message => "Sorting mapped reads",
	command =>
"$SAMTOOLS_COMMAND sort $fastqpath$fastqname-unsorted.bam  $BAMNAME"
);

######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	$BitQC->log_message( message => "Removing temporary files." );

	unlink("$FASTQ");
	unlink("$fastqpath$fastqname.sai");
	if ($PAIR ) {
		unlink("$PAIR");
		unlink("$fastqpath$fastqname.sai_2");
	}
	unlink("$fastqpath$fastqname-unsorted.bam");
}

# finish logging
$BitQC->finish_log( message => "Job completed: bwa mapping of fastq file $FASTQ" );
