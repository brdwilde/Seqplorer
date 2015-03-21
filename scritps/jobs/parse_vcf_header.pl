#!/usr/bin/perl -w
use strict;
use warnings;
use BitQC;
use MongoDB::OID;

######################################################################################
# INITIALISE BITQC MODULE
######################################################################################

# Make BitQC object
# settings will come from environment variables
my $BitQC = new BitQC();

# Load bitqc configuration from the given database
$BitQC->load(
	'script_args' => {
		'db_config'   	=> { default => boolean::false, type => 'bool' }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my @VCF 				= @{$BitQC->getRunConfig('vcf')};
my %SAMPLES;
%SAMPLES  = %{$BitQC->getRunConfig('samples')} if $BitQC->getRunConfig('samples');
my $SAMPLESCOLL       = $BitQC->getRunConfig('samplescol');
my $VCFHEADERCOLL     	= $BitQC->getRunConfig('vcfheadercol');
my $PROJECTID  		= $BitQC->getRunConfig('projectid');
my $PROJECTCOL 		= $BitQC->getRunConfig('projectcol');
my $GENOMEBUILD 		= $BitQC->getRunConfig('genomebuild');

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
# PARSE THE VCF FILES
######################################################################################

# get the bam input files
my @files = $BitQC->{fileadapter}->getLocal(\@VCF,'vcf');

my $fileindex = 0;
foreach my $file (@files){

	my %vcfhash = $file->getFileInfo();

	#get the name of the file
	my $vcfname = $file->getInfo('name');
	my $vcffile = $file->getInfo('file');
	my $vcfext = $file->getInfo('ext');

	######################################################################################
	# GET THE SAMPLE NAMES AND HEADER INFO FROM THE VCF FILE
	######################################################################################

	# open a file pointer to the vcf file
	my $vcfpointer = $file->getReadPointer();

	# get the header lines and the samples in the vcf file
	my @header;
	my @samplenames;
	while (<$vcfpointer>) {    #Loop through lines
		chomp;
		if (/^##/) {
			push( @header, $_ );    # this is a header line
		}
		elsif (/^#CHROM/) {         # variant header line
			@samplenames =
				 split( /\t/, $_ );    # get the sample names in the vcf file
			splice( @samplenames, 0, 9 );
			# first 9 items are vcf specific, rest are sample names
		}
		else {
			last;
		}
	}
	close $vcfpointer;

	#############################################
	# PROCESS THE HEADER, INTEGRATE IT WITH THE DATABASE CONTENT
	#############################################

	# create hash of header values
	my %header;
	foreach my $headerline (@header) {
		# parse the vcf header value
		# first match will be the header key, second the header value
		$headerline =~ /^##(.+)=<(.+)>$/;
		if ($2) {
			# split by all commas exept the ones followed by quoted text
			my %val;
			my $key   = $1;
			my $field = $2;
			while ( $field =~ s/([\w]+)=([\w\s]+|".+"|\.),?// ) {
				my $key = $1;
				my $val = $2;
				$val =~ s/^"//;    # remove trailing an leading quotes
				$val =~ s/"$//;
				$val{ lc($key) } = $val;
			}
			push( @{ $header{ uc($key) } }, \%val );
		}
	}

	# Insert the info fields of the header into the database
	my $mongodb = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
	my $vcfheader_collection = $mongodb->$VCFHEADERCOLL;

	# get the info fields
	my $info = $BitQC->{DatabaseAdapter}->findEntryById(
		collection => $VCFHEADERCOLL,
		id         => "INFO"
	);

	# turn into hash
	my %dbinfo;
	for my $info ( @{ $info->{'values'} } ) {
		$dbinfo{ $info->{'id'} } = boolean::true;
	}

	# add header info fields of this vcf file that do not exist yet
	foreach my $value ( @{ $header{'INFO'} } ) {
		$vcfheader_collection->update(
			{ '_id'       => 'INFO' },
			{ '$addToSet' => { 'values' => $value } },
			{ 'upsert'    => 1 }
			 )
			 unless ( $dbinfo{ $value->{id} } );
	}

	# Insert the format fields of the header into the database
	# get the format fields first
	my $format = $BitQC->{DatabaseAdapter}->findEntryById(
		collection => $VCFHEADERCOLL,
		id         => "FORMAT"
	);

	# turn into hash
	my %dbformat;
	for my $format ( @{ $format->{'values'} } ) {
		$dbformat{ $format->{'id'} } = boolean::true;
	}

	# add header format fields of this vcf file that do not exist yet
	foreach my $value ( @{ $header{'FORMAT'} } ) {
		$vcfheader_collection->update(
			{ '_id'       => 'FORMAT' },
			{ '$addToSet' => { 'values' => $value } },
			{ 'upsert'    => 1 }
		) unless ( $dbformat{ $value->{id} } );
	}

	#############################
	# PROCESS THE SAMPLES
	#############################

	if ( !@samplenames ) {
	# there is no sample information in this vcf file, we get the sample name from the config or the file name
		if (%SAMPLES) {
			foreach my $sample (keys %SAMPLES) {
				push( @samplenames, $sample );
			}
		}
		else {
			push( @samplenames, $vcfname );
		}
	}

	my $sample_collection = $mongodb->$SAMPLESCOLL;

	my @vcfsamples;

	foreach my $sample (@samplenames) {
		# look for this sample in the database
		my $sample_id;
		# if samples are configured in the config we try to use their ID
		if ($SAMPLES{$sample}) {
			$sample_id = $SAMPLES{$sample};

			$BitQC->{DatabaseAdapter}->addtoSet(
				collection => $SAMPLESCOLL, 
				id => MongoDB::OID->new( value => $sample_id),
				array => 'files',
				element => \%vcfhash
			);
		} else {
			my $sample_obj = $BitQC->{DatabaseAdapter}->insertEntry(
				collection => $SAMPLESCOLL,
				fields     => {
					'name'    => $sample,
					'project' => [
						{
							'id' =>
								 MongoDB::OID->new( value => $PROJECTID ),
							'name' => $project->{name}
						}
					],
					'genome' => $GENOMEBUILD,
					'files' => [ \%vcfhash ]
				},
				save_mode => 1
			);
			$sample_id = $sample_obj->to_string;
			$SAMPLES{$sample} = $sample_id;
		}

		# update the configuration so the jobs can access the sample id's
		if(exists $BitQC->{run_config}->{samples} && ref($BitQC->{run_config}->{samples}) ne 'HASH'){
			$BitQC->{run_config}->{samples}={};
		}
		$BitQC->{run_config}->{samples}->{$sample} = $sample_id;

		# create a sample hash containing the name and the id of the sample
		my %sample = (
			name => $sample,
			id => $sample_id
		);
		# add the %sample hash to an array, this array will thus contain a hash 
		# for each sample occuring in the vcf file, in the same order of occurence
		push( @vcfsamples, \%sample );
	}



	# add the hash of sample name and id pairs to the configuration
	$vcfhash{samples} = \@vcfsamples;
	
	$BitQC->{run_config}->{vcf}[$fileindex] = \%vcfhash;

	$fileindex++;
}

# update the database configuration
$BitQC->replaceRunConfig();

#print Dumper ($BitQC->{run_config});

# finish logging
$BitQC->finish_log(
	message => "VCF files parsed." );
