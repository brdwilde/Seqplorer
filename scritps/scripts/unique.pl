#!/usr/bin/perl -w

=head1 LICENSE

  No licence yet?

=head1 CONTACT

  Please email comments or questions to the 
  developer at <gbramdewilde@gmail.com>.

=cut

=head1 NAME

Bitqc unique - A script to get all unique values for all keys in all documents of a collection

=head1 SYNOPSIS

unique.pl [options]

Use --help to see options, --man to see extended manual

by Bram de Wilde (gbramdewilde@gmail.com)

=head1 DESCRIPTION

B<unique> Reduce a collection of documents to its unique values.

=cut


#!/usr/bin/perl -w
use strict;
use warnings;
use BitQC;
use File::Temp qw/ tempfile tempdir /;
use CGI;
use JSON;
use Data::Dumper::Simple;

######################################################################################
#CREATE A BiTQC OBJECT AND START LOGGING
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'parallelkey'     => { type     => "string", default => "c", short => "p" },
		'uniquecoll' => { type => "string", default => "variants", short => "c"},
		'plotscol' => { type => "string", default => "plots"},
		'query' => { type => "string", default => '{}'},
		'maxlist' => { type => "int", default => 1000, short => "m"}
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Log variables
my $BITQC_LOG_ID = $BitQC->{log_id};

#variables
my $PARALLELKEY     = $BitQC->getRunConfig('parallelkey');
my $UNIQUECOLL      = $BitQC->getRunConfig('uniquecoll');
my $QUERY      		= decode_json($BitQC->getRunConfig('query'));

#Job scripts
my $BITQC_JOBSCRIPTS_PATH = $BitQC->{node_config}->{executables}->{jobscripts}->{path};
my $BITQC_SCRIPTS_PATH = $BitQC->{node_config}->{executables}->{scripts}->{path};

my $JOB_SCRIPT_NOTIFY   = $BITQC_JOBSCRIPTS_PATH . "notify.pl";
my $JOB_UNIQUE_MAP 	= $BITQC_JOBSCRIPTS_PATH . "unique_map.pl";
my $JOB_UNIQUE_REDUCE 	= $BITQC_JOBSCRIPTS_PATH . "unique_reduce.pl";

######################################################################################
# CHECK IF THE INPUT IS VALID
######################################################################################

# all input is valid?

######################################################################################
# GET THE VARIANTS FOR THIS GENOME BUILD
######################################################################################

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

# create mongodb connection
$MongoDB::Cursor::timeout = -1; # no timeout
my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();

my $parallel = $mongodb->run_command([ 
    "distinct" => $UNIQUECOLL, 
    "key"      => $PARALLELKEY, 
    "query"    => $QUERY 
]);

my $unique_reducecommand = "$JOB_UNIQUE_REDUCE ";
my @unique_mapcommands;

foreach my $key (@{$parallel->{values}}){
	#create a temporary file in the working directory to store the variants we cannot find in the database
	my $resultfile =
		 File::Temp::tempnam( $wd, $key . "_result_XXXXX" );
	$resultfile =~ s/\.//g; # make sure the file name does not contain any dots (key name sometimes does!)
	$resultfile .= '.txt.gz';

	# create a annotation job for this chromosome
	push (@unique_mapcommands, "$JOB_UNIQUE_MAP --resultfile $resultfile --key $key");

	$unique_reducecommand .= "--resultfile $resultfile ";
}

$BitQC->createPBSJob(
	cmd 		=> \@unique_mapcommands,
	name 		=> 'unique_map', 
	job_opts 	=> {cput  => '72000'}
);

$BitQC->createPBSJob(
	cmd 		=> $unique_reducecommand,
	name 		=> 'unique_reduce', 
	job_opts 	=> {cput  => '72000'}
);

########################################################
# NOTIFY
#######################################################

# create job to notify user upon success
# create a notification message
my $notify_fh;
my $notify_filename;
( $notify_fh, $notify_filename ) =
 	tempfile( "notify_messageXXXXXX", DIR => $wd, SUFFIX => '.html' );

my $notify_message = CGI->new;
print $notify_fh $notify_message->header('text/html'), $notify_message->start_html();
print $notify_fh "<p>Dear_user,<p>The collection $UNIQUECOLL has been reduced.<BR>The job id of your job was ".$BITQC_LOG_ID;
print $notify_fh $notify_message->end_html();

my $finish_fh;
my $finish_filename;
( $finish_fh, $finish_filename ) =
 	tempfile( "finish_messageXXXXXX", DIR => $wd, SUFFIX => '.txt' );
print $finish_fh "The collection has been reduced succesfully";

# create job to notify user if all went well
my $notifycommand = $JOB_SCRIPT_NOTIFY;
$notifycommand .= " --subject Job_$BITQC_LOG_ID --message $notify_filename --finish_master --finish_master_message $finish_filename";

$BitQC->createPBSJob(
	cmd 		=> $notifycommand,
	name 		=> 'notify',
	job_opts 	=> {
		cput   => '30',
	} 
);
	
$BitQC->submitPBSJobs();

# finish logging
$BitQC->finish_log( message => "Collection reduction jobs submitted succesfully" );

__END__

=head1 OPTIONS

=head3 Map reduction options:

=over 8

=item B<-p --parallelkey>

The key to use for parallelization of the mapping phase (sharding key of undelaying database colleciton is probably best) [c]

=item B<-c --uniquecoll>

The colleciton to reduce, resuts will be stored in a collection with the same name and suffix _unique added

=item B<--plotscol>

The collection where to store the plots with the count information

=item B<--query>

A valid mongo query to restrict the mapping to a subset of the records; only valid json is allowed

=item B<-m --maxlist>

The maximum number of unique values for a certain key that will be stored

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

=item B<--server_id>

The mongodb server id to perform the analysis with.

=item B<--bitqc_host>

host to running the BitQC database. [localhost]

=item B<--bitqc_port>

port the BitQC database is running on. [27017]

=item B<--bitqc_db>

The BitQC database name used. [bitqc]

=item B<--bitqc_log_coll>

The BitQC logging collection. [log]

=item B<--bitqc_server_coll>

The BitQC server collection. [servers]

=item B<--bitqc_config_coll>

The BitQC config collection. [configurations]

=item B<--bitqc_genome_coll>

The BitQC genomes collection. [genome]

=item B<--db_config>

whether to use the BitQC database for storing the run config. [true]

=item B<--startlog>

Whether to use the BitQC logging in the	database, if false logging will be printed to 
STDOUT. [true]

=back

=cut