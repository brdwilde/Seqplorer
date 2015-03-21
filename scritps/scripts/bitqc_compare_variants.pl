#!/usr/bin/perl -w
use strict;
use warnings;
use BitQC;

######################################################################################
#CREATE A BitQC OBJECT AND START LOGGING
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'variantscol' => { default => 'variants',     type     => "string" },
		'samplescol'  => { default => 'samples',      type     => "string" },
		'refsampleid'    => { type    => "string"},
		'refbam'    => { type    => "string",       required => 1 },
		'compsampleid'    => { type    => "string" },
		'compbam'    => { type    => "string",       required => 1 },
		'interval' => { type => "integer", default => 1000000000 },
		'multitest' => { type => "string", default => 'BH'}
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

my $REFSAMPLEID       = $BitQC->getRunConfig('refsampleid');
my $REFBAM 		      = $BitQC->getRunConfig('refbam');
my $COMPSAMPLEID      = $BitQC->getRunConfig('compsampleid');
my $COMPBAM       	  = $BitQC->getRunConfig('compbam');

#Job scripts
my $BITQC_JOBSCRIPTS_PATH =
  $BitQC->{node_config}->{executables}->{jobscripts}->{path};

my $JOB_COMPARE = $BITQC_JOBSCRIPTS_PATH . "compare_getdata.pl";
my $JOB_COMPARE_STORE = $BITQC_JOBSCRIPTS_PATH . "compare_storedata.pl";

#Get index for given organismbuild
my $SAMTOOLS_INDEX = $BitQC->getGenomeIndex('samtools');

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

# sampleid's can be specified command line, but also in the bam files hash
# if they are in the bam hash, we update the database config
if (!$REFSAMPLEID && ref($REFBAM) eq 'HASH'){
	$REFSAMPLEID = ($REFBAM->{'sampleid'});
	$BitQC->setRunConfig('refsampleid', $REFSAMPLEID);
}
if (!$COMPSAMPLEID && ref($COMPBAM) eq 'HASH'){
	$COMPSAMPLEID = ($COMPBAM->{'sampleid'});
	$BitQC->setRunConfig('compsampleid', $COMPSAMPLEID);
}

######################################################################################
# PREPARE
######################################################################################

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

######################################################################################
# CREATE A MESSAGE TO NOTIFY THE USER ON SUCCESS OR WHEN SOMETHING GOES WRONG
######################################################################################

# parallelize by chromosome
my @chromosomes = `awk '{ print \$1 }' $SAMTOOLS_INDEX.fai`;


# jobs and temp files
my @comparecommands;

my $storecommand = $JOB_COMPARE_STORE;

foreach my $chr (@chromosomes){
	chop($chr);

	my $chrfilename = $chr;
	$chrfilename =~ s/\.//;
	my $pvalfile = $BitQC->{fileadapter}->createFile({path => $wd, name => 'pvalfile_'.$chrfilename, ext => '.txt', type => 'local'});
	my $pvalfilepath = $pvalfile->getInfo('file');
	
	my $comparecommand = $JOB_COMPARE;
	$comparecommand .= " --chromosome ".$chr;
	$comparecommand .= " --pval_outfile ".$pvalfilepath;

	push (@comparecommands, $comparecommand);

	$storecommand .= ' --pvalfiles '.$pvalfilepath;
}

$BitQC->createPBSJob(
	cmd 		=> \@comparecommands,
	name 		=> 'compare_getdata',
	job_opts 	=> {
		cput   => '72000'
	}
);

$BitQC->createPBSJob(
	cmd 		=> $storecommand,
	name 		=> 'compare_storedata',
	job_opts 	=> {
		cput   => '72000'
	}
);

$BitQC->submitPBSJobs();

__END__

=head1 NAME

bitqc_rename_remove_sample.pl - A script to renmae or remove a sample in the database

=head1 SYNOPSIS

bitqc_rename_remove_sample.pl [options]

Use -? to see options

=head1 OPTIONS

=over 8

=item B<-h -? --help>			Print a brief help message and exit.

=item B<-m --man>				Display the manual page.

=item B<-v --verbose>			Print more verbose information when running. Mostly for debug purposes. [false]

=item B<--variantscol>			The mongodb collection containing the variants records [variants]

=item B<--samplescol>			The mongodb collection containing the samples records [samples]

=item B<--sampleid>				the database id for the sample to renmae or delete

=item B<--samplename>			The new name for the sample

=item B<--del>					set if you want to remove the sample, no sample name can be set to make this option work! [false]

=item B<--email_to>				A list of valid email addresses, specify multiple times for multiple emails to be sent. An email will be sent to all adresses specified on success or failure.

=item B<--email_from>			The email address sending the notification emails.

=item B<--config_id>			The mongodb script config id to use in this analysis.

=item B<--server_id>			The mongodb server id to perform the analysis with.

=item B<--bitqc_host>			host to running the BitQC database. [localhost]

=item B<--bitqc_port>   		port the BitQC database is running on. [27017]

=item B<--bitqc_db>     		The BitQC database name used. [bitqc]

=item B<--log_coll>		The BitQC logging collection. [log]

=item B<--server_coll>	The BitQC server collection. [servers]

=item B<--config_coll>	The BitQC config collection. [config]

=item B<--genome_coll>	The BitQC genomes collection. [genome]

=item B<--db_config>			whether to use the BitQC database for storing the run config. [true]

=item B<--startlog>				whether to use the BitQC logging in the database, if false logging will be printed to STDOUT. [true]

=back
=head1 DESCRIPTION

B<BitQC rename remove sample> will rename or remove a sample in the mongo database.

=cut
