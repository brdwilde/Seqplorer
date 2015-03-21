#!/usr/bin/perl -w

=head1 LICENSE

  No licence yet?

=head1 CONTACT

  Please email comments or questions to the 
  developer at <gbramdewilde@gmail.com>.

=cut

=head1 NAME

Bitqc Gene Coverage Generator - A script to generate coverage statistics for a list of genes or target regions

=head1 SYNOPSIS

bitqc_gene_coverage_generator.pl [options]

Use --help to see options, --man to see extended manual

by Bram de Wilde (gbramdewilde@gmail.com)

=head1 DESCRIPTION

B<bitqc_gene_coverage_generator> a script to generate coverage statistics for one or more genes or target regions.

=cut

use strict;
use warnings;
use Parallel::ForkManager;
use BitQC;
use JSON;
use CGI;
use File::Temp qw/ tempfile tempdir /;

######################################################################################
#CREATE A BiTQC OBJECT AND PREPARE THE ANALYSIS SERVER
######################################################################################
my $BitQC = new BitQC();

$BitQC->load(
	'script_args' => {
		#db_config needs to be enabled or stats are not saved to database
		'db_config' 	=> { type => "boolean", default => boolean::true },
		'gene' 				=> { type => "string", short => "g", array => 1 },
		'regions' 			=> { type => "string", short => "r" },
		'export'  			=> { required => 1, type => "string", short => "e" },
		'threshold' 		=> { type => "int", short => "t" },
		'remove_overlap' 	=> { type => "boolean", default => boolean::true },
		'bam'				=> { required => 1, type => "string", array => 1, short => "b" },
		'genomebuild'		=> { required => 1, type => "string" },
#		'max_procs' 		=> { type => "int", default => 1},
		'bininterval'		=> { type => "int", default => 10},
		'codingonly'		=> { type => "boolean"},
		'meannormalize'		=> { type => "boolean"},
		'normalizeto'		=> { type => "int"},
#		'offtarget'			=> { type => "boolean"},
		'readstats'			=> { type => "boolean"},
		'rawdata'			=> { type => "boolean"},
		'cannonical'		=> { type => "boolean"},
		'allgenes'			=> { type => "boolean"},
		'xreftype'			=> { type => "string"},
		'sampleids'			=> { type => "string", array =>1},
		'plotscoll'			=> { type => "string", default => "plots"}
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Supported export formats
my %EXPORT_FORMATS=();
$EXPORT_FORMATS{pdf}= "pdf";
$EXPORT_FORMATS{json}= "json";
$EXPORT_FORMATS{html}= "html";
$EXPORT_FORMATS{mongodb}= "mongodb";
$EXPORT_FORMATS{txt}= "txt";

#Standard constants

my @BAM;
@BAM 				= @{$BitQC->getRunConfig('bam')};
my @GENE;
my $GENEREF 		= $BitQC->getRunConfig('gene');
if (ref($GENEREF) eq 'ARRAY'){
	@GENE = @{$BitQC->getRunConfig('gene')} ;	
} else {
	push (@GENE,$GENEREF);
}
my $REGIONS      	= $BitQC->getRunConfig('regions');
my $VARIANTSCOLL 	= $BitQC->getRunConfig('variantscol');
my $EXPORT			= lc($BitQC->getRunConfig('export'));
my $MIN_COVERAGE 	= $BitQC->getRunConfig('minimum_coverage');
my $COVERAGE_DEPTH 	= $BitQC->getRunConfig('coverage_depth');
my $REMOVE_OVERLAP 	= $BitQC->getRunConfig('remove_overlap');
my $MAX_PROCESSES	= $BitQC->{node_config}->{system}->{mappingcores};
my $BININTERVAL		= $BitQC->getRunConfig('bininterval');
my $CODINGONLY 		= $BitQC->getRunConfig('codingonly');
my $NORMALIZE		= $BitQC->getRunConfig('normalizeto');
#my $OFFTARGET		= $BitQC->getRunConfig('offtarget');
my $READSTATS 		= $BitQC->getRunConfig('readstats');
my $RAWDATA 		= $BitQC->getRunConfig('rawdata');
my $CANNONICAL 		= $BitQC->getRunConfig('cannonical');
my $ALLGENES 		= $BitQC->getRunConfig('allgenes');
my $XREFS 			= $BitQC->getRunConfig('xreftype');
my $SAMPLEIDS		= $BitQC->getRunConfig('sampleids');
my $BITQC_LOG_ID = $BitQC->{log_id};

# Ensembl variables
my $ENSEMBL_REGISTRY = $BitQC->getCommand('ensemblAPI');
my $ENSEMBL_HOST = $BitQC->{node_config}->{executables}->{ensemblAPI}->{host};
my $ENSEMBL_USER = $BitQC->{node_config}->{executables}->{ensemblAPI}->{user};
my $ENSEMBL_PASS = $BitQC->{node_config}->{executables}->{ensemblAPI}->{pass};
my $ENSEMBL_PORT = $BitQC->{node_config}->{executables}->{ensemblAPI}->{port};

#Genomeinformation
my $ENSEMBL_ORGANISM = $BitQC->{genome}->{organism}->{ensemblname};
my $SAMTOOLS_INDEX = $BitQC->getGenomeIndex('samtools');

# executables
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');


#Job scripts
my $BITQC_JOBSCRIPTS_PATH = $BitQC->{node_config}->{executables}->{jobscripts}->{path};

my $JOB_COVERAGE_GETDATA = $BITQC_JOBSCRIPTS_PATH . "coverage_getdata.pl";
my $JOB_COVERAGE_MERGEDATA = $BITQC_JOBSCRIPTS_PATH . "coverage_mergedata.pl";
my $JOB_SCRIPT_NOTIFY   = $BITQC_JOBSCRIPTS_PATH . "notify.pl";

###########################################################################
# EXTRA CHECKS FOR ARGUMENTS
###########################################################################

#Export check
if(!$EXPORT_FORMATS{$EXPORT}){
	$BitQC->log_error(
		message => "export as $EXPORT option is not supported."
	);
}

###########################################################################
# Change to ths working directory
###########################################################################

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

###########################################################################
# CHECK IF SAMPLE ID INFO IS INCLUDED IN THE BAM FILES HASH
###########################################################################

# sampleid's can be specified command line, but also in the bam files hash
if (!$SAMPLEIDS){
	foreach my $bam (@BAM){
		if (ref($bam) eq 'HASH'){
			push (@{$SAMPLEIDS}, $bam->{'sampleid'}) if ($bam->{'sampleid'});
		}
	}	
	$BitQC->setRunConfig('sampleids', $SAMPLEIDS);
}

###########################################################################
# DETERMINE THE BAMFILE(S)
###########################################################################

my @bamfiles = $BitQC->{fileadapter}->getLocal(\@BAM,'bam');
my @bamconfig;
foreach(@bamfiles){
	my %filehash = $_->getFileInfo();
	push (@bamconfig,\%filehash);
}
$BitQC->setRunConfig('bam', \@bamconfig);

###########################################################################
# DETERMENING THE REGIONS
###########################################################################

my %regions;
my $usermessage;
my $genename;
my $end = "-";
my $start = "-";
my $length = 0;
my $counter=0;

# get the regions we want to get coverage for
if ( $REGIONS ){
	# user specified a regions file, we read it
	my $regionfile = $BitQC->{fileadapter}->getLocalFile($REGIONS);
	my $regionpointer = $regionfile->getReadPointer();
	my $genename = $regionfile->getInfo('name');
	while (<$regionpointer>) {
		# we assume bed format
		chomp;
		next if ($_ =~/^#/); # skip comment lines
		my @a = split(/\t/);

		# split by region
		unless (!$a[0] || !$a[1] || !$a[2] || !$a[3]) {
			# this is a valid bed line
			$regions{$a[0]}{$a[1]}{$a[2]} = $a[3];
			$length	+= $a[2] - $a[1];
			$counter++;
		};
	}
} elsif (@GENE && $GENE[0]) {
	# user specified one or more genes
	foreach my $gene (@GENE) {
		if ($gene =~ /^(\w+):([0-9]+)-([0-9]+)$/){
			# not a gene, but a target interval
			my $chrom = $1;
			$start 	= $2-1; # bed file uses 0 based coördinate
			$end 	= $3;
			$length	+= $end - $start;

			$regions{$chrom}{$start}{$end} = $gene;
			$counter++;
			$genename = $gene;
		} else {
			# get coördinates form ensembl

			#Connect to ensembl registry
			$ENSEMBL_REGISTRY->load_registry_from_db(
				-host    => $ENSEMBL_HOST,
				-user    => $ENSEMBL_USER,
				-pass    => $ENSEMBL_PASS,
				-port    => $ENSEMBL_PORT,
				-verobose => 1
			);
			
			$ENSEMBL_REGISTRY->set_reconnect_when_lost();
			
			#Make adaptors
			my $gene_adaptor = $ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'Gene' );

			my $ensemblgene;
			if($gene =~ /^ENSG[0-9]+$/){
				# gene name is in ensembl format
				$ensemblgene = $gene_adaptor->fetch_by_stable_id($gene);
				if(!defined($ensemblgene)){
					$usermessage = "Gene $gene cannot be found in the ensembl database";
				}
				$genename .= $gene."_";
			}else{
				# non ensembl format genen name
				my @genes = @{ $gene_adaptor->fetch_all_by_external_name($gene) };

				#Show all possible genes
				if(scalar(@genes) > 1){
					$usermessage = "Multiple genes found with name $gene. Please select one: ";

					foreach my $g (@genes){
						$usermessage .= $g->stable_id().", ";
					}
				}
				elsif(scalar(@genes) == 1){
					$ensemblgene = $genes[0];
					$genename .= $gene."_";
				}else{
					$usermessage = "Gene $gene cannot be found in the ensembl database";
				}
			}
			$BitQC->log_message( message =>  $usermessage) if ($usermessage);
			
			#Get gene information
			if ($ensemblgene){
				$end 	= $ensemblgene->end();
				$start 	= $ensemblgene->start();
				my $chrom = $ensemblgene->slice->seq_region_name();
				$length	+= $end - $start;
				my $gene_id	= $ensemblgene->stable_id();

				#Fetch all transcripts of the gene
				if ($CODINGONLY || $CANNONICAL){
					# fetch all transcripts and add exon coding start and stop for each transcript
					my @transcripts = @{ $ensemblgene->get_all_Transcripts };
					foreach my $transcript (@transcripts){
						my @exons_array;
						if ($CODINGONLY){
							# get coding exons if we did not ask for cannonical only transcript
							# and if we did ask for cannonical only transcript and this transcript is cannonical
							@exons_array = @{ $transcript->get_all_translateable_Exons()} if (!$CANNONICAL || ($CANNONICAL && $transcript->is_canonical()));
						} else {
							# get all exons if we did not ask for cannonical only transcript
							# and if we did ask for cannonical only transcript and this transcript is cannonical
							@exons_array = @{ $transcript->get_all_Exons()} if (!$CANNONICAL || ($CANNONICAL && $transcript->is_canonical()));
						}
						my $exonslength = 0;
						foreach my $exon (@exons_array){
							my $exon_name	= $exon->display_id();
							my $exon_strand	= $exon->strand();
							my $exon_start;
							my $exon_end;
							if ($CODINGONLY){
								$exon_start = $exon->coding_region_start($transcript) - 1; #make 0 based coördinate
								$exon_end = $exon->coding_region_end($transcript);
							} else {
								$exon_start = $exon->start()- 1; #make 0 based coördinate
								$exon_end = $exon->end();
							}
							$exonslength += $exon_end - $exon_start ;
							$regions{$chrom}{$exon_start}{$exon_end} = $exon_name if ($exon_start && $exon_end);
							$length	+= $exon_end - $exon_start;
							$counter++;
						}
						print "$gene_id\t".@exons_array."\t$exonslength\n" if (@exons_array);
					}
				} else {
					my @exons_array = @{ $ensemblgene->get_all_Exons };
					foreach my $exon (@exons_array){
						my $exon_name	= $exon->display_id();
						my $exon_strand	= $exon->strand();			

						#Fetch exon information
						my $exon_start	= $exon->start()- 1; #make 0 based coördinate
						my $exon_end	= $exon->end();
						$regions{$chrom}{$exon_start}{$exon_end} = $exon_name;
						$length	+= $exon_end - $exon_start;
						$counter++;
					}
				}
			}		
		}
	}
} elsif ($ALLGENES){
	$genename .= "All_";
	$genename .= "cannonical_" if ($CANNONICAL);
	$genename .= "coding_" if ($CODINGONLY);
	$genename .= "ensembl_transcripts";
	$genename .= "_from_".$XREFS;

	#Connect to ensembl registry
	$ENSEMBL_REGISTRY->load_registry_from_db(
		-host    => $ENSEMBL_HOST,
		-user    => $ENSEMBL_USER,
		-pass    => $ENSEMBL_PASS,
		-port    => $ENSEMBL_PORT,
		-verobose => 1
	);
	
	$ENSEMBL_REGISTRY->set_reconnect_when_lost();
	
	#Make adaptors
	my $slice_adaptor = $ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'Slice' );
	my $gene_adaptor = $ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'Gene' );


	my @slices = @{ $slice_adaptor->fetch_all('chromosome') };

	foreach my $slice (@slices){
		my $genes = $slice->get_all_Genes();
		while ( my $ensemblgene = shift @{$genes} ){
			$end 	= $ensemblgene->end();
			$start 	= $ensemblgene->start();
			my $chrom = $ensemblgene->slice->seq_region_name();
			$length	+= $end - $start;
			my $gene_id	= $ensemblgene->stable_id();

			#Fetch all transcripts of the gene
			if ($CODINGONLY || $CANNONICAL){
				# fetch all transcripts and add exon coding start and stop for each transcript
				my @transcripts = @{ $ensemblgene->get_all_Transcripts };
				foreach my $transcript (@transcripts){

					my $hasxref = 1;
					if ($XREFS) {
               			$hasxref = @{$transcript->get_all_xrefs($XREFS) } ? 1 : 0;
					}

					if ($hasxref){
						my @exons_array;
						if ($CODINGONLY){
							# get coding exons if we did not ask for cannonical only transcript
							# and if we did ask for cannonical only transcript and this transcript is cannonical
							@exons_array = @{ $transcript->get_all_translateable_Exons()} if (!$CANNONICAL || ($CANNONICAL && $transcript->is_canonical()));
						} else {
							# get all exons if we did not ask for cannonical only transcript
							# and if we did ask for cannonical only transcript and this transcript is cannonical
							@exons_array = @{ $transcript->get_all_Exons()} if (!$CANNONICAL || ($CANNONICAL && $transcript->is_canonical()));
						}
						foreach my $exon (@exons_array){
							my $exon_name	= $exon->display_id();
							my $exon_strand	= $exon->strand();
							my $exon_start;
							my $exon_end;
							if ($CODINGONLY){
								$exon_start = $exon->coding_region_start($transcript)- 1; #make 0 based coördinate
								$exon_end = $exon->coding_region_end($transcript);
							} else {
								$exon_start = $exon->start()- 1; #make 0 based coördinate
								$exon_end = $exon->end();
							}
							$regions{$chrom}{$exon_start}{$exon_end} = $exon_name if ($exon_start && $exon_end);
							$length	+= $exon_end - $exon_start;
							$counter++;
						}
					}
				}
			} else {

				my $hasxref = 1;
				if ($XREFS) {
         			$hasxref = @{ $ensemblgene->get_all_xrefs($XREFS) } ? 1 : 0;
				}
				
				my @exons_array;
				@exons_array = @{ $ensemblgene->get_all_Exons } if ($hasxref);
				foreach my $exon (@exons_array){
					my $exon_name	= $exon->display_id();
					my $exon_strand	= $exon->strand();			

					#Fetch exon information
					my $exon_start	= $exon->start() - 1; #make 0 based coördinate
					my $exon_end	= $exon->end();
					$regions{$chrom}{$exon_start}{$exon_end} = $exon_name;
					$length	+= $exon_end - $exon_start;
					$counter++;
				}
			}
		}

	}
}

# remove trailing _ from gene name
$genename =~ s/_$//g; 

print "Found $counter regions with a total length of $length for $genename\n";

# remove overlap if required
%regions=%{remove_overlap( positions => \%regions)} if ($REMOVE_OVERLAP);

# get the flagstats for the bam files to determine global statistics
my $fork_manager= new Parallel::ForkManager($MAX_PROCESSES);

my @bamfilenames;
my $chromosomes;
my %globalstats;

foreach my $bamfile (@bamfiles){

	my $bamname = $bamfile->getInfo('name');

	push (@bamfilenames, $bamname);

	# TODO: will only work for local files!!! extend to any bitqc file type
	my $filename = $bamfile->getInfo('file');

	$fork_manager->start and next;

	my %bamstats = (
		'stats' => {
			'normalizationfactor' => 1
		}
	);

	if ($READSTATS || $NORMALIZE){
		my @flagstat = `$SAMTOOLS_COMMAND flagstat $filename`;

		# get total quality filter passed reads 
		$flagstat[0] =~ /^([0-9]+)\s+/;
		$bamstats{'stats'}{'totalreads'} = $1;

		$flagstat[1] =~ /^([0-9]+)\s+/;
		$bamstats{'stats'}{'duplicatereads'} = $1;

		$flagstat[2] =~ /^([0-9]+)\s+/;
		$bamstats{'stats'}{'mappedreads'} = $1;

		$bamstats{'stats'}{'coveragereads'} = $bamstats{'stats'}{'mappedreads'}-$bamstats{'stats'}{'duplicatereads'};

		# if ($OFFTARGET){
		# 	$bamstats{'stats'}{'ontargetreads'} = 0;
		# }
	}

	if ($NORMALIZE){
		$bamstats{'stats'}{'normalizedreads'} = $NORMALIZE;
		$bamstats{'stats'}{'normalizationfactor'} = $NORMALIZE/$bamstats{'stats'}{'coveragereads'};
	}

	# save the global stats in the config
	$BitQC->setRunConfig($bamname.'_stats', \%bamstats);

	#End the process
	$fork_manager->finish;
}

#Wait till all processes are finished
$fork_manager->wait_all_children;

$length = 0;
$counter = 0;

# print regions to a file per chromosome and create a job to get the data
my @coverage_getadata_commands;
foreach my $chrom (keys %regions){

	my $filename = $wd."region_".$chrom;
	$filename =~ s/\.//g; # make sure the file name does not contain any dots (region name sometimes does!)
	my $regionfilename = $filename.'.bed';

	$chromosomes .= ' --chromosome '.$chrom;

	# create local file object
	my $regionfile = $BitQC->{fileadapter}->createFile( {
		'filetype' => 'bed',
		'file' => $regionfilename,
		'type' => 'local',
		'ext' => '.bed'
	});

	# create file pointer for writing
	my $regionfilepointer = $regionfile->getWritePointer();

	foreach my $start (sort { $a <=> $b} keys %{$regions{$chrom}}){
		foreach my $end (sort { $a <=> $b} keys %{$regions{$chrom}{$start}}){
			print $regionfilepointer $chrom."\t".$start."\t".$end."\t".$regions{$chrom}{$start}{$end}."\n";
			$length += $end - $start;
			$counter++;
		}
	}


	# create a get data job for this chromosome
	push (@coverage_getadata_commands, "$JOB_COVERAGE_GETDATA --chromosome $chrom --regionfile $regionfilename");
}

$BitQC->createPBSJob(
	cmd 		=> \@coverage_getadata_commands,
	name 		=> 'coverage_getdata',
	job_opts 	=> {
		ppn    => $MAX_PROCESSES,
		cput   => '72000'
	} 
);


$BitQC->createPBSJob(
	cmd 		=> $JOB_COVERAGE_MERGEDATA." --genename ".$genename.$chromosomes,
	name 		=> 'coverage_mergedata',
	job_opts 	=> {
		ppn    => $MAX_PROCESSES,
		cput   => '72000'
	} 
);


########################################################
# NOTIFY
#######################################################

# create a notification message
my $notify_fh;
my $notify_filename;
( $notify_fh, $notify_filename ) = tempfile( "notify_messageXXXXXX", DIR => $wd, SUFFIX => '.html' );
my $message = CGI->new;
print $notify_fh $message->start_html();
print $notify_fh "<p>Dear_user,<p>Coverage statistics for $genename where successfully calculated.";
print $notify_fh "<p>Coverage was calculated for $counter regions with a total length of $length basepairs.";
print $notify_fh $message->end_html();

my $finish_fh;
my $finish_filename;
( $finish_fh, $finish_filename ) = tempfile( "finish_messageXXXXXX", DIR => $wd, SUFFIX => '.txt' );
print $finish_fh "Coverage statistics calculated successfully for $genename.";
print $finish_fh "Coverage was calculated for $counter regions with a total length of $length basepairs.";

# create job to notify user if all went well
my $notifycommand = $JOB_SCRIPT_NOTIFY;
$notifycommand .= " --subject Job_$BITQC_LOG_ID --message $notify_filename --finish_master --finish_master_message $finish_filename";

$BitQC->createPBSJob(
	cmd 		=> $notifycommand,
	name 		=> 'notify',
	job_opts 	=> {
		cput   => '30',
#			nodes  => $BITQC_PBS_SERVER # enable this if jobs cannot submit other jobs from the pbs nodes
	} 
);

$BitQC->submitPBSJobs();
	
# my %positions;
# $positions{ $chromosome }{ $start }{ $stop } = $name;
# use: my %regions=%{remove_overlap( positions => \%positions)};
sub remove_overlap {

	my %args = @_;

	my %positions = %{ $args{positions} };

	# hash to return:
	my %regions;

	# concatenate the regions and remove the overlap
	for my $chr ( keys %positions ) {
		my %stretch;
		for my $start ( sort { $a <=> $b } keys %{ $positions{$chr} } ) {
			for my $stop ( sort { $a <=> $b } keys %{ $positions{$chr}{$start} }) {
				if ( !%stretch ) {

					# start a new stretch
					$stretch{chr}   = $chr;
					$stretch{start} = $start;
					$stretch{stop}  = $stop;
					$stretch{name}  = $positions{$chr}{$start}{$stop};
				} elsif ( $start > ( $stretch{stop} ) ) {

				 	# first we add the current stretch to the regions array
				 	$regions{$stretch{chr}}{$stretch{start}}{$stretch{stop}} = $stretch{name};

					# start a new stretch
					$stretch{chr}   = $chr;
					$stretch{start} = $start;
					$stretch{stop}  = $stop;
					$stretch{name}  = $positions{$chr}{$start}{$stop};
				} elsif ( $stretch{stop} <= $stop ) {

					# modify the stretch contents
					$stretch{stop} = $stop;
					$stretch{name} .= "_".$positions{$chr}{$start}{$stop} unless ($stretch{name} eq $positions{$chr}{$start}{$stop} || length ($stretch{name}) > 40);
				}
			}
		}

		# we add the last stretch to the regions
		$regions{$stretch{chr}}{$stretch{start}}{$stretch{stop}} = $stretch{name};
	}
	return (\%regions);
}


__END__

=head1 OPTIONS

=head3 Gene coverage generator options:

=over 8

=item B<-g --gene>

The ensembl gene (ensembl ID or unique cannonical name) for which to calculate coverage statistics. Coverage statistics
will be calculated for all known exons of this gene. Alterantively a genomic region in the chr:start-stop format can
be specified.
This option is overruled if a regions file is specified.
Specify this option multiple times for multi gene coverage statistics.

=item B<-r --regions>

A bed file specifying genomic regions for which to calculate coverage. Either a file name or a BitQC file object can be
specified.

=item B<-e --export>

One of "json", "txt" or "mongodb". The output format of the coverage statistics files. Pdf and html options comming soon? [required]

=item B<-t --threshold>

Calculate the number of bases with a coverage equal to or higher than this threshold

=item B<--remove_overlap>

If set overlapping regions in the target regions will be concatenated to one region.
Use --noremove_overlap to disable [true]

=item B<-b --bam>

List of input bam files, a directory containing bam files or a list of BitQC file objects of bam files [required]

=item B<--bininterval>

Integer value specifying the interval in basepairs by which the coverage frequency distribution is to be binned [10]

=item B<--codingonly>

Set this falg to limit the gene information obtained from ensembl to the coding parts of all exons

=item B<--normalizeto>

Set this flag to normalize all coverage data to a preset number of reads. This option can be usefull when
comparing coverage statistics accros several bam files e.g. to evauluate different capture strategies. 
Beware to choose a value close to the mean number of reads over all bam files, otherwise the errors in the
coverage statistics will become too big when normalizing

=item B<--readstats>

Set this flagg to generate some global reads stats on the input bam files
Beware that this takes a lot of time for large BAM files

=item B<--rawdata>

Set this flag to export the raw data used for calculating coverage statistics. The individual data points used in canculating coverage statistics will be included in this file.

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
