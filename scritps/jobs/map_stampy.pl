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
my $STAMPY_COMMAND = $BitQC->getCommand('stampy');
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');

#Get index for given organismbuild
my $BWA_INDEX = $BitQC->getGenomeIndex('bwa');
