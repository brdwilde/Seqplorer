#!/usr/bin/perl -w

=head1 LICENSE

  No licence yet?

=head1 CONTACT

  Please email comments or questions to the 
  developer at <gbramdewilde@gmail.com>.

=cut

=head1 NAME

Bitqc Map Reads - A script to align next generation sequencing data to a reference genome and post process the alligned data

=head1 SYNOPSIS

map_reads.pl [options]

Use --help to see options, --man to see extended manual

by Bram de Wilde (gbramdewilde@gmail.com)

=head1 DESCRIPTION

B<map_reads> a script to automatically process and align reads starting from one or more raw fastq input file(s) and outputting a sorted and indexed bam file.

=cut

use strict;
use warnings;
use File::Basename;
use File::Slurp;
use File::Temp qw/ tempfile tempdir /;
use CGI;
use BitQC;

######################################################################################
#CREATE A BitQC OBJECT AND CAPTURE THE INPUT
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'files' =>  { type => "string", array => 1, short => "f" },
		'output' => { required => 1, type => "string", short => "o" },
		'mapper' => { required => 1, type => "string",    short => "m" },
		'mapoptions' => { type => "string", hash => 1 },
		'sort'   => { default => boolean::true, type  => "bool", short => "s" },
		'index'  => { default => boolean::true, type  => "bool" },
		'remove' => { default => boolean::true, type  => "bool" },
		'pair'   => { type    => "string",      array => 1,      short => "p" },
		'platform'    => { required => 1,              type => 'string' },
		'chuncksize'  => { default  => 2000000,        type => 'int' },
		'projectid' => { type     => "string" },
		'projectcol' => { default => 'projects', type => "string" },
		'samples' => {type => 'string', array =>1 },
		'samplescol'      => { default  => 'samples',      type  => "string" },

		# the folowing options are options of the post mapping processing script
		'rmdup' => { default => boolean::true, type => "bool", short => "d" },
		'recal' => { default => boolean::true, type => "bool", short => "r" },
		'local_realignment' => { default => boolean::true, type => "bool", short => "l" }
	}
);


######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Log variables
my $BITQC_LOG_ID = $BitQC->{log_id};

# get all the possible input files
my @INPUT_FILES = @{ $BitQC->getRunConfig('files') };
my @INPUT_PAIRS;
@INPUT_PAIRS = @{ $BitQC->getRunConfig('pair') } if ($BitQC->getRunConfig('pair'));


# set the mapping options
my $MAPPER       = $BitQC->getRunConfig('mapper');
my $MAPPINGCORES = $BitQC->{node_config}->{system}->{mappingcores};
my $PLATFORM     = $BitQC->getRunConfig('platform');
my $CHUNKSIZE = $BitQC->getRunConfig('chuncksize') * 4; # multiply by 4 (4 lines per read in fastq format)

# the list of post processing options for the bam files generated
my $SORT         = $BitQC->getRunConfig('sort');
my $INDEX        = $BitQC->getRunConfig('index');
my $RECALIBRATE       = $BitQC->getRunConfig('recal');
my $LOCAL_REALIGNMENT = $BitQC->getRunConfig('local_realignment');
my $RMDUP             = $BitQC->getRunConfig('rmdup');

# set the output directory
my $OUTPUT       = $BitQC->getRunConfig('output');
$OUTPUT .= '/' unless ($OUTPUT =~/\/$/);

# get the seqplorer project id and optional sample ids
# these argumetns are required if we want to make the data available in the seqplorer web interface
my $PROJECTID  = $BitQC->getRunConfig('projectid');
my $PROJECTCOL = $BitQC->getRunConfig('projectcol');
my @SAMPLES;
@SAMPLES = @{$BitQC->getRunConfig('samples')} if ($BitQC->getRunConfig('samples'));
my $SAMPLESCOL = $BitQC->getRunConfig('samplescol');


# A list of job scripts
my $BITQC_JOBSCRIPTS_PATH = $BitQC->{node_config}->{executables}->{jobscripts}->{path};
my $JOB_SCRIPT_BAM_INDEX = $BITQC_JOBSCRIPTS_PATH . "index_bam.pl";
my $JOB_SCRIPT_NOTIFY    = $BITQC_JOBSCRIPTS_PATH . "notify.pl";
my $JOB_SCRIPT_MERGE     = $BITQC_JOBSCRIPTS_PATH . "merge_bams.pl";
my $JOB_SCRIPT_SORT      = $BITQC_JOBSCRIPTS_PATH . "sort_bam.pl";
my $JOB_SCRIPT_STORE	 = $BITQC_JOBSCRIPTS_PATH . "store_file.pl";
my %MAPPINGSCRIPTS = (
	bwa    => $BITQC_JOBSCRIPTS_PATH . "map_bwa.pl",
	bwasw  => $BITQC_JOBSCRIPTS_PATH . "map_bwasw.pl",
	bowtie => $BITQC_JOBSCRIPTS_PATH . "map_bowtie.pl",
	#stampy => $BITQC_JOBSCRIPTS_PATH . "map_stampy.pl",
);
my $JOB_SCRIPT_RECALIBRATE 			= $BITQC_JOBSCRIPTS_PATH . "recalibrate_bam.pl";
my $JOB_SCRIPT_REMOVE_DUPLICATES 	= $BITQC_JOBSCRIPTS_PATH . "remove_duplicates_bam.pl";
my $JOB_SCRIPT_LOCAL_REALIGNMENT 	= $BITQC_JOBSCRIPTS_PATH . 'local_realign_bam.pl';

# get the genomebuild, reads will be mapped to this genome, and its indexes
my $SAMTOOLS_INDEX = $BitQC->getGenomeIndex('samtools');
my $GENOMBUILD = $BitQC->getRunConfig('genomebuild');

# some jobs will be split by region, we use the chormosome names form the genoeme as regions	
my @regions;
@regions = `awk '{ print \$1 }' $SAMTOOLS_INDEX.fai`;
chop(@regions);


######################################################################################
# CHECK IF THE INPUT IS VALID
######################################################################################

# check if the number of paired files is as large as the number of forward fastq files
if (   @INPUT_FILES && @INPUT_PAIRS ) {
	$BitQC->log_error(
		message => "Please specify as many fastq files as pairs." )
	  unless ( scalar( @INPUT_FILES ) == scalar( @INPUT_PAIRS ));
}
# perform the same check but this time for the sample names
if (   @INPUT_FILES && @SAMPLES ) {
#	$BitQC->log_error(
#		message => "Please specify as many sample names as fastq files." )
#	  unless ( scalar( @{ $BitQC->{run_config}->{input} } ) == scalar( @{ $BitQC->{run_config}->{samples} } ) );
}
$BitQC->log_error(
	message => "Unknown mapper specified, please use one of bwa, bwasw, bowtie" )
unless ( $MAPPINGSCRIPTS{$MAPPER} );

###########################################################################
# CHECK IF SAMPLE ID INFO IS INCLUDED IN THE INPUT FILE HASH
###########################################################################

# sampleid's can be specified command line, but also in the input files hash
if (!@SAMPLES){
	foreach my $file (@INPUT_FILES){
		if (ref($file) eq 'HASH'){
			push (@SAMPLES, ($file->{'sampleid'}=>$file->{'samplename'})) if ($file->{'sampleid'});
		}
	}	
	$BitQC->setRunConfig('samples', \@SAMPLES);
}


######################################################################################
# CREATE ARRAY OF BitQCFile objects
######################################################################################

my @inputfiles;
if (@INPUT_FILES){
	@inputfiles = $BitQC->{fileadapter}->getLocal(\@INPUT_FILES,'fastq');
	if (@inputfiles){
		my @fastqconfig;
		foreach(@inputfiles){
			my %filehash = $_->getFileInfo();
			push (@fastqconfig,\%filehash);
		}
		$BitQC->setRunConfig('input', \@fastqconfig);		
	} else {
		@inputfiles = $BitQC->{fileadapter}->getLocal(\@INPUT_FILES,'bam');
		my @bamconfig;
		foreach(@inputfiles){
			my %filehash = $_->getFileInfo();
			push (@bamconfig,\%filehash);
		}
		$BitQC->setRunConfig('files', \@bamconfig);
	}
}

my @fastqpairs;
if (@INPUT_PAIRS){
	@fastqpairs = $BitQC->{fileadapter}->getLocal(\@INPUT_PAIRS,'fastq');
	my @pairconfig;
	foreach(@fastqpairs){
		my %filehash = $_->getFileInfo();
		push (@pairconfig,\%filehash);
	}
	$BitQC->setRunConfig('pair', \@pairconfig);
}


######################################################################################
# START MAPPING PROCESS
######################################################################################

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

# create the output directory if requested
if (!ref($OUTPUT)){
	# $OUTPUT is a string, thus a path
	if (!(-d $OUTPUT)){
		mkdir ($OUTPUT);
	}
}

######################################################################################
# GET THE PROJECT RECORD FOR SAMPLE AND FILE STORAGE
######################################################################################

my $project;
if ($PROJECTID){
	# get the project we want to add the samples to
	$project = $BitQC->{DatabaseAdapter}->findEntryById(
		collection => $PROJECTCOL,
		id         => MongoDB::OID->new( value => $PROJECTID )
	);
}

my $fileindex = 0;
my @bam;

foreach my $file (@inputfiles) {

	# collect the file info
	my %filehash = $file->getFileInfo();

	#get the name of the file
	my $name = $file->getInfo('name');
	my $filetype = $file->getInfo('filetype');
	my $type = $file->getInfo('type');
	my $bamfile;
	$bamfile = $file->getInfo('file') if ($type eq 'bam');

	##################################################################################
	# CREATE OR UPDATE THE SAMPLE INFORMATION FOR THE INPUT FILE
	##################################################################################
	my $sample_id;
	if ($PROJECTID){
		# we got a project id, add sample and file info to this project

		my @files = (\%filehash);
		# optionally add info about the paired fastq file if it exists
		my %pairhash;
		%pairhash = $fastqpairs[$fileindex]->getFileInfo() if ($fastqpairs[$fileindex]);
		push (@files, \%pairhash) if (%pairhash);

		if ($SAMPLES[$fileindex]){
			# we got sample information in the config
			if(ref($SAMPLES[$fileindex]) eq 'HASH'){
				# hash should be in the $name => mongoid format
				# the sample is known to the database, we add the files the sample record

				# get the name and the id form the hash
				foreach my $samplename (keys %{$SAMPLES[$fileindex]}){
					$sample_id = $SAMPLES[$fileindex]->{$samplename};
					$name = $samplename;
				}

				# update the sample record by adding the input file if not already there
				$BitQC->{DatabaseAdapter}->addtoSet(
					collection => $SAMPLESCOL, 
					id => MongoDB::OID->new( value => $sample_id),
					array => 'files',
					element => \%filehash
				);
				$BitQC->{DatabaseAdapter}->addtoSet(
					collection => $SAMPLESCOL, 
					id => MongoDB::OID->new( value => $sample_id),
					array => 'files',
					element => \%pairhash
				) if (%pairhash);

			} else {
				# the user specified a sample name for this file
				# and the sample is unknown to the database: (we didn't get a hash with the sample id)
				# create a record and name the sample appropriately
				$name = $SAMPLES[$fileindex];
				my %sample;
				my $sample_obj = $BitQC->{DatabaseAdapter}->insertEntry(
					collection => $SAMPLESCOL,
					fields     => {
						'name'    => $name,
						'project' => [
							{
								'id' =>
								  MongoDB::OID->new( value => $PROJECTID ),
								'name' => $project->{name}
							}
						],
						'genome' => $GENOMBUILD,
						'files' => \@files
					},
					save_mode => 1
				);
				$sample_id = $sample_obj->{value};
				$sample{$name} = $sample_id;

				# update the configuration
				$BitQC->{run_config}->{samples}[$fileindex] = \%sample;
				$BitQC->replaceRunConfig();
			}
		} else {
			# no sample specified and known to the database
			# we create the sample and use the file name as the sample name
			# TODO: for BAM files we should be using the name of the read groups in it as sample names
			my %sample;
			my $sample_obj = $BitQC->{DatabaseAdapter}->insertEntry(
				collection => $SAMPLESCOL,
				fields     => {
					'name'    => $name,
					'project' => [
						{
							'id' => MongoDB::OID->new( value => $PROJECTID ),
							'name' => $project->{name}
						}
					],
					'genome' => $GENOMBUILD,
					'files' => \@files
				},
				save_mode => 1
			);
			$sample_id = $sample_obj->{value};
			$sample{$name} = $sample_id;

			# update the configuration
			push (@{$BitQC->{run_config}->{samples}},\%sample);
			$BitQC->replaceRunConfig();
		}
	}

	######################################################################################
	# SPLIT AND MAP
	######################################################################################

	if ($filetype eq 'fastq') {
		##################################################################################
		# CREATE READ GROUP INFORMATION FOR BAM FILE ANNOTATION
		##################################################################################

		# create a hash of the readgroups per fastq file for later use, store it in the config
		# TODO: extend this read group information with more atributes
		my $readgroupname=$name; 
		# database does not accept keys with . in them -> replace by underscore
		$readgroupname=~ s/\./\_/g;
		my $readgroup = "\@RG\tID:$readgroupname\tSM:$name\tPL:$PLATFORM";
		$BitQC->{run_config}->{readgroup}->{$readgroupname} = $readgroup;
		$BitQC->replaceRunConfig();

		##################################################################################
		# CREATE FASTQ CHUNCKS FOR MAPPING
		##################################################################################

		# some variables for counting and tracking chuncks
		my $chunck_count = 0;
		my @bamchuncks;
		my @mapping_jobs;

		# variables to store the fastq data
		my @chunck;
		my $outfastqfile;
		my $outfastqpair;
		my $localfilepointer;

		# open a file to store the entire fastq file compressed
		# the contents of the fastq file will be copied here during the processing
		if (!ref($OUTPUT)){
			if ( $type ne 'local'){
				# user wants to store data locally and the input file is not local
			
				# create local file object
				$outfastqfile = $BitQC->{fileadapter}->createFile( {
					'compression' => 'gzip',
	    			'filetype' => 'fastq',
			   		'name' => $name.'_R1',
	    			'file' => $OUTPUT.$name.'_R1.fastq.gz',
	    			'type' => 'local',
	    			'ext' => '.fastq.gz'
				});
				# create file pointer for writing
				$localfilepointer = $outfastqfile->getWritePointer();
			}
		}
		elsif ($OUTPUT) {
			# the user wants to store the file at a remote location

			# we take the parameters the user set for output files
			my %filehash = %$OUTPUT;
			# we now modify these settings for the paired fastq file (retaining host and path specific info)
			$filehash{compression} = 'gzip';
			$filehash{filetype} = 'fastq';
			$filehash{name} = $name.'_R1';
			$filehash{path} = $sample_id if ($filehash{type} eq 'mongodb');
			$filehash{ext} = '.fastq.gz';
			delete ($filehash{file}); # will be rebuilt from the hash
			$outfastqfile = $BitQC->{fileadapter}->createFile(\%filehash);
			$localfilepointer = $outfastqfile->getWritePointer();
		}
		if ($PROJECTID && $outfastqfile){
			# add the output file to the database record
			my %filehash = $outfastqfile->getFileInfo;

			# update the sample record by adding the fastq file if not already there
			$BitQC->{DatabaseAdapter}->addtoSet(
				collection => $SAMPLESCOL, 
				id => MongoDB::OID->new( value => $sample_id),
				array => 'files',
				element => \%filehash
			);
		}

		# open a file pointer
		my $fastqpointer = $file->getReadPointer();

		#Split fastq file in chunks based on number of lines and create mapping command per chunck
		my $cores = $MAPPINGCORES;
		if ( $MAPPER eq "stampy" ) {
			$cores = 1;
		}

		my @mappingcommands;

		my $linenumber = 0;
		while (<$fastqpointer>) {
			$linenumber++;
			# store the line in the chunck array
			push(@chunck,$_);

			# If line equals CHUNK_NUMBER_OF_LINES than make new chunk
			# and create a mapping job for the previous chunck
			if ( $linenumber == $CHUNKSIZE ) {

				# write the data to the chunck for mapping
				my $chunckname = $wd . $name . "_" . $chunck_count;
				write_file( $chunckname. "_1.fastq",	@chunck );

				# write the data to the local file if required
				write_file( $localfilepointer , @chunck ) if ($outfastqfile);

				# log some info
				$BitQC->log_message( message => "$name split, chunck $chunckname created" );

				my $mappingcommand = $MAPPINGSCRIPTS{$MAPPER};
				$mappingcommand .= " --mappingcores $cores --bamname $chunckname --fastq ".$chunckname."_1.fastq --readgroupindex $name";
				$mappingcommand .= " --pair ".$chunckname."_2.fastq" if (defined( $fastqpairs[$fileindex] ));

				push (@mappingcommands, $mappingcommand);

				# store the chunck
				push( @bamchuncks, $chunckname . ".bam" );

				# reset the chunck
				@chunck   = ();
				# increase chunck count
				$chunck_count++;
				# reset the line counter
				$linenumber = 0;
			}
		}
		# the entire fastq file was processed; we create a mapping job for the reads remaining in the last chunck
		if ( @chunck ) {

			my $chunckname = $wd . $name . "_" . $chunck_count;
			write_file( $chunckname. "_1.fastq",	@chunck );

			# log some info
			$BitQC->log_message( message => "$name split, chunck $chunckname created" );
			
			# write the data to the local file if required
			write_file( $localfilepointer , @chunck ) if ($outfastqfile);

			my $mappingcommand = $MAPPINGSCRIPTS{$MAPPER};
			$mappingcommand .= " --mappingcores $cores --bamname $chunckname --fastq ".$chunckname."_1.fastq	--readgroupindex $name";
			$mappingcommand .= " --pair ".$chunckname."_2.fastq" if (defined( $fastqpairs[$fileindex] ));
			
			push (@mappingcommands, $mappingcommand);
			
			# store the chunck
			push( @bamchuncks, $chunckname . ".bam" );
		}

		close $fastqpointer;
		close $localfilepointer if ($localfilepointer);

		# open file pointer to the paired file if it is defined
		if ( defined( $fastqpairs[$fileindex] ) )	{
			my $pair = $fastqpairs[$fileindex];
			my $pairpointer = $pair->getReadPointer();
			# reset the pointer
			$chunck_count = 0;

			# arrays to store the fastq data
			my @chunck;
			my $localfilepointer;
		
			# open a local file to store the entire fastq file compressed
			# the contents of the fastq file will be copied here during the processing
			if (-d $OUTPUT ){
				if ( $type ne 'local'){
					# create local file object
					$outfastqpair = $BitQC->{fileadapter}->createFile( {
						'compression' => 'gzip',
		   		 		'filetype' => 'fastq',
					    'name' => $name.'_R2',
	    				'file' => $OUTPUT.$name.'_R2.fastq.gz',
						'type' => 'local',
	    				'ext' => '.fastq.gz'
					});
					# create file pointer fro writing
					$localfilepointer = $outfastqpair->getWritePointer();
				}
			} elsif ($OUTPUT) {
				# create file object and file pointer
				my %filehash = %$OUTPUT; # we take the parameters the user set for otput files
				# we now modify these settings for the paired fastq file (retaining host and path specific info)
				$filehash{compression} = 'gzip';
				$filehash{filetype} = 'fastq';
				$filehash{name} = $name.'_R2';
				$filehash{path} = $sample_id if ($filehash{type} eq 'mongodb');
				$filehash{ext} = '.fastq.gz';
				delete ($filehash{file}); # will be rebuilt from the hash
				$outfastqpair = $BitQC->{fileadapter}->createFile(\%filehash);
				$localfilepointer = $outfastqpair->getWritePointer();
			}
			if ($PROJECTID && $outfastqpair){
				# add the output file to the database record
				my %filehash = $outfastqpair->getFileInfo;
		
				# update the sample record by adding the fastq file if not already there
				$BitQC->{DatabaseAdapter}->addtoSet(
					collection => $SAMPLESCOL, 
					id => MongoDB::OID->new( value => $sample_id),
					array => 'files',
					element => \%filehash
				);
			}
		
			#Split fastq file in chunks based on number of lines
			my $linenumber = 0;
			while (<$pairpointer>) {
				$linenumber++;
				# store the line in the chunck array
				push(@chunck,$_);

				# If line equals CHUNK_NUMBER_OF_LINES than make new chunk
				# and create a mapping job for the previous chunck
				if ( $linenumber == $CHUNKSIZE ) {
		
					# write the data to the chunck for mapping
					write_file( $wd . $name . "_" . $chunck_count . "_2.fastq",	@chunck );
		
					# write the data to the local file if required
					write_file( $localfilepointer , @chunck ) if ($outfastqpair);
		
					# log some info
					$BitQC->log_message( message => "$name split, chunck " 
						  . $wd 
						  . $name
						  . "_$chunck_count for paired fastq file created" );
		
					# reset the chunck
					@chunck   = ();
					# increase chunck count
					$chunck_count++;
					# reset the line counter
					$linenumber = 0;
				}
			}
			# the entire fastq file was processed; we create a mapping job for the reads remaining in the last chunck
			if ( @chunck ) {
				$BitQC->log_message( message => "$name split, chunck " 
					  . $wd 
					  . $name
					  . "_$chunck_count for paired fastq file created" );
				
				# write the data to the file
				write_file( $wd . $name . "_" . $chunck_count . "_2.fastq",	@chunck );
		
				# write the data to the local file if required
				write_file( $localfilepointer , @chunck ) if ($outfastqpair);
			}	
			close $pairpointer;
			close $localfilepointer if ($localfilepointer);
		}

		# create jobs to perform the mapping

		$BitQC->createPBSJob(
			cmd 		=> \@mappingcommands,
			name 		=> 'map_'.$MAPPER,
			job_opts 	=> {
				ppn    => $cores,
				cput   => '72000'
			},
			message => "Mapping jobs submitted for $name" 
		);

		# create a job to merge the mapped chuncks
		$bamfile = $wd . "$name.bam"; # will be merging to local file

		my $mergecommand = $JOB_SCRIPT_MERGE." --name ".$bamfile;

		foreach (@bamchuncks) {
			$mergecommand .= " --bamchuncks ".$_;
		}

		$BitQC->createPBSJob(
			cmd 		=> $mergecommand,
			name 		=> 'merge',
			job_opts 	=> {
				cput   => '28000'
			},
			message => "Merge job submitted"
		);

		########################################################
		# SORT
		#######################################################
		if ( defined($SORT) && $SORT ) {

			$BitQC->createPBSJob(
				cmd 		=> $JOB_SCRIPT_SORT." --bam $bamfile",
				name 		=> 'sort',
				job_opts 	=> {
					cput   => '28000'
				},
				message => "Sorting job submitted for $bamfile" 
			);
		}

		########################################################
		# INDEXING
		#######################################################
		if ( defined($INDEX) && $INDEX ) {

			$BitQC->createPBSJob(
				cmd 		=> $JOB_SCRIPT_BAM_INDEX." --bam $bamfile",
				name 		=> 'index',
				job_opts 	=> {
					cput   => '28000'
				},
				message => "Index creation job submitted for $bamfile"  
			);
		}

	} 

	######################################################################################
	# MAKE THE INPUT BAM FILE AVAILABLE FOR FURTER PROCESSING
	######################################################################################

	elsif ($filetype eq 'bam'){
		# we will be checking if the file is a local sorted and indexed bam file
		# if not we will move it to the working dir 
		# and if no index exist, we will sort and index the bam file

		if ( $type ne 'local'){

			$bamfile = $wd.$name.'.bam';

			my $storecommand = $JOB_SCRIPT_STORE;

			foreach my $arg (keys %filehash){
				$storecommand .= " --inputfile ".$arg."=".$filehash{$arg};
			}

			$storecommand .= " --nocompress --outfile type=local --outfile file=".$bamfile;
			$storecommand .= " --noremove";

			$BitQC->createPBSJob(
				cmd 		=> $storecommand,
				name 		=> 'store',
				job_opts 	=> {
					cput   => '72000'
				},
				message => "$name file is not local; job submitted to copy file to local working directory" 
			);
		}

		# create the index file object for the bam file onbject
		my $index = $file->duplicateFile({'filetype' => 'bai'});

		if ( !( $index->fileExists() ) ) {

			# there is no index!
			# we asume the file is not sorted either for ease of working
			# sort and index the bam files, then perform the post processing steps


			$BitQC->log_message( message =>
				  "No index found for bam $name we start by sorting and indexing" );

			########################################################
			# SORT
			#######################################################
			if ( defined($SORT) && $SORT ) {
		
				$BitQC->createPBSJob(
					cmd 		=> $JOB_SCRIPT_SORT." --bam $bamfile",
					name 		=> 'sort',
					job_opts 	=> {
						cput   => '28000'
					},
					message => "Sorting job submitted for $name"
				);
			}
		
			########################################################
			# INDEXING
			#######################################################
			if ( defined($INDEX) && $INDEX ) {
		
				$BitQC->createPBSJob(
					cmd 		=> $JOB_SCRIPT_BAM_INDEX." --bam $bamfile",
					name 		=> 'index',
					job_opts 	=> {
						cput   => '28000'
					},
					message => "Index creation job submitted for $name" 
				);		
			}
		}
	}

	######################################################################################
	# POST FORCESS THE ALLIGNED READS
	######################################################################################

	########################################################
	# LOCAL REALIGNMENT
	########################################################
	if ( defined($LOCAL_REALIGNMENT) && $LOCAL_REALIGNMENT ) {
		
		my @local_realignment_commands;
		my @realignbams;

		#create local realignment job per region
		foreach my $region (@regions) {
			# region bam and realignemtn target intervals file

			my $region_bam =
				 $wd . $name . $region . "_local_realign.bam";
			my $target_intervals =
				 $wd . $name . $region . "_local_realigner.intervals";

 			push(@local_realignment_commands, 
 				"$JOB_SCRIPT_LOCAL_REALIGNMENT ".
				"--inputbam $bamfile ".
				"--region $region ".
				"--outputfilename $region_bam ".
				"--target_intervals $target_intervals"
 			);

 			push (@realignbams, $region_bam);

		}
	
		$BitQC->createPBSJob(
			cmd 		=> \@local_realignment_commands,
			name 		=> 'local_realignment',
			job_opts 	=> {
				cput   => '72000'
			},
			message =>"Local realignment jobs submitted for $name"
		);

		########################################################
		# MERGE BAM FILES
		#######################################################

		my $mergecommand = $JOB_SCRIPT_MERGE." --name ".$bamfile;

		foreach (@realignbams) {
			$mergecommand .= " --bamchuncks ".$_;
		}
	
		$BitQC->createPBSJob(
			cmd 		=> $mergecommand,
			name 		=> 'merge',
			job_opts 	=> {
				cput   => '28000'
			},
			message => "Merge job submitted for local realigned bam chuncks for $name"
		);
	}

	########################################################
	# REMOVE DUPLICACTES
	#######################################################

	if ( defined($RMDUP) && $RMDUP ) {
	
		$BitQC->createPBSJob(
			cmd 		=> $JOB_SCRIPT_REMOVE_DUPLICATES." --bam $bamfile",
			name 		=> 'remove_duplicates',
			job_opts 	=> {
				cput   => '72000'
			},
			message => "Duplicate marking job submitted for $name" 
		);
	}

	########################################################
	# RECALIBRATE
	#######################################################
	if ( defined($RECALIBRATE) && $RECALIBRATE ) {
		
		# index first!!
		$BitQC->createPBSJob(
			cmd 		=> $JOB_SCRIPT_BAM_INDEX." --bam $bamfile",
			name 		=> 'index',
			job_opts 	=> {
				cput   => '28000'
			},
			message => "Index creation job submitted for $name to enable recalibration"
		);
			
		$BitQC->createPBSJob(
			cmd 		=> $JOB_SCRIPT_RECALIBRATE." --bam $bamfile",
			name 		=> 'gatk_recalibrate',
			job_opts 	=> {
				cput   => '230400'
			},
			message =>
				 "Base quality recalibration job for $name submitted"
		);
	}
	########################################################
	# INDEXING
	#######################################################
	if ( defined($INDEX) && $INDEX ) {
		
		# index first!!
		$BitQC->createPBSJob(
			cmd 		=> $JOB_SCRIPT_BAM_INDEX." --bam $bamfile",
			name 		=> 'index',
			job_opts 	=> {
				cput   => '28000'
			},
			message => "Index creation job submitted for $name"
		);
	}

	########################################################
	# store
	########################################################

	$bam[$fileindex] = $bamfile;

	if ( defined($OUTPUT) && $OUTPUT ) {
		# create a bitQC file object for the output file
		my $outputbamfile;

		if (-d $OUTPUT){
			# user wants us to copy the file to the output dir

			# create local file object
			$OUTPUT .= '/' unless ($OUTPUT =~/\/$/); # make sure we have a trailing /

			$outputbamfile = $BitQC->{fileadapter}->createFile( {
		 		'filetype' => 'bam',
   				'file' => $OUTPUT.$name.'.bam',
				'type' => 'local'
			});
		} elsif ($OUTPUT) {
			# create file object and file pointer
			my %filehash = %$OUTPUT; # we take the parameters the user set for output files

			# we now modify these settings for the paired fastq file (retaining host and path specific info)
			delete ($filehash{compression}); # outputbamfile has its own compression
			$filehash{filetype} = 'bam';
			$filehash{name} = $name;
			$filehash{path} = $sample_id if ($filehash{type} eq 'mongodb');
			$filehash{ext} = '.bam';
			delete ($filehash{file}); # will be rebuilt from the hash
			$outputbamfile = $BitQC->{fileadapter}->createFile(\%filehash);
		}

		# @bam will be a list of file hashes
		my %bamhash = $outputbamfile->getFileInfo();
		$bam[$fileindex] = \%bamhash;

		if ($PROJECTID){
			# update the sample record by adding the bam file if not already there
			$BitQC->{DatabaseAdapter}->addtoSet(
				collection => $SAMPLESCOL, 
				id => MongoDB::OID->new( value => $sample_id),
				array => 'files',
				element => \%bamhash
			);
		}

		my $storecommand = $JOB_SCRIPT_STORE;
		$storecommand .= " --nocompress --inputfile type=local --inputfile file=".$bamfile;

		foreach my $arg (keys %bamhash){
			$storecommand .= " --outfile ".$arg."=".$bamhash{$arg};
		}

		$BitQC->createPBSJob(
			cmd 		=> $storecommand,
			name 		=> 'store',
			job_opts 	=> {
				cput   => '72000'
			},
			message => "Storage job submitted for $bamfile"  
		);

	}

	$fileindex++;

	########################################################
	# NOTIFY
	#######################################################

	# create a notification message
	my $notify_fh;
	my $notify_filename;
	( $notify_fh, $notify_filename ) =
	  tempfile( "notify_messageXXXXXX", DIR => $wd, SUFFIX => '.html' );
	my $message = CGI->new;
	print $notify_fh $message->header('text/html'), $message->start_html();
	print $notify_fh "<p>Dear_user,<p>The processing of your data has successfully completed for file $name.<BR>The job id of your job was "
	  . "$BITQC_LOG_ID <p> this was file $fileindex of ".@inputfiles." total files.";
	print $notify_fh $message->end_html();

	my $finish_fh;
	my $finish_filename;
	( $finish_fh, $finish_filename ) =
	  tempfile( "finish_messageXXXXXX", DIR => $wd, SUFFIX => '.txt' );
	print $finish_fh "The processing of the files is complete";

	# create job to notify user if all went well
	my $notifycommand = $JOB_SCRIPT_NOTIFY;
	$notifycommand .= " --subject Job_$BITQC_LOG_ID --message $notify_filename --finish_master --finish_master_message $finish_filename";

	$BitQC->createPBSJob(
		cmd 		=> $notifycommand,
		name 		=> 'notify',
		job_opts 	=> {
			cput   => '30',
#			nodes  => $BITQC_PBS_SERVER # enable this if jobs cannot submit other jobs from the pbs nodes
		},
		message => "User notification job submitted" 
	);

	$BitQC->submitPBSJobs(message => "Jobs of file $bamfile submitted" );
}

# update the run configuration with the newly created bam files (can be used for subsequent analysis)
$BitQC->setRunConfig('bam', \@bam);

$BitQC->log_message( message => "Updating the configuration to contain the bam files we will be generating" );

######################################################################################
# FINISH
######################################################################################

$BitQC->finish_log(	message => "Mapping script completed, jobs awaiting processing..." );

__END__

=head1 OPTIONS

=head3 Map reads options:

=over 8

=item B<-f --files>		

The input bam of fastq files: A file, list of files, a folder containing files, or a hash containing 
information on the network location of the file. Specify a list of files by specifying this option 
multiple times. When pointed to a folder, all files ending in .fastq, .fastq(.gz|.bz) or .bam will be used as input. 
Ftp or mongodb download can be specified, but not using the command line, see the manual section on specifying
network input for more informtion.

=item B<-p --pair>		

The fastq files to be used as pairs in an analysis, the same rules apply as for the --input option.
B<WARNING:> the number and order of the files specified here should be exactly the same as the ones specified 
for the fastq argument so we can create pairs. When using a folder for this argument the files in this 
folder should have the same names as the files for the fastq argument (or have the same order when UNIX sorted)

=item B<-o --output>

A directory where output files will be written to, can also contain an hash with BitQC::File object parameters
for remote data storage (not available via the command line)

=item B<-m --mapper>

The mapping strategy to be used while mapping. Valid values are: bwa, bwasw or bowtie

=item B<--mapoptions>

A list of key value pairs to specify the mapping options, see the aligners manual for possible value's. 
Specify values as key=value pairs, specify as much options as you like by repeating this argument

=item B<-s --sort>

Sort the generated alignment files. [true]

=item B<-i --index>

Index the generated alignment files. [true]

=item B<-d --rmdup>

Remove duplicate reads using picard tools. [true]

=item B<-r --recal>

Mark duplicate reads using Picard tools. [true]

=item B<-l --local_realignment>

Perform local realignement using the Genome analysis toolkit. [false]

=item B<--remove>

remove all temporary files generated in the alignment process. Mostly for debug purposes. [true]

=item B<--chuncksize>

Integer value for the number of reads to be	used in a single mapping job [2000000]

=item B<--platform>

The sequencing platform used to generate the reads valid value's are: ILLUMINA, SOLID,
LS454, HELICOS and PACBIO

=item B<--projectid>

The mongo dabtabase id of the project

=item B<--projectcol>

the mongo collection where project records are stored [projects]

=item B<--samplescol>

The mongo database collection the sample names will be storesd in. [samples]

=item B<--samples>

The name of the sample of which the file contains data, when a projectid is specified, a sample
record will be created to hold the information on this sample and all files generated will be attached
to that sample record. Optionally can contain a hash of samplename=>sampleid key value pairs if sample
records already exist in the database. Can be specified multiple times, if so the order of the
names should match the number of the fastq and the pair files.

=back

=head3 BitQC options:

Options used to configure the BitQC module used for logging and script configuration

=over 8

=item B<-h --help>

Print a brief help message and exit.

=item B<-m --man>

Display the manual page.

=item B<-v --verbose>

Print more verbose information when running. Mostly for debug purposes. [false]

=item B<--email_to>	

A list of valid email addresses, specify multiple times for multiple emails to be sent.
An email will be sent to all adresses specified on success or failure.

=item B<--email_from>

The email address sending the notification emails.

=item B<--errormessage>

The error message to be sent when the script fails. either a text or html, the message or a file containing the message.

=item B<--errorsubject>

The subject of the mail being sent on error.

=item B<--config_id>

The mongodb script config id to use in this analysis.

=item B<--genomebuild>

The reference genome to use for alignemnt.

=item B<--server_id>

The mongodb server id to perform the analysis with.

=item B<--bitqc_host>

host to running the BitQC database. [localhost]

=item B<--bitqc_port>

port the BitQC database is running on. [27017]

=item B<--bitqc_db>

The BitQC database name used. [bitqc]

=item B<--log_coll>

The BitQC logging collection. [log]

=item B<--server_coll>

The BitQC server collection. [servers]

=item B<--config_coll>

The BitQC config collection. [config]

=item B<--genome_coll>

The BitQC genomes collection. [genome]

=item B<--db_config>

whether to use the BitQC database for storing the run config. [true]

=item B<--startlog>

Whether to use the BitQC logging in the	database, if false logging will be printed to 
STDOUT. [true]

=back

=head1 Network input

Generating a configuration object with the seqplorer webtool rather than teh command line all input files can be
encoded as an array of BitQC::File objects. This way we can use remote network files as input for this script.
These options are mainly inteded for usage of this script as a backend for a web tool.
See the BitQC::File code for more information

The hash keys are:

=over 8

=item B<type>

one of ftp, http, https, mongodb, ssh


=item B<host>

the hostname of the ftp, http, https or ssh server

=item B<user>

the username to login

=item B<pass>

the password to login
			
=item B<file>

the full path to the file to use as input (relative for wab url's absolute for local or ssh files)

=item B<name>

the name of the sample in this file, if not specified the file name will be used

=item B<compression>

when the file is compressed, the compression method, one of gzip, bzip

=back

=cut