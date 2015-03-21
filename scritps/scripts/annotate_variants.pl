#!/usr/bin/perl -w

=head1 LICENSE

  No licence yet?

=head1 CONTACT

  Please email comments or questions to the 
  developer at <gbramdewilde@gmail.com>.

=cut

=head1 NAME

Bitqc Annotate Variants - A script to update the annotation inforamtion on all variants in the database

=head1 SYNOPSIS

annotate_variants.pl [options]

Use --help to see options, --man to see extended manual

by Bram de Wilde (gbramdewilde@gmail.com)

=head1 DESCRIPTION

B<annotate_variants> a script to update the annotation information of genomic variants in the database.

=cut


#!/usr/bin/perl -w
use strict;
use warnings;
use BitQC;
use File::Temp qw/ tempfile tempdir /;
use CGI;
use Data::Dumper::Simple;

######################################################################################
#CREATE A BiTQC OBJECT AND START LOGGING
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'genomebuild'       => { required => 1,            type => 'string' },
		'regions'     => { type     => "string",       short => "r" },
		'variantscol' => { type => "string", default => "variants"}
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Log variables
my $BITQC_LOG_ID = $BitQC->{log_id};

#variables
my $GENOMBUILD 		= $BitQC->getRunConfig('genomebuild');
my $VARIANTSCOLL      = $BitQC->getRunConfig('variantscol');

#Job scripts
my $BITQC_JOBSCRIPTS_PATH = $BitQC->{node_config}->{executables}->{jobscripts}->{path};
my $BITQC_SCRIPTS_PATH = $BitQC->{node_config}->{executables}->{scripts}->{path};

my $JOB_SCRIPT_NOTIFY   = $BITQC_JOBSCRIPTS_PATH . "notify.pl";
my $JOB_VCF_VARIANT_ANNOTATE 	= $BITQC_JOBSCRIPTS_PATH . "annotate_variants.pl";

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
#$MongoDB::Cursor::timeout = -1; # no timeout
my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();

my $variants_collection = $mongodb->$VARIANTSCOLL;

# hold compassison results
my %result;

# build the query
my $cursor = $variants_collection->find({"b" =>$GENOMBUILD});

# get only fields we need
$cursor->fields({
	"b" => 1,
	"c" => 1,
	"s" => 1,
	"e" => 1,
	"v" => 1,
	"mast" => 1,
	"mist" => 1,
	"mien" => 1,
	"maen" => 1,
	"str" => 1,
	"so" => 1,
	"_id" => 1
});


# make reading form slave nodes OK
#$cursor->slave_okay(1);

my %variantfiles;
my @annotatecommands;

my $i =0;
while (my $record = $cursor->next) {
	print "$i records processed for build $GENOMBUILD\n" unless ($i % 1000);

	# get variables form variant record
	my $genomebuild =	$record->{b};
	my $chromosome =	$record->{c};
	my $ensemblstart =	$record->{s};
	my $ensemblend =	$record->{e};
	my $variant =	$record->{v};
	my $ensemblmax_start =	$record->{mast} ? $record->{mast} : "";
	my $ensemblmin_start =	$record->{mist} ? $record->{mist} : "";
	my $ensemblmin_end =	$record->{mien} ? $record->{mien} : "";
	my $ensemblmax_end =	$record->{maen} ? $record->{maen} : "";
	my $ensemblstrand =	$record->{str};
	my $ensembl_so_term =	$record->{so} ? $record->{so} : "";
	my $variantid =	$record->{_id};

	if (!$variantfiles{$chromosome}){
		#create a temporary file in the working directory to store the variants we cannot find in the database
		my $unknown_variants_file =
			 File::Temp::tempnam( $wd, $chromosome . "_unknown_variants_XXXXX" );
		$unknown_variants_file =~ s/\.//g; # make sure the file name does not contain any dots (region name sometimes does!)
		$unknown_variants_file .= '.txt.gz';

		# create local file object
		my $variantsfile = $BitQC->{fileadapter}->createFile( {
			'compression' => 'gzip',
		    'filetype' => 'txt',
			'file' => $unknown_variants_file,
		    'type' => 'local'
		});
		$variantfiles{$chromosome} = $variantsfile->getWritePointer();	

		# create a annotation job for this chromosome
		push (@annotatecommands, "$JOB_VCF_VARIANT_ANNOTATE --unknownvcf $unknown_variants_file ");
	}

	# add the variant information to the unknown variants file
	print {$variantfiles{$chromosome}} 
		"$genomebuild\t$chromosome\t$ensemblstart\t$ensemblend\t$variant\t"
		."$ensemblmax_start\t$ensemblmin_start\t$ensemblmin_end\t$ensemblmax_end\t$ensemblstrand\t$ensembl_so_term\t"
		."$variantid\n";
	$i++;
}

$BitQC->createPBSJob(
	cmd 		=> \@annotatecommands,
	name 		=> 'variant_annotate', 
	job_opts 	=> {cput  => '86400'}
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
print $notify_fh "<p>Dear_user,<p>The annotation of the variants for genome $GENOMBUILD has successfully completed.<BR>The job id of your job was ".$BITQC_LOG_ID;
print $notify_fh $notify_message->end_html();

my $finish_fh;
my $finish_filename;
( $finish_fh, $finish_filename ) =
 	tempfile( "finish_messageXXXXXX", DIR => $wd, SUFFIX => '.txt' );
print $finish_fh "The variant annotation is complete";

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
$BitQC->finish_log( message => "Variant annotation jobs submitted succesfully" );

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