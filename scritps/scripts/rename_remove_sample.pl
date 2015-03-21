#!/usr/bin/perl -w

=head1 LICENSE

  No licence yet?

=head1 CONTACT

  Please email comments or questions to the 
  developer at <gbramdewilde@gmail.com>.

=cut

=head1 NAME

rename_remove_sample.pl - A script to rename or remove a sample in the database

=head1 SYNOPSIS

rename_remove_sample.pl [options]

Use --help to see options, --man to see extended manual

by Bram de Wilde (gbramdewilde@gmail.com)

=head1 DESCRIPTION

B<rename_remove_sample> a script to rename or remove a sample from the mongo database.

=cut

use strict;
use warnings;
use BitQC;
use MongoDB::OID;
use Data::Dumper::Simple;

######################################################################################
#CREATE A BiTQC OBJECT AND START LOGGING
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		'variantscol' => { default => 'variants',     type     => "string" },
		'samplescol'  => { default => 'samples',      type     => "string" },
		'sampleid'    => { type    => "string",       required => 1 },
		'samplename'  => { type    => "string" },
		'sample'      => { default => boolean::true, type => 'boolean' },
		'del'         => { default => boolean::false, type     => 'boolean' }
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Log variables
my $BITQC_LOG_ID = $BitQC->{log_id};

#Other variables
my $SAMPLEID          = $BitQC->getRunConfig('sampleid');
my $SAMPLESCOLL       = $BitQC->getRunConfig('samplescol');
my $VARIANTSCOLL      = $BitQC->getRunConfig('variantscol');
my $SAMPLENAME        = $BitQC->getRunConfig('samplename');
my $SAMPLE            = $BitQC->getRunConfig('sample');
my $DELETE            = $BitQC->getRunConfig('del');
my $SUBJECT           = "Job " . $BITQC_LOG_ID;
my $MESSAGE           = "Content-Type: text/html; charset=ISO-8859-1";
# emails
my $TO_EMAIL   = $BitQC->getRunConfig('email_to');
my $FROM_EMAIL = $BitQC->getRunConfig('email_from');

# create and change to working dir
my $wd = $BitQC->workingDir();


######################################################################################
# CREATE A MESSAGE TO NOTIFY THE USER ON SUCCESS OR WHEN SOMETHING GOES WRONG
######################################################################################

# get the database connection and the collections we will be working on
my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
my $sample_collection   = $mongodb->$SAMPLESCOLL;
my $variants_collection = $mongodb->$VARIANTSCOLL;
my $sample              = $BitQC->{DatabaseAdapter}->findEntryById(
	collection => $SAMPLESCOLL,
	id         => MongoDB::OID->new( value => $SAMPLEID )
);

# get the current name of the sample
my $oldname = $sample->{name};

# set the error message to return to the user
my $messagecontent =
"<p>Dear user,<p>We where unable to rename or remove sample $oldname.<BR>The log id of the job was "
  . $BITQC_LOG_ID
  . "<BR>Please review the run log or contact the system administrators for more information.";

if ($SAMPLENAME) {

	$BitQC->log_message( message => "Renaming sample $oldname" );

	# RENAME THE SAMPLE IN THE SAMPLES COLLECTION
	$sample_collection->update(
		{ "_id"      => MongoDB::OID->new( value => $SAMPLEID ) },
		{ '$set'     => { "name"                 => $SAMPLENAME } },
		{ 'multiple' => 1 }
	);

	$BitQC->log_message( message => "Renaming sample in variants collection" );

	# UPDATE THE NAME OF THE SAMPLE IN THE VARIANTS COLLECTION
	my $variants_collection = $mongodb->$VARIANTSCOLL;
	$variants_collection->update(
		{ "sa.id"    => MongoDB::OID->new( value => $SAMPLEID ) },
		{ '$set'     => { 'sa.$.sn'              => $SAMPLENAME } },
		{ 'multiple' => 1 }
	);

	$BitQC->log_message( message => "Renaming files associated with the sample" );

	# RENAME THE FILES
	my @newfiles;
	foreach my $file ( @{ $sample->{files} } ) {

		# TODO replace by BitQCFile function?
		# TODO: depending on the file type, replace the information inside to match the new name
		$file->{name} =~ s/$oldname/$SAMPLENAME/;
		push( @newfiles, $file );
	}

	$sample_collection->update(
		{ "_id"      => MongoDB::OID->new( value => $SAMPLEID ) },
		{ '$set'     => { "files"                => \@newfiles } },
		{ 'multiple' => 1 }
	);

	# update the message to contain a success message
	$messagecontent =
"<p>Dear user,<p>Sample $oldname has succesfully been renamed to $SAMPLENAME.<BR>The log id of the job was "
	  . $BITQC_LOG_ID;

}
elsif ($DELETE) {
	if ($SAMPLE) {

		$BitQC->log_message( message => "Removing files associated with the sample" );

		foreach my $file ( @{ $sample->{files} } ) {

			# TODO replace by BitQCFile function
			# delete file
		}

		$BitQC->log_message( message => "Removing sample $oldname" );

		$sample_collection->remove(
			{ "_id" => MongoDB::OID->new( value => $SAMPLEID ) } );
	}

	$BitQC->log_message( message => "Disassociate sample from variants" );

	$variants_collection->update(
		{ "sa.id" => MongoDB::OID->new( value => $SAMPLEID ) },
		{ '$pull' => { 'sa' => {'id' => MongoDB::OID->new( value => $SAMPLEID )} } },
		{ 'multiple' => 1 }
	);

	$messagecontent =
"<p>Dear user,<p>Sample $oldname has succesfully been removed.<BR>The log id of the job was "
	  . $BITQC_LOG_ID;

}

######################################################################################
# SEND THE MAIL
######################################################################################

$MESSAGE .= $messagecontent;

foreach my $to_email ( @{$TO_EMAIL} ) {
	$BitQC->sendEmail(
		to      => $to_email,
		from    => $FROM_EMAIL,
		subject => $SUBJECT,
		message => $MESSAGE
	);

	$BitQC->log_message( message => "Notification sent to $to_email" );
}

$BitQC->finish_log( message => "Sample renamed or removed" );

__END__

=head1 OPTIONS

The options for this script are devided in 2 sections. The first section are script specific options, the
next section contains BitQC options for logging and configuration.

=head3 Map reads options:

=over 8

=item B<--sampleid>				

the database id for the sample to renmae or delete

=item B<--samplename>			

The new name for the sample

=item B<--del>					

set if you want to remove the sample, setting tha sample name option will cancel this option [false]

=item B<--sample>

set to false to keep the sample record and files in the database, only the variant association will be removed [true]

=item B<--email_to>				

A list of valid email addresses, specify multiple times for multiple emails to be sent. An email will be sent to all adresses specified on success or failure.

=item B<--email_from>			

The email address sending the notification emails.

=item B<--variantscol>			

The mongodb collection containing the variants records [variants]

=item B<--samplescol>			

The mongodb collection containing the samples records [samples]

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

=item B<--log_coll>

The BitQC logging collection. [log]

=item B<--server_coll>

The BitQC server collection. [servers]

=item B<--config_coll>

The BitQC config collection. [config]

=item B<--db_config>

whether to use the BitQC database for storing the run config. [true]

=item B<--startlog>

Whether to use the BitQC logging in the	database, if false logging will be printed to 
STDOUT. [true]

=back

=cut
