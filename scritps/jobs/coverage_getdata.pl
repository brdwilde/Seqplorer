#!/usr/bin/perl -w
use strict;
use warnings;
use Parallel::ForkManager;
use Statistics::Descriptive;
#use Statistics::RankCorrelation;
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
		'regionfile'	=> { type => 'string' },
		'chromosome'	=> { type => 'string'}
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

my @BAM;
@BAM 				= @{$BitQC->getRunConfig('bam')};
my $REGIONFILE      	= $BitQC->getRunConfig('regionfile');
my $CHROMOSOME      	= $BitQC->getRunConfig('chromosome');
my $NORMALIZE		= $BitQC->getRunConfig('normalizeto');
my $OFFTARGET		= $BitQC->getRunConfig('offtarget');
my $RAWDATA 		= $BitQC->getRunConfig('rawdata');
my $MAX_PROCESSES	= $BitQC->{node_config}->{system}->{mappingcores};

#Get command
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');

###########################################################################
# Change to ths working directory
###########################################################################

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

######################################################################################
# GET THE COVERAGE DATA FOR EACH REGION IN THE REGIONS FILE
######################################################################################

my @bamfiles = $BitQC->{fileadapter}->getLocal(\@BAM,'bam');

my %regionstart;
my %regionend;

# create local file object
my $regionfile = $BitQC->{fileadapter}->createFile( {
	'filetype' => 'bed',
	'file' => $REGIONFILE,
	'type' => 'local',
	'ext' => '.bed'
});
my $regionfilepointer = $regionfile->getReadPointer();

# create a hash to indicate what bases we need coverage data for
while (<$regionfilepointer>){
	chomp($_);

	my @line = split("\t", $_);

	push (@{$regionstart{$line[1]+1}}, $line[3]); # we correct for the bed file being 0 based while smatools being 1 based coordinates!!!! half open vs closed...
	$regionend{$line[2]}{$line[3]} = 1; # both bed and samtools co¨rdinates are closed, so no correciton here!!!!
}

my $fork_manager= new Parallel::ForkManager($MAX_PROCESSES);

foreach my $bamfile (@bamfiles){

	my $bamname = $bamfile->getInfo('name');
	my $bamfile = $bamfile->getInfo('file');

	$fork_manager->start and next;

	my $filename = $wd.$bamname.'';
	$filename =~ s/\.//g;

	my $rawdatafilename = $filename.'_'.$CHROMOSOME.'_raw.txt.gz';

	# open file for storing raw data
	my $rawdatafile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
		'filetype' => 'txt',
		'file' => $rawdatafilename,
	    'type' => 'local',
	    'ext' => '.txt.gz'
	});

	# create file pointer for writing
	my $rawdatafilepointer = $rawdatafile->getWritePointer();


	# open command for raw data generation
	my $depthcommand = $SAMTOOLS_COMMAND.' depth  -r '.$CHROMOSOME.' -b '.$REGIONFILE.' '.$bamfile;
	open(my $depth, "-|", $depthcommand);

	my $regionpos;
	my @regions;

	# get the start position of the first region
	$regionpos = ( sort {$a <=> $b} keys %regionstart )[0];
	#$lastpos = $regionpos+1;

	while (<$depth>) {
		chomp();

		my @line = split("\t", $_);

		my $pos = $line[1];
		my $cov = $line[2];

		# if no coverage is detected on the region start base
		while ($regionpos < $pos){
			# add regions that start in this interval
			if ($regionstart{$regionpos}){
				# add regions that start here
				push (@regions, @{$regionstart{$regionpos}});
			}

			# add datapoints with coverage 0 untill we reach the first base with coverage
			foreach my $regionname (@regions){
				print $rawdatafilepointer $CHROMOSOME."\t".$regionpos."\t".$regionname."\t".$bamname."\t0\n";
			}

			# remove regions that end on this position
			if ($regionend{$regionpos}){
				# remove regions that end here
				@regions = grep ! exists $regionend{$regionpos}{$_}, @regions;
			}

			$regionpos++;
			#$lastpos = $regionpos;
		}

		#add regions that start on this position to the array
		if ($regionstart{$pos}){
			# add regions that start here
			push (@regions, @{$regionstart{$pos}});
		}

		foreach my $regionname (@regions){
			print $rawdatafilepointer $CHROMOSOME."\t".$pos."\t".$regionname."\t".$bamname."\t".$cov."\n";
		}

		# remove regions that end on this position
		if ($regionend{$pos}){
			# remove regions that end here
			@regions = grep ! exists $regionend{$pos}{$_}, @regions;
		}
		$regionpos = $pos+1; # this region has been printed so we move on
	}
	# keep on printing coverage 0 positions as long as some regions are available
	while (@regions){
		# regions are remaining
		# add datapoints with coverage 0 untill we run out of regions
		foreach my $regionname (@regions){
			print $rawdatafilepointer $CHROMOSOME."\t".$regionpos."\t".$regionname."\t".$bamname."\t0\n";
		}

		# remove regions that end on this position
		if ($regionend{$regionpos}){
			# remove regions that end here
			@regions = grep ! exists $regionend{$regionpos}{$_}, @regions;
		}

		$regionpos++;
	}

	$fork_manager->finish;
}

#Wait till all processes are finished
$fork_manager->wait_all_children;



	
