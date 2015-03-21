#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use PBS::Client;
use SequencingTools;

# get the command line arguments
my $man         = 0;
my $help        = 0;
my $version     = 0;
my $quiet       = 0;
my $inputfile   = 0;
my $regionsfile = 0;
my $organism_id = 0;
my $build       = 0;
my $index       = 0;
my $mongoserver = 0;
my $mongoport   = 0;
my $mongodb     = 0;
my $config_id   = 0;
pod2usage("$0: No arguments specified.") if ( @ARGV == 0 );
my %command_args;
%{ $command_args{arguments} } = (@ARGV);
GetOptions(
	'help|?'     => \$help,
	man          => \$man,
	'version|v'  => \$version,
	'quiet|q'    => \$quiet,
	'fasta|f=s'  => \$inputfile,
	'region|r=s' => \$regionsfile,
	'build|b=s'  => \$build,
	'index|i=s'  => \$index,
	'config=s'   => \$config_id,
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

# specify default settings here
$mongoserver = "localhost" unless ($mongoserver);
$mongoport   = "27017"     unless ($mongoport);
$mongodb     = "nxtseq"    unless ($mongodb);

# get the configuration for the script
my %mongo_server = (
	host     => $mongoserver,
	port     => $mongoport,
	database => $mongodb
);

my $sequencingtools = new SequencingTools(
	mongo_server => \%mongo_server,
	config_id    => $config_id,
	stagein      => 1,
	prepare      => ["fastahack"]
);

if ($inputfile) {
	if ( -d $inputfile ) {
		opendir( DIR, $inputfile );
		my @files = grep( /\.fa$/, readdir(DIR) );
		closedir(DIR);
		my $i = 0;
		foreach (@files) {
			$sequencingtools->{run_config}->{inputfile}[$i] =
			  $inputfile . $files[$i];
			$i++;
		}
	} else {
		@{ $sequencingtools->{run_config}->{inputfile} } = ($inputfile);
	}
}
$sequencingtools->{run_config}->{regionsfile} = $regionsfile if ($regionsfile);
@{ $sequencingtools->{run_config}->{index} } = ($index) if ($index);
$sequencingtools->{run_config}->{build}       = $build       if ($build);
$sequencingtools->{run_config}->{organism_id} = $organism_id if ($organism_id);

# check arguments
die "use -? to see correct command line arguments\n"
  unless ( $sequencingtools->{run_config}->{inputfile}
	&& $sequencingtools->{run_config}->{build}
	&& $config_id );

my $fastahack =
  $sequencingtools->{nodeconfig}->{executables}->{fastahack}->{command};

#########################
# configuration options #
#########################

# create a genome specific dir for holding the genome and index files unless it exists
if (
	!(
		  -d $sequencingtools->{node_config}->{paths}->{genomedir}->{dir}
		. $sequencingtools->{run_config}->{organism_id} . "/"
		. $sequencingtools->{run_config}->{build}
	)
  )
{
	mkdir $sequencingtools->{node_config}->{paths}->{genomedir}->{dir}
	  . $sequencingtools->{run_config}->{organism_id}, 0777;
	mkdir $sequencingtools->{node_config}->{paths}->{genomedir}->{dir}
	  . $sequencingtools->{run_config}->{organism_id} . "/"
	  . $sequencingtools->{run_config}->{build}, 0777;
	$sequencingtools->log_message( message => "Directory "
		  . $sequencingtools->{node_config}->{paths}->{genomedir}->{dir}
		  . $sequencingtools->{run_config}->{organism_id} . "/"
		  . $sequencingtools->{run_config}->{build}
		  . " created" );
}

# target fasta name:
my $fasta =
    $sequencingtools->{node_config}->{paths}->{genomedir}->{dir}
  . $sequencingtools->{run_config}->{organism_id} . "/"
  . $sequencingtools->{run_config}->{build} . "/"
  . $sequencingtools->{run_config}->{build} . ".fa";

# check to see if target fasta exists
if ( -e $fasta ) {
	$sequencingtools->log_message(

		message => "Fasta $fasta found"
	);
	if ( $sequencingtools->{run_config}->{replace} ) {
		$sequencingtools->log_message(

			message => "$fasta will be replaced"
		);
	} elsif ( $sequencingtools->{run_config}->{reindex} ) {
		$sequencingtools->log_message(

			message => "New indexes will be build for $fasta"
		);
		goto INDEX if $sequencingtools->{run_config}->{reindex};
	} else {
		die(
			$sequencingtools->finish_log(

				message =>
"Genome already exists, please enter a new build name or choose to overwrite the genome"
			),
			"Enter a new build name for the genome...\n"
		);
	}
}

# here we create copy or concatenate the reference fasta file
open( OUTFILE, "+> $fasta" )
  || die(
	$sequencingtools->finish_log(

		message => "Cannot open sequence fasta file!"
	),
	"Cannot open sequence fasta file!\n"
  );

if ( $sequencingtools->{run_config}->{regionsfile} ) {

	# create the reference fasta from the coordinates file

	$sequencingtools->log_message(

		message => "Creating genome fasta in $fasta"
	);

	open( IN, "<" . $sequencingtools->{run_config}->{regionsfile} )
	  || die(
		$sequencingtools->finish_log(

			message => "Cannot open coordinates file!"
		),
		"Cannot open coordinates file!\n"
	  );

	my $c = 0;
	while (<IN>) {
		chomp;
		my @a = split( /\t/, $_ );

		my $start       = $a[2];
		my $end         = $a[3];
		my $chr         = $a[1];
		my $sourcefasta = $sequencingtools->{run_config}->{inputfile}[0];
		my @sequence    = `$fastahack $sourcefasta $chr:$start..$end`;

		print OUTFILE ">" . $a[0] . "\n" . $sequence[0] . "\n";
		$c++;
	}

	close IN;
	$sequencingtools->log_message( message => "$c sequences created" );
} else {
	$sequencingtools->log_message( message => "Copying to $fasta file" );
	foreach ( @{ $sequencingtools->{run_config}->{inputfile} } ) {
		open( IN, "<" . $_ ) || die(
			$sequencingtools->finish_log(

				message => "Cannot open input fasta file!"
			),
			"Cannot open fasta file!\n"
		);
		while (<IN>) {
			print OUTFILE;
		}
	}
	close IN;
	$sequencingtools->log_message( message => "Done copying files" );
}
close OUTFILE;

#enter the genome in the database so we know it is avaiable
INDEX:

# create a PBS client object for PBS job submission
my $client =
  PBS::Client->new(
	server => $sequencingtools->{node_config}->{pbs}->{server} );

# open mongo connection
my $mongod = MongoDB::Connection->new(
	"host" => $mongo_server{host} . ":" . $mongo_server{port} );
my $database = $mongo_server{database};
my $logdb    = $mongod->$database;
my $col      = $logdb->genome;
my %genome   = (
	build       => $sequencingtools->{run_config}->{build},
	organism_id => $sequencingtools->{run_config}->{organism_id},
	fasta       => $sequencingtools->{run_config}->{build} . ".fa"
);
my $genome_record_id;
my $genome_record = $col->find_one( \%genome );

if ($genome_record) {
	$genome_record_id = $genome_record->{_id};
} else {
	$genome_record = $col->insert( \%genome, { safe => 1 } );
	$genome_record_id = $genome_record->value;
}

my @jobs;

# create job to notify user upon error
my %error = (
	log_id     => $sequencingtools->{log_id},
	to_email   => $sequencingtools->{run_config}->{to_email},
	from_email => $sequencingtools->{run_config}->{from_email},
	subject    => "Job_" . $config_id,
	message =>
"Dear_user\\n\\nYour_genome_creation_job_has_failed.\\nPlease_contact_the_system_administrators_for_more_information.",
	analysis_server => $sequencingtools->{run_config}->{server},
	server_config   => $sequencingtools->{run_config}->{server_config},
	mongo_host      => $mongo_server{host},
	mongo_port      => $mongo_server{port},
	mongodb         => $mongo_server{database}
);
my $error = PBS::Client::Job->new(
	name => 'error',
	cmd  => $sequencingtools->{node_config}->{executables}->{jobscripts}->{path}
	  . "jobs_notify.pl",
	vars    => {%error},
	wallt   => '30',
	cput    => '30',
	queue   => $sequencingtools->{node_config}->{pbs}->{queue},
	mailopt => "e"
);

if ( !$sequencingtools->{run_config}->{index} ) {
	$sequencingtools->log_message(

		message => "No index requested, so none created"
	);
} else {

	$sequencingtools->log_message( message => "Start generating indexes" );

	foreach ( @{ $sequencingtools->{run_config}->{index} } ) {
		my $index = $_;

		my %vars = (
			index            => $index,
			fasta            => $fasta,
			log_id           => $sequencingtools->{log_id},
			mongo_host       => $mongo_server{host},
			mongo_port       => $mongo_server{port},
			mongodb          => $mongo_server{database},
			config_id        => $config_id,
			genome_record_id => $genome_record_id,
		);

		my $job = PBS::Client::Job->new(
			name => 'generate_index',
			cmd  => $sequencingtools->{node_config}->{executables}->{jobscripts}
			  ->{path} . "jobs_generate_index.pl",
			vars  => {%vars},
			queue => $sequencingtools->{node_config}->{pbs}->{queue},
			wallt => '04:00:00',
			cput  => '14400',
			next  => { fail => $error }
		);

		push( @jobs, $job );

		#$client->qsub($job);

		#my $pbsid = $job->pbsid;
		#log_message(
		#
		#	message => "Job submitted with id $pbsid"
		#);
	}
}

# store the newly created genome in the mongo grid
my %store = (
	log_id    => $sequencingtools->{log_id},
	filename  => $genome_record_id,
	extension => '.tar.b2',
	inputpath => $sequencingtools->{node_config}->{paths}->{genomedir}->{dir}
	  . $sequencingtools->{run_config}->{organism_id} . "/"
	  . $sequencingtools->{run_config}->{build} . "/",
	mongo_host      => $mongo_server{host},
	mongo_port      => $mongo_server{port},
	mongodb         => $mongo_server{database},
	analysis_server => $sequencingtools->{run_config}->{server},
	server_config   => $sequencingtools->{run_config}->{server_config}
);
my $store = PBS::Client::Job->new(
	name => 'grid_store',
	cmd  => $sequencingtools->{node_config}->{executables}->{jobscripts}->{path}
	  . "jobs_grid_store.pl",
	vars  => {%store},
	queue => $sequencingtools->{node_config}->{pbs}->{queue},
	wallt => '04:00:00',
	cput  => '14400',
	prev  => { ok => \@jobs },
	next  => { fail => $error }
);

my %notify = (
	log_id     => $sequencingtools->{log_id},
	to_email   => $sequencingtools->{run_config}->{to_email},
	from_email => $sequencingtools->{run_config}->{from_email},
	subject    => "Job_" . $config_id,
	message =>
"Dear_user\\n\\nYour_genome_creation_job_has_finished_successfully.\\nYou_can_now_start_using_your_new_genome\\n\\nKind_regards\\nThe_NXTVAT_team",
	analysis_server => $sequencingtools->{run_config}->{server},
	server_config   => $sequencingtools->{run_config}->{server_config},
	mongo_host      => $mongo_server{host},
	mongo_port      => $mongo_server{port},
	mongodb         => $mongo_server{database},
	analysis_server => $sequencingtools->{run_config}->{server},
	server_config   => $sequencingtools->{run_config}->{server_config},
	finish_master   => 'true'
);
my $notify = PBS::Client::Job->new(
	name => 'notify',
	cmd  => $sequencingtools->{node_config}->{executables}->{jobscripts}->{path}
	  . "jobs_notify.pl",
	vars  => {%notify},
	queue => $sequencingtools->{node_config}->{pbs}->{queue},
	wallt => '30',
	cput  => '30',

	#	maillist => $sequencingtools->{run_config}->{to_email},
	#	mailopt => "e",
	prev => { ok   => $store },
	next => { fail => $error }
);

$client->qsub($notify);

__END__

=head1 NAME
create_genome.pl - Script to create a reference genome and optionally an index for it

=head1 SYNOPSIS

create_genome.pl.pl [options]

Use -? to see options

=head1 OPTIONS

=over 8

=item B<-h -? --help>	Print a brief help message and exits.

=item B<-m --man>		Displays the manual page.

=item B<-v --version>	Displays the version of the script.

=item B<--config>		A xml configuration file to run the script.

=item B<-p --procs>		Number of processes to use. [default 14]

=item B<-f --fasta>		The input file: either
						- 	One or more fasta/multiple fasta files ending in .fa, to specify 
							multiple files use the directory containing them 
							(!! NO validity check is performed on the file format!!)
							The fasta files will be merged to one multiple fasta in the genomes directory
						-	One fasta file with a full samtools index for sequence retrieval by fastahack

=item B<-r --region>	A genomic locations file in the <<build>>tab<<chromosome>>tab<<start>>tab<<stop>>newline format
						If this file is specified a reference fasta will be constucted using fastahack

=item B<-g --genome_dir>	The directory where to store the fasta and the coresponding indexes

=item B<-b --build>		The build for the genome

=item B<-i --index>		the index to be created on the fasta reference genome
						-	all: creates bwa, broad, bowtie  [default]
						-	none: skip index creation
						-	bowtie: bowtie index
						-	broad: samtools picard and GATK indexes
						-	bwa: default bwtsw index
						-	bwaIS: bwa IS index creation (max genome size limited!)
						-	casava CASAVA 1.6 eland alignment !!See manual for size restrictions!!

=back

=head1 DESCRIPTION

B<create_genome> function:
This function will create a fasta file in the specified directory as a reference genome for aligning
An index for the aligner of choice will be created in the corresponding subdirectory

=cut
