#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use DateTime;
use Math::Complex;
use Sys::Hostname;
use Getopt::Long;
use Pod::Usage;
use XML::Simple;
use lib::functions;
use Data::Dumper::Simple;

# get the version of the script for logging
my $svn_version  = &script_version();
my $current_time = DateTime->now( time_zone => 'floating' );
my $host         = hostname;

#default settings
my $man            = 0;
my $help           = 0;
my $version        = 0;
my $quiet          = 0;
my $database       = 0;
my $bam            = 0;
my $procs          = 0;
my $genome         = 0;
my $regions        = 0;
my $readlength     = 0;
my $output         = 0;
my $primers        = 0;
my $min_cov        = 0;
my $max_readlength = 150;

pod2usage("$0: No arguments specified.") if ( @ARGV == 0 );
GetOptions(
	'help|?'            => \$help,
	man                 => \$man,
	'version|v'         => \$version,
	'quiet|q'           => \$quiet,
	'procs=i'           => \$procs,
	'database|d=s'      => \$database,
	'bam|b=s'           => \$bam,
	'genome|g=s'        => \$genome,
	'regions|r=s'       => \$regions,
	'primers|p=s'       => \$primers,
	'readlength=i'      => \$readlength,
	'output|o=s'        => \$output,
	'min_cov=i'         => \$min_cov,
	'max_read_length=i' => \$max_readlength
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

die "$0, $svn_version.\n" if $version;

# specify default settings here
#my $mongoserver = "localhost";
#my $mongoport   = "27017";
#my $mongodb     = "nxtseq";

# get the configuration for the script
#my %mongo_server = (
#	host     => $mongoserver,
#	port     => $mongoport,
#	database => $mongodb
#);

#my @prepare = ( "ensemblAPI", "pph" );
#my $server = server(
#	mongo_server  => \%mongo_server,
#	server_config => "nxtvat",
#	server        => "localhost",
#	prepare       => \@prepare
#);

#print Dumper ($server);

push @INC, ('/opt/ensembl-api-64/ensembl/modules', '/opt/ensembl-api-64/ensembl-variation/modules');
require Bio::EnsEMBL::Registry;

my $registry = 'Bio::EnsEMBL::Registry';

#Make ensembl registry 
$registry->load_registry_from_db(
	-host    => '10.0.0.105',
	-user    => 'ensembluser',
	-pass	=> 'ensemblpassword',
	-verbose => '1'
	);

my $slice_adaptor = $registry->get_adaptor( "homo_sapiens", 'Core', 'Slice' );



##---
## Display general run information
##---
print(
	"###################\n", "# Extract pooled variants #\n",
	"###################\n", "#\n#\t$svn_version\n",
	"#\tHost: $host\n",      "#\tRuntime: $current_time\n",
	"#\tProcess id: $$\n",   "#\n###################\n\n",
) unless $quiet;

my %bam = ();
my $dir;
my $ext;

##---
## User interaction
##---

# TODO Auto gues database name based from filename?
if ( -d $bam ) {
	opendir( DIR, $bam );
	my @bam = grep( /\.bam$/, readdir(DIR) );
	closedir(DIR);
	foreach (@bam) {
		my $bamname;
		( $bamname, $dir, $ext ) = fileparse( $_, '\..*' );
		print "Enter the database name for the $bamname file: ";
		my $ans = <STDIN>;
		chop($ans);
		$bam{ $bam . $bamname . $ext }{name} = $ans;

		#print "Enter the number of genotypes expected in $bamname: ";
		#$ans = <STDIN>;
		#chop($ans);
		#$bam{ $bam . $bamname . $ext }{genotypes} = $ans;
	}
	$dir = $bam;
} else {
	print "Enter the database name for the bam file: ";
	my $ans = <STDIN>;
	chop($ans);
	( my $bamname, $dir, $ext ) = fileparse( $bam, '\..*' );
	$bam{$bam}{name} = $ans;

	#	print "Enter the number of genotypes expected in $bam: ";
	#	$ans = <STDIN>;
	#	chop($ans);
	#	$bam{ $bam }{genotypes} = $ans;
}

# set the sigterm reaction for the script and the children in case we want to fork
#my $Fork = new Parallel::Forker( use_sig_child => 1 );
#$SIG{CHLD} = sub { Parallel::Forker::sig_child($Fork); };
#$SIG{TERM} = sub {
#	$Fork->kill_tree_all('TERM') if $Fork && $Fork->in_parent;
#	die "Quitting...\n";
#};

#$Fork->max_proc($procs);

my $genomename;
my $genomepath;
my $genomeext;
( $genomename, $genomepath, $genomeext ) = fileparse( $genome, '\..*' );
my $fasta = $genomepath . "samtools/" . $genomename . $genomeext;

my @regions;

# check regions file
if ( -e $regions ) {
	open( INFILE, "< $regions" )
	  || die "cannot open coordinates file!";

	my %positions;

	# we process the reads for each region of interest
	while (<INFILE>) {
		chomp;
		my @line = split( /\t/, $_ );
		$positions{ $line[1] }{ $line[2] }{ $line[3] } = 1;
	}
	close INFILE;

	# concatenate the regions and remove the overlap
	for my $chr ( keys %positions ) {
		my %stretch;
		for my $start ( sort { $a <=> $b } keys %{ $positions{$chr} } ) {
			for my $stop (
				sort { $a <=> $b }
				keys %{ $positions{$chr}{$start} }
			  )
			{
				if ( !%stretch ) {

					# start a new stretch
					$stretch{chr}   = $chr;
					$stretch{start} = $start;
					$stretch{stop}  = $stop;
				} elsif ( $start > ( $stretch{stop} + $max_readlength ) ) {

			   # the feature is more than "$maxreadlength" basepairs appart from
			   # the previous feature so we create a new stretch
			   # first we add the current stretch to the regions array
					push( @regions,
						    $stretch{chr} . ":"
						  . $stretch{start} . "-"
						  . $stretch{stop} );

					# start a new stretch
					$stretch{chr}   = $chr;
					$stretch{start} = $start;
					$stretch{stop}  = $stop;
				} elsif ( $stretch{stop} <= $stop ) {

					# modify the stretch contents
					$stretch{stop} = $stop;
				}
			}
		}

		# we add the last stretch to the regions
		push( @regions,
			$stretch{chr} . ":" . $stretch{start} . "-" . $stretch{stop} );
	}

} elsif ( $regions eq "infer" ) {

  # TODO: autocreate regions based on coverage
  # this will drastically reduce memory requirements and improve parallelization
} else {

	# get the chromosome names for parallelisation
	@regions = `cut -f1 $fasta.fai`;
}

my %primers;

# check regions file
if ( -e $primers ) {
	open( INFILE, "< $primers" )
	  || die "cannot open primers file!";

	# get the positions close to the primers
	while (<INFILE>) {
		chomp;

		my @line = split( /\t/, $_ );
		for my $i ( $line[2] .. $line[1] + $readlength ) {

			$primers{ $line[0] }{$i} = "read_start";
		}
		for my $i ( $line[4] - $readlength .. $line[3] ) {
			$primers{ $line[0] }{$i} = "read_start";
		}
	}
	close INFILE;
	open( INFILE, "< $primers" )
	  || die "cannot open primers file!";

	# overlay the primer positions themselves
	while (<INFILE>) {
		chomp;
		my @line = split( /\t/, $_ );
		for my $i ( $line[1] .. $line[2] ) {
			$primers{ $line[0] }{$i} = "primer";
		}
		for my $i ( $line[3] .. $line[4] ) {
			$primers{ $line[0] }{$i} = "primer";
		}
	}
	close INFILE;
}

my %allvariants;
my %variants;
my %coverage;
my %chromrepeats;

foreach my $region (@regions) {
	chomp($region);

	$region =~ m/(^\w+):(\d+)-(\d+$)/;
	my $start = $2;
	my $end   = $3;
	my $slice = $slice_adaptor->fetch_by_region( 'chromosome', $1, $2, $3 );

	my @repeats = @{ $slice->get_all_RepeatFeatures() };

	my %repeats;
	foreach my $repeat (@repeats) {
		for my $i ( $repeat->start() .. $repeat->end() ) {
			$repeats{$i} = $repeat->display_id();
		}
	}

	#foreach my $chr ( keys %regions ) {
	#	foreach my $start ( keys %{ $regions{$chr} } ) {
	#		foreach my $stop ( keys %{ $regions{$chr}{$start} } ) {
	for my $filename ( keys %bam ) {

		#		$Fork->schedule(
		#			label        => "extract_variants",
		#			run_on_start => sub {

		# get the name for the bam file in the database
		my $poolname = $bam{$filename}{name};

		# get the name for the bam file in the database
		my $bam_genotypes = $bam{$filename}{genotypes};

#				print "samtools-0.1.11 view -u $filename $region | samtools-0.1.11 pileup -f $fasta -|";
#				open( IN, "samtools-0.1.11 view -u $filename $region | samtools-0.1.11 pileup -f $fasta -|" ) || die "cannot open pipe";
		open( IN,
"samtools-0.1.16 mpileup -Q0 -d10000000  -m 3 -F 0.0002 -f $fasta $filename -r $region |"
		) || die "cannot open pipe";

		my $i = 0;
		my %pile;
		my @map_qual;
		my @read_pos;
		my $maxreadlength = 0;
	  LINE: while (<IN>) {    #Loop through lines
			   # print "$i lines processed of $filename\n" if !( $i % 1000000 );
			$i++;

			##---
			## Get values from line
			##---
			chomp;
			my @a = split( /\t/, $_ );

			#$a[0] =~ /^chr(.+)/; # chop off the 'chr' part of the chromosome
			my $chr  = $a[0];
			my $pos  = $a[1];
			my $rfba = uc( $a[2] );
			my $cov  = $a[3];
			my $seq  = $a[4];
			my $qual = $a[5];

			my $originalseq = $seq;

			# remove info on indel bases
			#$seq =~ s/\*//g;

			if ( $repeats{$i} ) {
				$chromrepeats{$chr}{$pos} = $repeats{$i};
			}

			my $index = 0;
			foreach (@read_pos) {
				$read_pos[$index] += 1;
				$maxreadlength = $read_pos[$index]
				  if ( $read_pos[$index] > $maxreadlength );
				$index++;
			}

			my %indels;

			# remove indels from $seq string
			while ( $seq =~ m/(\+|\-)([0-9]+)([ACGTNacgtn]+)/ ) {
				my $cutoutlength = length($1) + length($2) + $2;

				# do not use length ($3) because a snp might follow an indel!!!
				my $indel = substr( $seq, $-[0], $cutoutlength, "" );
				$allvariants{ uc($indel) } = 1;
				$variants{$region}{$chr}{$pos}{$rfba}{$poolname}{ uc($indel) }
				  {'var_cov'} += 1;
				$coverage{$region}{$chr}{$pos}{$rfba}{$poolname}
				  {'cov'} += 1;
				if ( $indel =~ m/[ACGTN]+/ ) {
					$variants{$region}{$chr}{$pos}{$rfba}{$poolname}
					  { uc($indel) }{'var_fc'} += 1;
					$coverage{$region}{$chr}{$pos}{$rfba}{$poolname}
					  {'fc'} += 1;
				} else {
					$variants{$region}{$chr}{$pos}{$rfba}{$poolname}
					  { uc($indel) }{'var_rc'} += 1;
					$coverage{$region}{$chr}{$pos}{$rfba}{$poolname}
					  {'rc'} += 1;
				}
				$variants{$region}{$chr}{$pos}{$rfba}{$poolname}{ uc($indel) }
				  {'var_tot_qual'} = 0;
				$variants{$region}{$chr}{$pos}{$rfba}{$poolname}{ uc($indel) }
				  {'var_tot_map_qual'} = 0;

			}

			my $newreads;
			while ( $seq =~ m/(\^)(.)/ ) {
				substr( $seq, $-[0], 2, "" );

				#				if ( $i eq 1 ) {
				#					shift(@read_pos);
				#					shift(@map_qual);
				#					shift(@read_pos);
				#					shift(@map_qual);
				#					shift(@read_pos);
				#					shift(@map_qual);
				#				}

				push( @map_qual, $2 );
				push( @read_pos, 1 );
				$newreads++;

			}

			my @splits;
			my $j = 0;
			while ( $seq =~ m/\$/ ) {
				substr( $seq, $-[0], 1, "" );

# $ sign concerns the base before it, so we remove the quality score with index one less
# we also substract the number of bases already removed since the index of the base
# we want to remove will decrease 1 with every base removed
				push( @splits, ( $-[0] - $j - 1 ) );
				$j++;
			}

			if ( $i eq 1 ) {
				my @base = split( //, $seq );
				foreach ( 0 .. $#base - $newreads ) {
					push( @read_pos, 1 );
					push( @map_qual, 0 );
				}
			}

	# TODO: remove this block once we are confident that is works with no errors
			my $map_qal_length  = $#map_qual + 1;
			my $read_pos_length = $#read_pos + 1;
			my $seq_length      = length($seq);
			my $qual_length     = length($qual);
			die
"WARNING: inconsistency found in lengths!!\n$region $pos \n$originalseq\n$seq\n$cov $seq_length $qual_length $map_qal_length $read_pos_length\n"
			  if ( $cov != $seq_length
				|| $cov != $qual_length
				|| $cov != $map_qal_length
				|| $cov != $read_pos_length );

			#$pile{$chr}{$pos}{rfba} = $rfba;
			my $fref = uc($rfba);
			my $rref = lc($rfba);
			$seq =~ s/\./$fref/g;
			$seq =~ s/,/$rref/g;

			my @base = split( //, $seq );
			my @qual = split( //, $qual );

			my $c = 0;
			foreach (@base) {
				my $phred    = ord( $qual[$c] ) - 33;
				my $mapphred = ord( $map_qual[$c] ) - 33;
				my $qual     = 10**( -$phred / 10.0 );
				my $mapqual  = 10**( -$mapphred / 10.0 );
				#my $count =
				#  1 - ( sqrt( ( $qual * $qual ) + ( $mapqual * $mapqual ) ) );

				my $count =
				1;

				$allvariants{ uc( $base[$c] ) } = 1;
				$variants{$region}{$chr}{$pos}{$rfba}{$poolname}
				  { uc( $base[$c] ) }{'var_cov'} += $count;
				$variants{$region}{$chr}{$pos}{$rfba}{$poolname}
				  { uc( $base[$c] ) }{'var_tot_qual'} += $phred;
				$variants{$region}{$chr}{$pos}{$rfba}{$poolname}
				  { uc( $base[$c] ) }{'var_tot_map_qual'} += $mapphred;
				$coverage{$region}{$chr}{$pos}{$rfba}{$poolname}
				  {'cov'} += $count;
				if ( $base[$c] =~ m/[ACGTN]+/ ) {
					$variants{$region}{$chr}{$pos}{$rfba}{$poolname}
					  { uc( $base[$c] ) }{'var_fc'} += $count;
					$coverage{$region}{$chr}{$pos}{$rfba}{$poolname}
					  {'fc'} += $count;
				} else {
					$variants{$region}{$chr}{$pos}{$rfba}{$poolname}
					  { uc( $base[$c] ) }{'var_rc'} += $count;
					$coverage{$region}{$chr}{$pos}{$rfba}{$poolname}
					  {'rc'} += $count;
				}
				$c++;
			}

			# splice out reads that ended from the quality array
			foreach (@splits) {
				splice( @map_qual, $_, 1 );
				splice( @read_pos, $_, 1 );
			}
		}
		close IN;
	}
}
open( OUTFILE, "> $output" );

#print OUTFILE
#"Region\tChromosome\tPosition\tPool\tRepeat\tPrimer\tReference\tRef_cov\tFor_cov\tRev_cov\tVariant\tVar_cov\tVar_for_cov\tVar_rev_cov";
print OUTFILE
"Region\tChromosome\tPosition\tPool\tRepeat\tPrimer\tReference\tRef_cov\tFor_cov\tRev_cov\tVariant\tVar_cov\tVar_for_cov\tVar_rev_cov\tVar_qual\tVar_map_qual";

#foreach my $variant ( sort keys %allvariants ) {
#	print OUTFILE $variant . "\t";
#}
print OUTFILE "\n";

foreach my $region ( keys %variants ) {
	foreach my $chr ( keys %{ $variants{$region} } ) {
		foreach my $pos ( sort keys %{ $variants{$region}{$chr} } ) {
			foreach my $rfba ( sort keys %{ $variants{$region}{$chr}{$pos} } ) {
				foreach my $pool (
					sort keys %{ $variants{$region}{$chr}{$pos}{$rfba} } )
				{

					foreach my $variant ( sort keys %allvariants ) {

						print OUTFILE $region . "\t" 
						  . $chr . "\t" 
						  . $pos . "\t"
						  . $pool . "\t";
						if ( $chromrepeats{$chr}{$pos} ) {
							print OUTFILE $chromrepeats{$chr}{$pos} . "\t";
						} else {
							print OUTFILE "0\t";
						}
						if ( $primers{$chr}{$pos} ) {
							print OUTFILE $primers{$chr}{$pos} . "\t";
						} else {
							print OUTFILE "0\t";
						}
						print OUTFILE $rfba . "\t";
						if ( $coverage{$region}{$chr}{$pos}{$rfba}{$pool}
							{'cov'} )
						{
							printf OUTFILE "%5.3f\t",
							  $coverage{$region}{$chr}{$pos}{$rfba}{$pool}
							  {'cov'};
						} else {
							print OUTFILE "0\t";
						}
						if ( $coverage{$region}{$chr}{$pos}{$rfba}{$pool}
							{'fc'} )
						{
							printf OUTFILE "%5.3f\t",
							  $coverage{$region}{$chr}{$pos}{$rfba}{$pool}
							  {'fc'};
						} else {
							print OUTFILE "0\t";
						}
						if ( $coverage{$region}{$chr}{$pos}{$rfba}{$pool}
							{'rc'} )
						{
							printf OUTFILE "%5.3f\t",
							  $coverage{$region}{$chr}{$pos}{$rfba}{$pool}
							  {'rc'};
						} else {
							print OUTFILE "0\t";
						}
						print OUTFILE $variant . "\t";
						if ( $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							{$variant}{'var_cov'} )
						{
							printf OUTFILE "%5.3f\t",
							  $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							  {$variant}{'var_cov'};
						} else {
							print OUTFILE "0\t";
						}
						if ( $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							{$variant}{'var_fc'} )
						{
							printf OUTFILE "%5.3f\t",
							  $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							  {$variant}{'var_fc'};
						} else {
							print OUTFILE "0\t";
						}
						if ( $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							{$variant}{'var_rc'} )
						{
							printf OUTFILE "%5.3f\t",
							  $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							  {$variant}{'var_rc'};
						} else {
							print OUTFILE "0\t";
						}

						if ( $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							{$variant}{'var_cov'} )
						{
							my $mean_qual =
							  $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							  {$variant}{'var_tot_qual'} /
							  $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							  {$variant}{'var_cov'};
							printf OUTFILE "%5.3f\t", $mean_qual;
							my $mean_map_qual =
							  $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							  {$variant}{'var_tot_map_qual'} /
							  $variants{$region}{$chr}{$pos}{$rfba}{$pool}
							  {$variant}{'var_cov'};
							printf OUTFILE "%5.3f",
							  $mean_map_qual;
						} else {
							print OUTFILE "O\t0";
						}
						print OUTFILE "\n";
					}
				}
			}
		}
	}
}

# set all forks as ready
#$Fork->ready_all;

# run the ready forks
#$Fork->poll;

#wait for the forks to finish
#$Fork->wait_all();

__END__

=head1 NAME

extract_variants_pooled.pl - A script to insert variant and coverage information into a database

=head1 SYNOPSIS

extract_variants_pooled.pl [options]

Use -? to see options

=head1 OPTIONS

=over 8

=item B<-h -? --help>	Print a brief help message and exits.

=item B<-m --man>		Displays the manual page.

=item B<-v --version>	Displays the version of the script.

=item B<-q --quiet>		Quiet, supress all output.

=item B<-b --bam>		[required] the sorted bam file to process of a directory containing sorted bam files

=item B<-g --genome>	[required] The fasta file for the genome the reads where mapped on

=item B<--regions -r>	a file containing the regions of interest in a <name>\t<chromosome>\t<start>\t<stop>

=item B<--output -o>	file to write output to

=back

=head1 DESCRIPTION

B<extract_variants_pooled> will process data from a (list of) bam file(s) extract the variants and the coverage, and insert this information into a database.

=cut
