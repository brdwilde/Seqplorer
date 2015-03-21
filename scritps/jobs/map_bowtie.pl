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
my $BOWTIE_COMMAND = $BitQC->getCommand('bowtie');
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');

#Get index for given organismbuild
my $BOWTIE_INDEX = $BitQC->getGenomeIndex('bowtie');
  
######################################################################################
# START BOWTIE MAPPING OF FASTQ FILE
######################################################################################

# get the fastq name
my $fastqname;
my $fastqpath;
( $fastqname, $fastqpath, my $fastqext ) = fileparse( $FASTQ, '\..*' );

my $readgroup;

my @readgroup = split( /\t/, $READGROUP->{$READGROUPINDEX} );
foreach (@readgroup) {
	$readgroup = "--sam-RG $_" unless ( $_ eq "\@RG" );
}

#process the mapping options
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

my $message = "Mapping $FASTQ";
my $input   = "-1 $FASTQ";

if ( -f $PAIR ) {
	$input .= " -2 $PAIR";
	$message = "Mapping $FASTQ and pairs";

}

$BitQC->run_and_log(
	message => $message,
	command =>
"$BOWTIE_COMMAND -p $CORES $mapopts -S $BOWTIE_INDEX $readgroup $input| $SAMTOOLS_COMMAND view -bhSo $fastqpath$fastqname-unsorted.bam - ",
  log_stderr => 1
);

$BitQC->run_and_log(
	message => "Sorting mapped reads",
	command =>
"$SAMTOOLS_COMMAND sort $fastqpath$fastqname-unsorted.bam $BAMNAME"
);

######################################################################################
# FINISH SCRIPT
######################################################################################

if ($REMOVE) {
	$BitQC->log_message( message => "Removing temporary files." );
	unlink("$FASTQ");
	if ( $PAIR ) {
		unlink("$PAIR");
	}
	unlink("$fastqpath$fastqname-unsorted.bam");
}

# finish logging
$BitQC->finish_log( message => "Job completed: bwa mapping of fastq file $FASTQ" );


