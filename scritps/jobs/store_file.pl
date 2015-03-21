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
		'db_config'   	=> { default => boolean::false, type => 'bool' },
		'inputfile'		=> { type => 'string', hash => 1},
		'outfile'		=> { type => 'string', hash => 1},
		'remove'		=> { type  => "bool" },
		'compress'		=> { type  => "bool" }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $INPUTFILE = $BitQC->getRunConfig('inputfile');
my $OUTFILE = $BitQC->getRunConfig('outfile');
my $REMOVE = $BitQC->getRunConfig('remove');
my $COMPRESS = $BitQC->getRunConfig('compress');

######################################################################################
# GET THE FILE POINTERS FOR IN AND OUTPUT
######################################################################################

# create file variables
my $outfile;
my $output;
my $infile;
my $input;

# create output file and open writing pointer
$outfile = $BitQC->{fileadapter}->createFile( $OUTFILE);
$output = $outfile->getWriteCommand('compress' => $COMPRESS); # if compress is 0 we won't change the input stream on write
my %outfile = $outfile->getFileInfo();

# create input file and open reading pointer
$infile = $BitQC->{fileadapter}->getLocalFile($INPUTFILE);
$input = $infile->getReadCommand('uncompress' => $COMPRESS); # if compress is 0 we won't uncompress th input stream on read
my %infile = $infile->getFileInfo();

my $name = $infile->getInfo('name');

# make sure we are not trying to copy a file over itself!
my %cmp = map { $_ => 1 } keys %infile;
for my $key (keys %outfile) {
	last unless exists $cmp{$key};
	last unless $infile{$key} eq $outfile{$key};
	delete $cmp{$key};
}
if (%cmp) {
	# inptu and output are not the same file, we continue

	$BitQC->run_and_log(
	        message => "Stored file $name",
	        command => "$input | $output",
	  		log_stderr => 1
	);

	my $type = $infile->getInfo('type');

	#Remove temporary files when argument is true
	if ($REMOVE && $type eq 'local') {
		my $file = $infile->getInfo('file');
		unlink($file);
		$BitQC->log_message(message => "Removed local file $name");
	}

	######################################################################################
	# STORE THE INDEX OF CERTAIN FILE TYPES
	######################################################################################

	my $filetype = $infile->getInfo('filetype');
	my %indexes = (
		bam => {filetype => 'bai'},
		vcf => {filetype => 'vcf.gz.tbi', ext => '.vcf.gz.tbi', compression => undef}
	);

	if (defined($indexes{$filetype})){
		# check if an index exists, and if so, store it!
		my $index = $infile->duplicateFile($indexes{$filetype});

		if ($index->fileExists()){
			# file exists!

			# create ouput file
			my $outindex = $outfile->duplicateFile($indexes{$filetype});
			my $indexout = $outindex->getWriteCommand('compress'=> $COMPRESS);

			# open pointer
			my $indexin = $index->getReadCommand('uncompress'=> $COMPRESS);

			$BitQC->run_and_log(
	        	message => "Stored index for $INPUTFILE",
	        	command => "$indexin | $indexout",
				log_stderr => 1
			);

			#Remove temporary files when argument is true
			if ($REMOVE && $type eq 'local') {
				my $file = $index->getInfo('file');
				unlink($file);
				$BitQC->log_message(message => "Removed local index for $name");
			}
		}
	}

} else {
	$BitQC->log_message(message => "Cannot copy or move file $name on top of itself. Doing nothing");
}


######################################################################################
# FINISH SCRIPT
######################################################################################

# finish logging
$BitQC->finish_log( message => "Job completed: file $name stored");
