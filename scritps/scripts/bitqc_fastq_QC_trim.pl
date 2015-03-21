#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use PBS::Client;

#use lib::functions;
use BitQC;

######################################################################################
#CREATE A BiTQC OBJECT AND START LOGGING
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'fastq' 	=> { required => 1, type => "string", array => 1, short => "f" },
		'outdir' 	=> { required => 1, type => "directory", short => "o" },
		'remove' 	=> { default => boolean::true, type => "bool" },
		'pair' 		=> { type    => "string",       array => 1, short => "p" },
		'trim' 		=> { default => boolean::false, type  => 'bool' },
		'quality'	=> { default => boolean::true, type => 'bool' },
		'trim_first_base' => { type    => "int"  },
		'trim_last_base' => { type    => "int"  },
		'quality_offset' => { required => 1, type => "string"}
	}
);

#Prepare commands
$BitQC->prepareNode( 'jobscripts' );

#Fastq paired tests
if (   defined( $BitQC->{run_config}->{fastq} )
	&& defined( $BitQC->{run_config}->{pair} ) )
{
	$BitQC->log_error(
		message => "Please specify as many fastq files as pairs." )
	  unless (
		scalar( @{ $BitQC->{run_config}->{fastq} } ) ==
		scalar( @{ $BitQC->{run_config}->{pair} } ) );
}

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Retrieve configuration id
my $BITQC_CONFIG_ID = $BitQC->{run_config}->{config_id};

#Database variables
my $BITQC_DATABASE_HOST = $BitQC->{run_config}->{bitqc_host};
my $BITQC_DATABASE_PORT = $BitQC->{run_config}->{bitqc_port};
my $BITQC_DATABASE_NAME = $BitQC->{run_config}->{bitqc_db};
my $BITQC_CONFIG_COLL   = $BitQC->{run_config}->{bitqc_config_coll};

#Log variables
my $BITQC_LOG_ID = $BitQC->{log_id};

#Retrieve executables variables
my $BITQC_MONGOFILES_COMMAND =
  $BitQC->{node_config}->{executables}->{mongofiles}->{command};
my $BITQC_JOBSCRIPTS_PATH =
  $BitQC->{node_config}->{executables}->{jobscripts}->{path};

#Other
my $OUTPUT_DIR = $BitQC->{run_config}->{outdir};

#Queue
my $BITQC_PBS_QUEUE  = $BitQC->{node_config}->{pbs}->{queue};
my $BITQC_PBS_SERVER = $BitQC->{node_config}->{pbs}->{server};

#Email variables
my $TO_EMAIL   = $BitQC->{run_config}->{email_to};     #array ref
my $FROM_EMAIL = $BitQC->{run_config}->{email_from};

#File variables
my @FASTQ_FILES = @{ $BitQC->{run_config}->{fastq} };
my @FASTQ_PAIRS = @{ $BitQC->{run_config}->{pair} };

#Job scripts
my $JOB_SCRIPT_FATSQC = "jobs_fastqc.pl";
my $JOB_SCRIPT_NOTIFY = "jobs_notify.pl";
my $JOB_SCRIPT_TRIM   = "jobs_fastq_trim.pl";

# other variables
my $TRIM 			= $BitQC->{run_config}->{trim};
my $TRIM_FIRST_BASE = $BitQC->{run_config}->{trim_first_base};
my $TRIM_LAST_BASE 	= $BitQC->{run_config}->{trim_last_base};
my $QC   			= $BitQC->{run_config}->{quality};
my $QUALITY_OFFSET	= $BitQC->{run_config}->{quality_offset};

#Quality offset/platform
my $QUALITY_OFFSETS = {	"Sanger"	=> 33,
						"Solexa" 	=> 64,
						"Illumina 1.3"	=> 64,
						"Illumina 1.4"	=> 64,
						"Illumina 1.5"	=> 64,
						"Illumina 1.6"	=> 64,
						"Illumina 1.7"	=> 64,
						"Illumina 1.8"	=> 33,
						"Illumina 1.8+"	=> 33
					};
					
					
######################################################################################
# CHECK IF GIVEN QUALITY OFFSET IS SUPPORTED BY THE SCRIPT
######################################################################################

if(!defined($QUALITY_OFFSETS->{$QUALITY_OFFSET})){
	$BitQC->log_error(
		message	=> "Given quality offset ($QUALITY_OFFSET) isn't supported.\n ".
				   " Following values are currently supported: ".join(', ',keys %{$QUALITY_OFFSETS}).". "
	);
}

######################################################################################
# CREATE ARRAY OF FASTQ FILES
######################################################################################

# get the fastq files to work on
if ( $#FASTQ_FILES == 0 ) {
	my @fastq;
	if ( -d $FASTQ_FILES[0] ) {

		# the fastq files are specified as a directory, list all fastq files
		opendir( DIR, $FASTQ_FILES[0] );
		my @files =
		  grep( /\.fastq$/, readdir(DIR) );    # search files ending in .fastq
		closedir(DIR);
		foreach ( sort (@files) ) {
			push( @fastq, $FASTQ_FILES[0] . $_ );
		}
		$BitQC->{run_config}->{fastq} = \@fastq;
		$BitQC->replaceRunConfig();
		@FASTQ_FILES = @{ $BitQC->{run_config}->{fastq} };
	}
}    # else: more files are specified, we don't change anything to the config

# get the pairs of the fastq files to work on
if ( $#FASTQ_PAIRS == 0 ) {
	my @fastq;
	if ( -d $FASTQ_PAIRS[0] ) {

		# the fastq files are specified as a directory, list all fastq files
		opendir( DIR, $FASTQ_PAIRS[0] );
		my @files =
		  grep( /\.fastq$/, readdir(DIR) );    # search files ending in .fastq
		closedir(DIR);
		foreach ( sort (@files) ) {
			push( @fastq, $FASTQ_PAIRS[0] . $_ );
		}
		$BitQC->{run_config}->{pair} = \@fastq;
		$BitQC->replaceRunConfig();
		@FASTQ_PAIRS = @{ $BitQC->{run_config}->{pair} };
		push @FASTQ_FILES, @FASTQ_PAIRS; #Push paired files into fastq files
	}
}    # else: more files are specified, we don't change anything to the config

######################################################################################
# START THE QC PROCESS
######################################################################################

# create temp dir as a working dir
my $wd;
my $dt = DateTime->now;
$wd = tempdir( $0 . "_" . $dt->ymd . "-" . $dt->hms('-') . "_XXXXXX",
	DIR => $OUTPUT_DIR );
chdir $wd;

#Create PBS client
my $client = PBS::Client->new();

# create job to notify user upon error
my %error = (
	log_id            => $BITQC_LOG_ID,
	database_host     => $BITQC_DATABASE_HOST,
	database_port     => $BITQC_DATABASE_PORT,
	database_name     => $BITQC_DATABASE_NAME,
	config_coll       => $BITQC_CONFIG_COLL,
	subject           => "Job_" . $BITQC_LOG_ID,
	subject_delimiter => "_",
	message =>
"<html><body><strong>Dear_user</strong>,<p>Your_fatsq_QC_or_trimming_job_with_id_"
	  . $BITQC_LOG_ID
	  . "_has_failed.</p>
<p>Please_contact_the_system_administrators_for_more_information.</p></body></html>",
	message_delimiter => "_",
);

my $error = PBS::Client::Job->new(
	name    => 'error',
	cmd     => $BITQC_JOBSCRIPTS_PATH . $JOB_SCRIPT_NOTIFY,
	wd      => $wd,
	vars    => {%error},
	wallt   => '30',
	cput    => '30',
	queue   => $BITQC_PBS_QUEUE,
	mailopt => "e"
);


########################################################
# SPLIT AND MAP
########################################################

#Map each fastq file
my $fastqindex = 0;
foreach (@FASTQ_FILES) {
	my $job;

	#get the name, path and extension
	my $fastqname;
	my $fastqpath;
	my $fastqext;
	( $fastqname, $fastqpath, $fastqext ) =
	  fileparse( $FASTQ_FILES[$fastqindex], '\..*' );

	# Make the fastq file local:
	# open a file pointer to the fastq file
	my $fastq = $FASTQ_FILES[$fastqindex];
	if ( -e $fastq ) {

		# do nothing?
	}
	else {

		# try the mongo database for a bzip2 compressed fastq file
		open( FASTQ,
"$BITQC_MONGOFILES_COMMAND -d $BITQC_DATABASE_NAME get $fastq -l -| sed 1d | bzcat |"
		);

		# TODO: open a file pointer to a web url
		# something like: open( FASTQ, "wget $fastq -O - |");
	}

	# open file pointer if it is defined
	if ( defined( $FASTQ_PAIRS[$fastqindex] )
		&& $FASTQ_PAIRS[$fastqindex] )
	{
		my $pair = $FASTQ_FILES[$fastqindex];
		if ( -e $pair ) {

			# do nothing?
		}
		else {

			# try the mongo database!
			open( FASTQ_2,
"$BITQC_MONGOFILES_COMMAND -d $BITQC_DATABASE_NAME get $pair -l -| sed 1d | bzcat |"
			);
		}
	}
	
	########################################################
	# TRIM
	########################################################
	if ($TRIM) {
		my %vars = (
			log_id        => $BITQC_LOG_ID,
			database_host => $BITQC_DATABASE_HOST,
			database_port => $BITQC_DATABASE_PORT,
			database_name => $BITQC_DATABASE_NAME,
			config_coll   => $BITQC_CONFIG_COLL,
			config_id     => $BITQC_CONFIG_ID,
			fastq_file    => $fastq,
			first_base	  => $TRIM_FIRST_BASE,
			last_base	  => $TRIM_LAST_BASE,
			quality_offset=> $QUALITY_OFFSET
		);

		my $trimjob = PBS::Client::Job->new(
			name  => "fastq_trimming",
			cmd   => $BITQC_JOBSCRIPTS_PATH . $JOB_SCRIPT_TRIM,
			vars  => {%vars},
			wd    => $wd,
			queue => $BITQC_PBS_QUEUE,
			wallt => '08:00:00',
			cput  => '28800'
		);
		$job = $trimjob;

		$BitQC->log_message( message => "Fastq trimming job submitted" );
	}

	########################################################
	# QUALITY CONTROL
	########################################################
	if ($QC) {
		my %vars = (
			log_id        => $BITQC_LOG_ID,
			database_host => $BITQC_DATABASE_HOST,
			database_port => $BITQC_DATABASE_PORT,
			database_name => $BITQC_DATABASE_NAME,
			config_coll   => $BITQC_CONFIG_COLL,
			config_id     => $BITQC_CONFIG_ID,
			fastq_file    => $fastq,
		);

		my $fastqcjob = PBS::Client::Job->new(
			name  => "fastqc",
			cmd   => $BITQC_JOBSCRIPTS_PATH . $JOB_SCRIPT_FATSQC,
			vars  => {%vars},
			wd    => $wd,
			queue => $BITQC_PBS_QUEUE,
			wallt => '08:00:00',
			cput  => '28800'
		);

		if ($job) {
			$fastqcjob->prev( { ok => $job } );
		}

		$job = $fastqcjob;

		$BitQC->log_message( message => "Quality control job submitted" );
	}

	########################################################
	# NOTIFY
	#######################################################
	my %notify = (
		log_id            => $BITQC_LOG_ID,
		database_host     => $BITQC_DATABASE_HOST,
		database_port     => $BITQC_DATABASE_PORT,
		database_name     => $BITQC_DATABASE_NAME,
		config_coll       => $BITQC_CONFIG_COLL,
		config_id         => $BITQC_CONFIG_ID,
		subject           => "Job_" . $BITQC_LOG_ID,
		subject_delimiter => "_",
		message =>
		  "<html><body><strong>Dear_user</strong>,<p>Your_fastq_trim_quality_controller_with_id_"
		  . $BITQC_LOG_ID
		  . "_has_finished_successfully.</p></body></html>",
		message_delimiter         => "_",
		finish_master             => 'true',
		finish_message            => 'Fastq_QC_trim_sucessfully_finished.',
		finfish_message_delimiter => "_",
	);
	my $notify = PBS::Client::Job->new(
		name  => 'notify',
		cmd   => $BITQC_JOBSCRIPTS_PATH . $JOB_SCRIPT_NOTIFY,
		wd    => $wd,
		vars  => {%notify},
		queue => $BITQC_PBS_QUEUE,
		wallt => '30',
		cput  => '30',
		prev  => { ok => $job },
		next  => { fail => $error }
	);

	$client->qsub($notify);

	$fastqindex++;
}

######################################################################################
# FINISH
######################################################################################

$BitQC->finish_log(
	message => "Fastq Quality controller and trimmer jobs submitted and awaiting processing..." 
);

######################################################################################
# SUBROUTINES
######################################################################################

__END__

=head1 NAME

fastq_QC_trim.pl - A script to trim a fastq file based on given trim options with the possibility to execute a new quality control on the generated trimmed file.

=head1 SYNOPSIS

fastq_QC_trim.pl [options]

Use -? to see options

=head1 OPTIONS

=over 8

=item B<-h -? --help>			Print a brief help message and exits.

=item B<-m --man>				Displays the manual page.

=item B<-v --verbose>			Print more verbose information when running. Mostly for debug purposes. [false]

=item B<-f --fastq>				The input fastq file: A fastq file, list of fastq files or a folder of fastq files. Specify a list of files by specifieing this option multiple times when pointed to a folder, all files ending in .fastq will be mapped

=item B<-p --pair>				The fastq files to be used as pairs in an analysis, specify multiple times for multiple files to be used. WARNING: the number and order of the files specified should be exactly the same as the ones specified for the fastq argument so we can create pairs then using a folder for this argument the files in this folder should have the same names as the files for the fastq argument (or have the same order when UNIX sorted)

=item B<--quality>				When set a quality control will be executed on the fastq file.

=item B<--quality_offset> 		The sequencing platform used to generate the reads valid value's are: Sanger, Solexa, Illumina 1.3, Illumina 1.4, Illumina 1.5, Illumina 1.6, Illumina 1.7, Illumina 1.8, Illumina 1.8+

=item B<--trim> 				When set the fastq file will be trimmed.

=item B<--trim_first_base>		Integer to tell the script what the first base is to trim on.

=item B<--trim_last_base>		Integer to tell the script what the last base is to trim on.
	
=item B<--email_to>				a list of valid email addresses, specify multiple times for multiple emails to be sent. An email will be sent to all adresses specified on success or failure.

=item B<--email_from>			The email address sending the notification emails.

=item B<--remove>				remove all temporary files generated in the alignment process. Mostly for debug purposes. [true]

=item B<--config_id>			The mongodb script config id to use in this analysis.

=item B<--server_id>			The mongodb server id to perform the analysis with.

=item B<--bitqc_host>			host to running the BitQC database. [localhost]

=item B<--bitqc_port>   		port the BitQC database is running on. [27017]

=item B<--bitqc_db>     		The BitQC database name used. [bitqc]

=item B<--bitqc_log_coll>		The BitQC logging collection. [log]

=item B<--bitqc_server_coll>	The BitQC server collection. [servers]

=item B<--bitqc_config_coll>	The BitQC config collection. [configurations]

=item B<--bitqc_genome_coll>	The BitQC genomes collection. [genome]

=item B<--db_config>			whether to use the BitQC database for storing the run config. [true]

=item B<--startlog>				whether to use the BitQC logging in the database, if false logging will be printed to STDOUT. [true]

=back

=head1 DESCRIPTION

B<fastq_QC_trim> A script to trim a fastq file based on given trim options with the possibility to execute a new quality control on the generated trimmed file.

=cut

