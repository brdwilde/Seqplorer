#!/usr/bin/perl -w

=head1 LICENSE

  No licence yet?

=head1 CONTACT

  Please email comments or questions to the 
  developer at <gbramdewilde@gmail.com>.

=cut

=head1 NAME

Bitqc Call Variants - A script to call variants fromn next generation sequencing data

=head1 SYNOPSIS

call_variants.pl [options]

Use --help to see options, --man to see extended manual

by Bram de Wilde (gbramdewilde@gmail.com)

=head1 DESCRIPTION

B<call_variants> a script to genomic variants like snp's and indel's from binary alignemnt (BAM) format files.

=cut


#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use File::Temp qw/ tempfile tempdir/;
use BitQC;
use CGI;
use MongoDB::OID;
use Data::Dumper::Simple;

######################################################################################
#CREATE A BiTQC OBJECT AND START LOGGING
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'files' 		=> { required => 1, type => "string", array => 1, short => "f" },
		'bampair' 		=> { type => "string", array => 1 },
		'bamtrio' 		=> { type => "string", array => 1 },
		'output' 		=> { required => 1, type => "string", short => "o" },
		'genomebuild' 	=> { required => 1,            type => 'string' },
		'regions'     	=> { type     => "string",       short => "r" },
		'algorithm' 	=> { required => 1, type => "string", short => "a" },
		'multisample' 	=> { default => boolean::false,  type => "bool" },
		'trimchr' 	=> { default => boolean::false,  type => "bool" },
		'varrecal'		=> { default  => boolean::false, type  => "bool" },
		'calloptions'	=> { type    => "string",       hash => 1 },
		'filteroptions'	=> { type    => "string",       hash => 1 },
		'remove' 		=> { default => boolean::true, type  => "bool" },
		'projectid' 	=> { type     => "string" },
		'projectcol' 	=> { default => 'projects', type => "string" },
		'samples' 		=> {type => 'string', hash =>1 },
		'samplescol' 	=> { default  => 'samples',      type  => "string" },
		'minallelequal'		=> { default  => 0,              type  => "int" },
		'passfilter'      	=> { default  => boolean::false, type  => "bool" },
		'mincov'          	=> { default  => 5,              type  => "int" },
		'mingenotypequal' 	=> { type     => "int" },
		'minsamplecov'    	=> { default  => 5,              type  => "int" },
		'vcfsamples'      	=> { type     => "string",       array => 1 },
		'variantscol'     	=> { default  => 'variants',     type  => "string" },
		'vcfheadercol'    	=> { default  => 'vcfheader',    type  => "string" }
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Log variables
my $BITQC_LOG_ID = $BitQC->{log_id};

#variables
my @FILES           	= @{ $BitQC->getRunConfig('files') };
my @BAM_PAIRS;
@BAM_PAIRS 			= @{ $BitQC->getRunConfig('bampair') } if ($BitQC->getRunConfig('bampair'));
my @BAM_TRIOS;
@BAM_TRIOS 			= @{ $BitQC->getRunConfig('bamtrio') } if ($BitQC->getRunConfig('bamtrio'));

my $ALGORITHM     = $BitQC->getRunConfig('algorithm');
my $OUTPUT 		  	= $BitQC->getRunConfig('output');
my $RECAL         	= $BitQC->getRunConfig('varrecal');
my $REGIONS       	= $BitQC->getRunConfig('regions');
my $MULTISAMPLE   	= $BitQC->getRunConfig('multisample');
my $PROJECTID  		= $BitQC->getRunConfig('projectid');
my $PROJECTCOL 		= $BitQC->getRunConfig('projectcol');
my $SAMPLESCOL 		= $BitQC->getRunConfig('samplescol');
my $TRIMCHR 		= $BitQC->getRunConfig('trimchr');
my $GZIP_COMMAND 	= $BitQC->getCommand('gzip');
my $BGZIP_COMMAND 	= $BitQC->getCommand('bgzip');
my %SAMPLES;
my $SAMPLES = $BitQC->getRunConfig('samples');
# make sure we can accept a array of sample id's comming form the mapping script
if (ref ($SAMPLES) eq 'HASH'){
	%SAMPLES  = %{$SAMPLES};
} elsif (ref ($SAMPLES) eq 'ARRAY'){
	foreach my $sample (@$SAMPLES){
		foreach my $id (keys %{$sample}){
			$SAMPLES{$id} = $sample->{$id};
		}
	}
	$BitQC->setRunConfig('samples', \%SAMPLES);
}
my $SAMPLESCOLL       = $BitQC->getRunConfig('samplescol');
my $VCFHEADERCOLL     = $BitQC->getRunConfig('vcfheadercol');

#Job scripts
my $BITQC_JOBSCRIPTS_PATH = $BitQC->{node_config}->{executables}->{jobscripts}->{path};

my $JOB_SCRIPT_NOTIFY   = $BITQC_JOBSCRIPTS_PATH . "notify.pl";
my $JOB_SCRIPT_STORE	= $BITQC_JOBSCRIPTS_PATH . "store_file.pl";
my $JOB_BAM2VCF       	= $BITQC_JOBSCRIPTS_PATH . "call_variants.pl";
my $JOB_VCF_CONCAT    	= $BITQC_JOBSCRIPTS_PATH . "concatenate_vcfs.pl";
my $JOB_VCF_PARSE		= $BITQC_JOBSCRIPTS_PATH . "parse_vcf_header.pl";
my $JOB_VCF_RECALIBRATE = $BITQC_JOBSCRIPTS_PATH . "recalibrate_vcf.pl";
my $JOB_VCF_SORT             	= $BITQC_JOBSCRIPTS_PATH . "sort_vcf.pl";
my $JOB_VCF_VARIANT_EXTRACT 	= $BITQC_JOBSCRIPTS_PATH . "extract_variants.pl";
my $JOB_VCF_VARIANT_ANNOTATE 	= $BITQC_JOBSCRIPTS_PATH . "annotate_variants.pl";

my $cores = 1;
if ( $ALGORITHM eq "gatk2_haplo" ) {
	$cores = 4;
}

#indexes and commands
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');
my $SAMTOOLS_INDEX = $BitQC->getGenomeIndex('samtools');
my $GENOMEBUILD 		= $BitQC->getRunConfig('genomebuild');

######################################################################################
# CHECK IF THE INPUT IS VALID
######################################################################################

# check if the number of paired files is as large as the number of forward bam files
if ( @FILES && @BAM_PAIRS ) {
	$BitQC->log_error(
		message => "Please specify as many pair files as bam files." )
	  unless ( scalar( @FILES) == scalar( @BAM_PAIRS ) );
}
# perform the same check but this time for the sample names
if ( @FILES && @BAM_TRIOS ) {
	$BitQC->log_error(
		message => "Please specify as many trio files as bam files." )
	  unless ( scalar( @FILES) == scalar( @BAM_TRIOS ) );
}
if ($ALGORITHM eq 'somaticsniper'){
	$BitQC->log_error(
		message => "Please specify a paired bam file to enable somaticsniper variant calling." )
	  unless ( @FILES&& @BAM_PAIRS  );
}

######################################################################################
# CREATE ARRAYS OF BAM BitQCFile objects
######################################################################################

# get the bam input files
my @files = $BitQC->{fileadapter}->getLocal(\@FILES,'bam');
my @filesconfig;

# if no bam files are specified, get the vcf input files
@files = $BitQC->{fileadapter}->getLocal(\@FILES,'vcf') unless (@files);

foreach(@files){
	my %filehash = $_->getFileInfo();
	push (@filesconfig,\%filehash);
}
$BitQC->setRunConfig('files', \@filesconfig);

# get the optional bam pairs and trio's
my @bampairs;
my @bamtrios;
if (@BAM_PAIRS){
	@bampairs = $BitQC->{fileadapter}->getLocal(\@BAM_PAIRS,'bam');
	my @pairconfig;
	foreach(@bampairs){
		my %filehash = $_->getFileInfo();
		push (@pairconfig,\%filehash);
	}
	$BitQC->setRunConfig('bampair', \@pairconfig);

	if (@BAM_TRIOS){
		@bamtrios = $BitQC->{fileadapter}->getLocal(\@BAM_TRIOS,'bam');
		my @trioconfig;
		foreach(@bamtrios){
			my %filehash = $_->getFileInfo();
			push (@trioconfig,\%filehash);
		}
		$BitQC->setRunConfig('bamtrio', \@trioconfig);
	}
}

######################################################################################
# START CALLING PROCESS
######################################################################################

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

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

######################################################################################
# GET THE REGIONS TO PARALLELIZE JOBS
######################################################################################

my @regions = `awk '{ print \$1 }' $SAMTOOLS_INDEX.fai`;
chop(@regions);

######################################################################################
# FOR EACH INPUT FILE ASSOCIATE IT WITH A DATABASE SAMPLE IF REQUIRED
######################################################################################

my $fileindex = 0;
my @vcffiles;

foreach my $file (@files) {

	my $type = $file->getInfo('filetype');

	# hash to contain the vcf file generated
	my %vcfhash;

	if ($type eq 'bam'){
		#get the name of the file
		my $filename = $file->getInfo('name');
		my $bamfile = $file->getInfo('file');

		my $sample_id;
		
		my %fileshash = $file->getFileInfo();

		# create array to hold all the input bam files
		my @files = (\%fileshash);

		if ($bampairs[$fileindex]){
			# add the paired bam file to the files array
			my %pairhash = $bampairs[$fileindex]->getFileInfo();
			push (@files, \%pairhash);
		}
		my $triofile;
		if ($bamtrios[$fileindex]){
			# add the bam trio to the files array
			my %triohash = $bampairs[$fileindex]->getFileInfo();
			push (@files, \%triohash);

			###################################################		
			# CREATE THE TRIO FILE
			###################################################
	
			# create a local file object
			my $file = $BitQC->{fileadapter}->createFile( {
				#'compression' => 'gzip',
    			'filetype' => 'txt',
			   	'name' => $filename.'_trio',
    			'path' => $wd,
    			'type' => 'local',
    			'ext' => '.txt.gz'
			});

			# create file pointer for writing
			my $triopointer = $file->getWritePointer();	

			print $triopointer $filename."\n";
			print $triopointer $BAM_PAIRS[$fileindex]->getInfo('name')."\n";
			print $triopointer $BAM_TRIOS[$fileindex]->getInfo('name')."\n";	

			close($triopointer);

			$triofile = $file->getInfo('file');
		}

		###################################################
		# ADD FILES AND SAMPLES TO THE DATABASE FOR EACH READ GROUP IN THE BAM FILE
		###################################################
		
		if ( $PROJECTID ){
			# get the read groups for this bam file
			my %readgroups;
			open(my $fh,"-|","$SAMTOOLS_COMMAND view -H $bamfile");
			while (<$fh>){
				chomp;
				if (/^\@RG/) {
					my @line = split(/\t/,$_);
					my $id;
					my $samplename;
					foreach (@line){
						if (/^ID:(.+)/){
							$id = $1;
						} elsif (/^SM:(.+)/){
							$samplename = $1;
						}
					}
					$readgroups{$samplename} = $id;
				}
			}
			close ($fh);

			foreach my $readgroup (keys %readgroups){
				if ($SAMPLES{$readgroup}){
					# we received an id for the read group sample name
					# update the sample record by adding the file if not already there
					$BitQC->{DatabaseAdapter}->addtoSet(
						collection => $SAMPLESCOL, 
						id => MongoDB::OID->new( value => $SAMPLES{$readgroup}),
						array => 'files',
						element => \%fileshash
					);
				} else {
					# no sample specified and known to the database
					# we create the sample and use the read group name as the sample name
					my $sample_obj = $BitQC->{DatabaseAdapter}->insertEntry(
						collection => $SAMPLESCOL,
						fields     => {
							'name'    => $readgroup,
							'project' => [
								{
									'id' => MongoDB::OID->new( value => $PROJECTID ),
									'name' => $project->{name}
								}
							],
							'genome' => $GENOMEBUILD,
							'files' => \@files
						},
						save_mode => 1
					);
					$sample_id = $sample_obj->{value};

					# update the database configuration and the SAMPLES hash
					$BitQC->{run_config}->{samples}->{$readgroup} = $sample_id;
					$BitQC->replaceRunConfig();
					$SAMPLES{$readgroup} = $sample_id;
				}
			}
		}

		###################################################
		# CREATE VARIANT CALLING JOBS AND VCF MERGE JOB
		###################################################

		unless ($MULTISAMPLE){
			# we create a variant calling job for each region
			my @vcfchuncks;
			my @extract_commands;

			foreach my $region (@regions) {

				#create a temporary file in the working directory
				my $reg_vcf_file =
					File::Temp::tempnam( $wd, $filename . "_" . $region . "_XXXXX" );
				$reg_vcf_file .= '.vcf.gz';

				my $command = "$JOB_BAM2VCF --region $region --outputfile $reg_vcf_file --bamindex $fileindex";
				$command .= " --triofile $triofile" if $triofile;

				# add the job script to the array
				push( @extract_commands, $command);
				push (@vcfchuncks, $reg_vcf_file);
			}

			$BitQC->createPBSJob(
				cmd 		=> \@extract_commands,
				name 		=> 'extract_variants',
				job_opts 	=> {
					ppn    => $cores,
					cput   => '216000'
				} 
			);

			# merge the per region vcf files

			# create a local file object
			my $vcf_file = $BitQC->{fileadapter}->createFile( {
				'compression' => 'gzip',
    			'filetype' => 'vcf',
			   	'name' => $filename,
    			'path' => $wd,
    			'type' => 'local',
    			'ext' => '.vcf.gz'
			});
			my $localvcffile = $vcf_file->getInfo('file');

			%vcfhash = $vcf_file->getFileInfo();
			
			my $concatcommand = $JOB_VCF_CONCAT." --name $localvcffile";
			foreach (@vcfchuncks){
				$concatcommand .= " --vcfchuncks ".$_;
			}
		
			$BitQC->createPBSJob(
				cmd 		=> $concatcommand,
				name 		=> 'merge_vcf',
				job_opts 	=> {
					cput   => '72000'
				}
			);

			push (@vcffiles, \%vcfhash);
		}

	} elsif ($type eq 'vcf'){

		%vcfhash = $file->getFileInfo();

		#get the name of the file
		my $vcfname = $file->getInfo('name');
		my $vcffile = $file->getInfo('file');
		$vcffile=~s/ /\\ /g;
		my $vcfext = $file->getInfo('ext');
		my $vcftype = $file->getInfo('type');
		
		##############################################################################
		# CHECK IF VCF FILE IS INDEXED, IF NOT, MAKE LOCAL, SORT, COMPRESS AND INDEX
		##############################################################################
	
		# create index file object
		my $index = $file->duplicateFile({filetype => 'vcf.gz.tbi', ext => '.vcf.gz.tbi', compression => undef});

		if ( !( $index->fileExists() ) ) {

			# there is no index!
			# we asume the file is not sorted either for ease of working
			# sort and index the vcf files, then perform the import to the database

			$BitQC->log_message( message =>
				  "No index found for vcf $vcfname, start by sorting and indexing" );

			# get the vcf file and store locally			
			if ( $vcftype ne 'local'){

				$vcffile = $wd.$vcfname.'-unsorted'.$vcfext;
		
				# sorting can only be done on local vcf files, so get it first

				$vcffile = $wd.$vcfname.'-unsorted'.$vcfext;

				my $storecommand = $JOB_SCRIPT_STORE;

				foreach my $arg (keys %vcfhash){
					# Escape spaces in the filepath
					$vcfhash{$arg}=~s/ /\\ /g;
					$storecommand .= " --inputfile ".$arg."=".$vcfhash{$arg};
				}
				# Escape spaces in the filepath
				$vcffile=~s/ /\\ /g;
				$storecommand .= " --nocompress --outfile type=local --outfile file=".$vcffile;
				$storecommand .= " --noremove";

				$BitQC->createPBSJob(
					cmd 		=> $storecommand,
					name 		=> 'getvcf',
					job_opts 	=> {
						cput   => '72000'
					} 
				);

		
				$BitQC->log_message( message => "$vcfname file is not local; copying file to local working directory" );
			}


			########################################################
			# SORT, COMPRESS AND INDEX
			#######################################################
			# trim chr part from contigs
			if($TRIMCHR){
				my $TRIM_COMMAND;
				if($vcffile =~ /\.gz$/){
					$TRIM_COMMAND="$GZIP_COMMAND -c -d $vcffile";
				}else{
					$TRIM_COMMAND="cat $vcffile";
				}
				$TRIM_COMMAND.=" | sed 's/^chr//' | $BGZIP_COMMAND -c > ".$wd.$vcfname.'-trimmed.vcf.gz'; 
				$BitQC->run_and_log(
					message => "Uncompressing vcf file",
					command => $TRIM_COMMAND
				);
				$vcffile=$wd.$vcfname.'-trimmed.vcf.gz';
			} 
			# compress and index the file first
			my $localfilename = $wd . $vcfname . ".vcf.gz";
			$BitQC->createPBSJob(
				cmd 		=> $JOB_VCF_SORT." --vcf $vcffile --name ".$wd.$vcfname,
				name 		=> 'vcf_sort',
				job_opts 	=> {cput   => '20000'}
			);
			undef(%vcfhash);
			$vcfhash{file} 			= $localfilename;
			$vcfhash{name} 			= $vcfname;
			$vcfhash{type} 			= 'local';
			$vcfhash{compression} 	= 'gzip';
			$vcfhash{filetype}    	= 'vcf';

		}

		push (@vcffiles, \%vcfhash);
	}

	$fileindex++;
}

######################################################################################
# EXTRACT VARIANTS TO VCF FOR BAM INPUT FILES
######################################################################################

if ($MULTISAMPLE) {
	# we create a variant extraction job per region for all the bam imput files
	my @extract_commands;
	my @vcfchuncks;
	foreach my $region (@regions) {
		
		# add the job script to the array

		#create a temporary file in the working directory
		my $reg_vcf_file = File::Temp::tempnam( $wd, $region . "_XXXXX" );
		$reg_vcf_file .= '.vcf.gz';

		push( @extract_commands, "$JOB_BAM2VCF --region $region --outputfile $reg_vcf_file" );
		push (@vcfchuncks, $reg_vcf_file);
	}

	$BitQC->createPBSJob(
		cmd 		=> \@extract_commands,
		name 		=> 'extract_variants',
		job_opts 	=> {
			ppn    => $cores,
			cput   => '720000'
		} 
	);

	#create a temporary file in the working directory
	my $vcf = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
    	'filetype' => 'vcf',
	   	'name' => 'variants_allSamples',
		'path' => $wd,
		'type' => 'local',
		'ext' => '.vcf.gz'
	});

	my %vcfhash = $vcf->getFileInfo();

	my $vcf_file = $vcf->getInfo('file');
	
	my $concatcommand = $JOB_VCF_CONCAT." --name $vcf_file";
	foreach (@vcfchuncks){
		$concatcommand .= " --vcfchuncks ".$_;
	}

	$BitQC->createPBSJob(
		cmd 		=> $concatcommand,
		name 		=> 'merge_vcf',
		job_opts 	=> {
			cput   => '72000'
		}
	);
	push (@vcffiles, \%vcfhash);
}

if ( defined($OUTPUT) && $OUTPUT ) {
	# move the vcf files generated to the appropriate location
	foreach my $vcffile (@vcffiles){

		my $storecommand = $JOB_SCRIPT_STORE;
		$storecommand .= " --nocompress";

		foreach my $arg (keys %$vcffile){
			$vcffile->{$arg}=~s/ /\\ /g;
			$storecommand .= " --inputfile ".$arg."=".$vcffile->{$arg};
		}

		my $filename = $vcffile->{name};
		my $outputvcffile;

		if (-d $OUTPUT){
			$OUTPUT .= '/' unless ($OUTPUT =~/\/$/); # make sure we have a trailing /
			# create local file object

			$outputvcffile = $BitQC->{fileadapter}->createFile( {
				'file' => $OUTPUT.$filename.'.vcf.gz',
				'type' => 'local'
			});

		} elsif (ref($OUTPUT) eq 'HASH') {
			# create file object and file pointer
			my %outputvcffilehash = %$OUTPUT; # we take the parameters the user set for output files

			# we now modify these settings for the paired fastq file (retaining host and path specific info)
			$outputvcffilehash{filetype} = 'vcf';
			$outputvcffilehash{name} = $filename;
			#$outputvcffilehash{path} = $sample_id if ($outputvcffilehash{type} eq 'mongodb');
			$outputvcffilehash{ext} = '.vcf.gz';
			delete ($outputvcffilehash{file}); # will be rebuilt from the hash
			$outputvcffile = $BitQC->{fileadapter}->createFile(\%outputvcffilehash);

		}else{
			$OUTPUT = $wd;
			$OUTPUT .= '/' unless ($OUTPUT =~/\/$/); # make sure we have a trailing /
			$OUTPUT .= 'output/';
			mkdir $OUTPUT unless (-d $OUTPUT);
			# create local file object

			$outputvcffile = $BitQC->{fileadapter}->createFile( {
				'file' => $OUTPUT.$filename.'.vcf.gz',
				'type' => 'local'
			});
		}

		my %vcfhash = $outputvcffile->getFileInfo();
		$vcffile = \%vcfhash;

		foreach my $arg (keys %vcfhash){
			$storecommand .= " --outfile ".$arg."=".$vcfhash{$arg};
		}

		$BitQC->createPBSJob(
			cmd 		=> $storecommand,
			name 		=> 'store',
			job_opts 	=> {
				cput   => '72000'
			} 
		);

		$BitQC->log_message( message => "Storage job submitted for $filename" );	
	}
}

# we now know all the vcf files that we either received as input or that will be generated
# update the database configuration
$BitQC->{run_config}->{vcf} = \@vcffiles;
$BitQC->replaceRunConfig();


#############################################################
# PARSE THE HEADER OF THE VCF FILES SO WE KNOW THE SAMPLE-DATABASE RELATIONS
#############################################################

$BitQC->createPBSJob(
	cmd 		=> $JOB_VCF_PARSE,
	name 		=> 'vcf_parse',
	job_opts 	=> {
		cput   => '72000'
	}
);

#############################################################
# PROCESS THE VCF FILES THEMSELVES
#############################################################
my $index = 0;
foreach my $vcf (@vcffiles){

	my $vcf_file = $vcf->{file};

	#############################################################
	# RECALIBRATE VCF
	#############################################################

	if ($RECAL) {	
		$BitQC->createPBSJob(
			cmd 		=> $JOB_VCF_RECALIBRATE." --vcf $vcf_file",
			name 		=> 'variant_recal',
			job_opts 	=> {
				cput   => '72000'
			}
		);
	}

	#############################################################
	# CREATE A VARIANT EXTRACT AND ANNOTATE JOB FOR EACH REGION
	#############################################################

	my @extractcommands;
	my @annotatecommands;

	foreach my $region (@regions) {
		
		#create a temporary file in the working directory to store the variants we cannot find in the database
		my $unknown_variants_file =
			 File::Temp::tempnam( $wd, $region . "_unknown_variants_XXXXX" );
		$unknown_variants_file =~ s/\.//g; # make sure the file name does not contain any dots (region name sometimes does!)
		$unknown_variants_file .= '.txt.gz';

		######################################################################################
		# INSERT ALL VARIANTS IN THE DATABASE AND ANNOTATE THE VARIANTS
		######################################################################################

		push (@extractcommands, "$JOB_VCF_VARIANT_EXTRACT --region $region --vcfindex $index --unknownvcf $unknown_variants_file ");
		push (@annotatecommands, "$JOB_VCF_VARIANT_ANNOTATE --unknownvcf $unknown_variants_file ");

	}

	$BitQC->createPBSJob(
		cmd 		=> \@extractcommands,
		name 		=> 'variant_import',
		job_opts 	=> {cput  => '20000'}
	);

	$BitQC->createPBSJob(
		cmd 		=> \@annotatecommands,
		name 		=> 'variant_annotate', 
		job_opts 	=> {cput  => '20000'}
	);


	$index++;
}

########################################################
# NOTIFY
#######################################################

# create job to notify user upon success
# create a notification message
my $notify_fh;
my $notify_filename;
( $notify_fh, $notify_filename ) =
	 tempfile( "notify_messageXXXXXX", DIR => $wd, SUFFIX => '.html' );

my $message = CGI->new;
print $notify_fh $message->start_html();
print $notify_fh "<p>Dear_user,<p>The variant calling and the import of your variants to the database has successfully completed.<BR>The job id of your job was ".$BITQC_LOG_ID;
print $notify_fh $message->end_html();
close ($notify_fh);

my $finish_fh;
my $finish_filename;
( $finish_fh, $finish_filename ) = tempfile( "finish_messageXXXXXX", DIR => $wd, SUFFIX => '.txt' );
print $finish_fh "The variant calling and importing is complete";
close ($finish_fh);

# create job to notify user if all went well
my $notifycommand = $JOB_SCRIPT_NOTIFY;
$notifycommand .= " --subject Job_$BITQC_LOG_ID --message $notify_filename --finish_master --finish_master_message $finish_filename";

$BitQC->createPBSJob(
	cmd 		=> $notifycommand,
	name 		=> 'notify',
	job_opts 	=> {
		cput   => '30',
#		nodes  => $BITQC_PBS_SERVER # enable this if jobs cannot submit other jobs from the pbs nodes
	} 
);

$BitQC->submitPBSJobs();

# finish logging
$BitQC->finish_log( message => "Variant calling and import jobs submitted succesfully" );


__END__

=head1 OPTIONS

The options for this script are devided in subsections. The first 2 sections are script specific, the
folowing sections contain options for other scripts called from this script.
We can use the --postprocess argument to call other scripts when this script is finished, required options
for these scripts should already be specified when the first script is run

=head3 variant calling options:

Options used to call variants from an aligned and processed bam file.
These options are used when --postprocess is set to "call_variants"

=over 8

=item B<-r --regions>

A bed file containing genomic regions. Variants will be extracted for these regions in
parallel, If not specified variant extraction will happen genome wide, parallelized by
chromosome.

=item B<-a --algorithm>

either one of gatk, samtools or somaticsniper; the algorithm used for variant calling

=item B<--multisample>

Weither to call variant for each read group or bam file seperatly or use them as a population
for variant calling. [false]

=item B<-b --bampair> 			

The input bam pair files: one, a number of or a directory containing .bam files to call variants on. Specifying this parameter will triger paired analysis focusing the analysis on the similarities and diferences between the samples. The order of the pair files should be the same as the order of the bam files!

=item B<-b --bamtrio>

The input bam trio files: one, a number of or a directory containing .bam files to call variants on. Specifying this parameter will triger trio analysis in which the bam file will be treated as the child, the pair file will be treated as the father and the trio fil wil be treated as the mother. The order of the trio files should be the same as the order of the bam files and the pair files!

=item B<--varrecal>

Perform GATK variant recalibration [false]

=item B<--calloptions>

Options used for variant calling; specify options als key=value pairs, use multiple times
to specify multiple options

=item B<--filteroptions>

Specify the variant filter options as key=value pairs, specify multiple times to use multiple
filters

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

=head3 variant import options:

Options used to import the variants into the mongodb database.
These options are used when --postprocess is set to "variants_to_mongo"

=over 8

=item B<--minallelequal>

The minimal allele quelaity score before a variant will be imported to the database [0]

=item B<--passfilter>

If set to true, will also import variants that did not pass filter criteria into the database [false]

=item B<--mincov>

The minimal coverage at the position of the variant before the variant will be imported in the database.
For moltisample variant calling this is the minimal coverage accross all samples [5]

=item B<--mingenotypequal>

The minimal genotyping quality for the variant to be imported into the database

=item B<--minsamplecov>

The minimal coverage in the sample before the variant will be imported into the database [5]

=item B<--vcfsamples>

A list of sample names to get extracted from the vcf file used as input

=item B<--variantscol>

The collection to import the variants into in the database [variants]

=item B<--vcfheadercol>

The collection to store the vcf header information in, this inforamtion will be used to process the data in the vcf input file [vcfheader]

=back

=head1 Network input

Using the database configuration option all input files can be encoded as an array of BitQC::File objects
This way we can use remote network files as input for this script
These options are mainly inteded for usage of this script as a backend for a web tool
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
