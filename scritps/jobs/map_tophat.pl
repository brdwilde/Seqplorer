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
my $TOPHAT_COMMAND = $BitQC->getCommand('tophat');
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');
my $PICARD_COMMAND = $BitQC->getCommand('picard_replacereadgroup');
my $REORDER_COMMAND = $BitQC->getCommand('picard_reorder');

#Get index for given organismbuild
my $BOWTIE_INDEX = $BitQC->getGenomeIndex('bowtie');
$BOWTIE_INDEX =~ s/\.fa$//;
my $GATK_INDEX = $BitQC->getGenomeIndex('gatk');
  
######################################################################################
# START TOPHAT MAPPING OF FASTQ FILE
######################################################################################

# get the fastq name
my $fastqname;
my $fastqpath;
( $fastqname, $fastqpath, my $fastqext ) = fileparse( $FASTQ, '\..*' );

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


my $fastq = $FASTQ;
my $message = "Mapping reads using tophat for $FASTQ";

if ( -f $PAIR ) {
	$fastq .= " ".$PAIR;
	$message .= " and pair ".$PAIR;
}

$BitQC->run_and_log(
	message => $message,
	command => "$TOPHAT_COMMAND -p $CORES -o $fastqpath$fastqname $BOWTIE_INDEX $fastq"
);

$BitQC->run_and_log(
	message => "Sorting mapped according to karyotypic order",
	command => "$REORDER_COMMAND I=$fastqpath$fastqname/accepted_hits.bam O=$BAMNAME-norg.bam REFERENCE=$GATK_INDEX 2>&1"
);

# add the read group info to the bam file
my $wd = $BitQC->workingDir();
my $readgroup = $BitQC->{run_config}->{readgroup}->{$READGROUPINDEX};

$readgroup =~ /ID:(\w+)/;
my $rgid = $1;
$readgroup =~ /SM:(\w+)/;
my $rgsn = $1;
$readgroup =~ /PL:(\w+)/;
my $rgpl = $1;

$BitQC->run_and_log(
	message => "Adding read group information to $BAMNAME",
	command =>
"$PICARD_COMMAND INPUT=$BAMNAME-norg.bam TMP_DIR=$wd OUTPUT=$BAMNAME.bam VALIDATION_STRINGENCY=LENIENT RGID=$rgid RGLB=$rgsn RGPL=$rgpl RGPU=$rgsn RGSM=$rgsn 2>&1"
);

######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	$BitQC->log_message( message => "Removing temporary files." );
	unlink("$FASTQ");
	unlink("$PAIR") if (-f $PAIR);
	unlink("$fastqpath$fastqname.sai");
	unlink("$fastqpath$fastqname/accepted_hits.bam");
	unlink("$BAMNAME-norg.bam");
}

# finish logging
$BitQC->finish_log( message => "Job completed: tophat mapping of fastq file $FASTQ" );


