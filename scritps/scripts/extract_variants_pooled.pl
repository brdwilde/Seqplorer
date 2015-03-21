#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use DateTime;
use Sys::Hostname;
use Getopt::Long;
use Pod::Usage;
use XML::Simple;
use Parallel::Forker;
use lib::functions;
use Data::Dumper::Simple;

# get the version of the script for logging
my $svn_version = &script_version();

my $current_time = DateTime->now( time_zone => 'floating' );
my $host = hostname;

# get the configurations specified in the config file
my $config   = XMLin('config.xml');
my $samtools = $config->{executables}->{samtools};

#default settings
my $man             = 0;
my $help            = 0;
my $version         = 0;
my $quiet           = 0;
my $database        = 0;
my $bam             = 0;
my $temp            = $config->{settings}->{temp};
my $procs           = $config->{settings}->{procs};
my $genome          = 0;
my $regions         = 0;
my $minbasequal     = 20;
my $minmapqual      = 30;
my $beginning_ommit = 0;
my $end_ommit       = 0;
my $min_cov         = 0;
my $max_readlength  = 150;

pod2usage("$0: No arguments specified.") if ( @ARGV == 0 );
GetOptions(
	'help|?'            => \$help,
	man                 => \$man,
	'version|v'         => \$version,
	'quiet|q'           => \$quiet,
	'procs|p=i'         => \$procs,
	'database|d=s'      => \$database,
	'bam|b=s'           => \$bam,
	'temp|t=s'          => \$temp,
	'genome|g=s'        => \$genome,
	'mapqual=i'         => \$minmapqual,
	'basequal=i'        => \$minbasequal,
	'regions|r=s'       => \$regions,
	'ignore_start=i'    => \$beginning_ommit,
	'ignore_end=i'      => \$end_ommit,
	'min_cov=i'         => \$min_cov,
	'max_read_length=i' => \$max_readlength
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

die "$0, $svn_version.\n" if $version;

# check temp dir
die "Temp dir is not a directory, please specify a valid path"
  unless ( -d $temp );

##---
## Display general run information
##---
print(
	"###################\n", "# Extract pooled variants #\n",
	"###################\n", "#\n#\t$svn_version\n",
	"#\tHost: $host\n",      "#\tRuntime: $current_time\n",
	"#\tProcess id: $$\n",   "#\n###################\n\n",
) unless $quiet;

##---
## Display quality settings
##---
print(

	# TODO: update version of samtools ?
"WARNING: Samtools-0.1.11 is used by this script by default, not the version in the config\n\n",
	"Quality settings:\n",
	"#################\n",
"The minimal quality values for a read or base to be imported in the database:\n",
	"Base quality (phred): $minbasequal\n",
	"Read quality: $minmapqual\n",
	"Omitting $beginning_ommit bases from the start of each alignment\n",
	"Omitting $end_ommit form the end of each alignment\n",
	"Minimum coverage to consider a location: $min_cov\n\n"
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
	my @bam = grep( /-sorted-recal\.bam$/, readdir(DIR) );
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
	my $ans = "test";    # <STDIN>;
	chop($ans);
	( my $bamname, $dir, $ext ) = fileparse( $bam, '\..*' );
	$bam{$bam}{name} = $ans;

	#	print "Enter the number of genotypes expected in $bam: ";
	#	$ans = <STDIN>;
	#	chop($ans);
	#	$bam{ $bam }{genotypes} = $ans;
}

# set the sigterm reaction for the script and the children in case we want to fork
my $Fork = new Parallel::Forker( use_sig_child => 1 );
$SIG{CHLD} = sub { Parallel::Forker::sig_child($Fork); };
$SIG{TERM} = sub {
	$Fork->kill_tree_all('TERM') if $Fork && $Fork->in_parent;
	die "Quitting...\n";
};

$Fork->max_proc($procs);

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

# we get all the names of the temp files
my @cov_tmp_files;
my @var_tmp_files;

foreach my $region (@regions) {
	chomp($region);

	#foreach my $chr ( keys %regions ) {
	#	foreach my $start ( keys %{ $regions{$chr} } ) {
	#		foreach my $stop ( keys %{ $regions{$chr}{$start} } ) {
	for ( keys %bam ) {
		my $filename = $_;
		my $bamname;
		( $bamname, $dir, $ext ) = fileparse( $_, '\..*' );

		my $cov_file = $temp . $bamname . "_" . $region . "-cov.tmp";
		my $var_file = $temp . $bamname . "_" . $region . "-var.tmp";
		push( @cov_tmp_files, $cov_file );
		push( @var_tmp_files, $var_file );
		$Fork->schedule(
			label        => "extract_variants",
			run_on_start => sub {

				# open the temp files for writing
				open COVERAGE, "> $cov_file"
				  || die "cannot open coverage tmp file: $!";
				open VARIANTS, "> $var_file"
				  || die "cannot open variant tmp file: $!";

				# get the name for the bam file in the database
				my $dbpilename = $bam{$filename}{name};

				# get the name for the bam file in the database
				my $bam_genotypes = $bam{$filename}{genotypes};

#				print "samtools-0.1.11 view -u $filename $region | samtools-0.1.11 pileup -f $fasta -|";
				open( IN,
"samtools-0.1.11 view -u $filename $region | samtools-0.1.11 pileup -f $fasta -|"
				) || die "cannot open pipe";

				my $i = 0;
				my %pile;
				my @map_qual;
				my @read_pos;
				my $maxreadlength = 0;
			  LINE: while (<IN>) {    #Loop through lines
					 # print "$i lines processed of $filename\n" if !( $i % 1000000 );
					$i++;

					my %variants;
					##---
					## Get values from line
					##---
					chomp;
					my @a = split( /\t/, $_ );

			   #$a[0] =~ /^chr(.+)/; # chop off the 'chr' part of the chromosome
					my $chr  = $a[0];
					my $pos  = $a[1];
					my $rfba = $a[2];
					my $cov  = $a[3];
					my $seq  = $a[4];
					my $qual = $a[5];

					# for now we skip indels
					next LINE if ( $rfba eq "*" );

					my $originalseq = $seq;

					# remove info on indel bases
					#$seq =~ s/\*//g;

					my $index = 0;
					foreach (@read_pos) {
						$read_pos[$index] += 1;
						$maxreadlength = $read_pos[$index]
						  if ( $read_pos[$index] > $maxreadlength );
						$index++;
					}

					while ( $seq =~ m/(\^)(.)/ ) {
						substr( $seq, $-[0], 2, "" );
						push( @map_qual, ord($2) - 33 );

						#push( @map_qual, $2 );
						push( @read_pos, 1 );
					}

					my $indels;

					# remove indels from $seq string
					while ( $seq =~ m/(\+|\-)([0-9]+)([ACGTNacgtn]+)/ ) {
						my $cutoutlength = length($1) + length($2) + $2;

				 # do not use length ($3) because a snp might follow an indel!!!
						$indels .= substr( $seq, $-[0], $cutoutlength, "" );
					}

					my @splits;
					my $j = 0;
					while ( $seq =~ m/\$/ ) {
						substr( $seq, $-[0], 1, "" );

# $ sign concerns the base befor it, so we remove the quality score with index one less
# we also substract the number of bases already removed since the index of the base
# we want te remove will decrease 1 with every base removed
						push( @splits, ( $-[0] - $j - 1 ) );
						$j++;
					}

	# TODO: remove this block once we are confident that is works with no errors
					my $map_qal_length  = $#map_qual + 1;
					my $read_pos_length = $#read_pos + 1;
					my $seq_length      = length($seq);
					my $qual_length     = length($qual);
					die
"WARNING: inconsistency found in lengths!!\n $bamname $pos $indels $originalseq $cov $seq_length $qual_length $map_qal_length $read_pos_length"
					  if ( $cov != $seq_length
						|| $cov != $qual_length
						|| $cov != $map_qal_length
						|| $cov != $read_pos_length );

					$pile{$chr}{$pos}{rfba} = $rfba;
					my $fref = uc($rfba);
					my $rref = lc($rfba);
					$seq =~ s/\./$fref/g;
					$seq =~ s/,/$rref/g;

					my @base = split( //, $seq );
					my @qual = split( //, $qual );

					my $c = 0;
					foreach (@base) {
						push(
							@{ $pile{$chr}{$pos}{data} },
							{
								base => $base[$c],

								qual => ord( $qual[$c] ) - 33,

								#qual => $qual[$c],
								mq  => $map_qual[$c],
								pos => $read_pos[$c],
								pos => $read_pos[$c],
							}
						);
						$c++;
					}

					# splice out reads that ended form the quality array
					foreach (@splits) {
						splice( @map_qual, $_, 1 );
						splice( @read_pos, $_, 1 );
					}

				}
				close IN;
				my %qual_statistic_var;
				my %qual_statistic_ref;
				my %qual_statistic_indel;
				my %qual_statistic_skipped;
				my %qual_statistic_filtered_all;
				my %map_qual_statistic_var;
				my %map_qual_statistic_ref;
				my %map_qual_statistic_indel;
				my %map_qual_statistic_skipped;
				my %map_qual_statistic_filtered_all;
				my %qual_by_pos;

				foreach my $chr ( keys %pile ) {
					foreach my $pos ( sort keys %{ $pile{$chr} } ) {
						my %alleles;
						my %coverage;
						my $i = 0;

						foreach ( @{ $pile{$chr}{$pos}{data} } ) {

							#									print Dumper ($_);
							my $start_ommit  = $beginning_ommit;
							my $stop_ommit   = $end_ommit;
							my $count_dir    = "Fc";
							my $qual_dir     = "Fq";
							my $map_qual_dir = "Fmq";
							if ( $_->{base} eq uc( $_->{base} ) ) {

						 # store the qualities by base pos for the forward reads
								$qual_by_pos{ $_->{pos} }{count} += 1;
								$qual_by_pos{ $_->{pos} }{sum}   += $_->{qual};
							} else {

						 # store the qualities by base pos for the reverse reads
								$qual_by_pos{ $maxreadlength - $_->{pos} }
								  {count} += 1;
								$qual_by_pos{ $maxreadlength - $_->{pos} }
								  {sum} += $_->{qual};

								# neg strand base swap read direction
								$start_ommit = $end_ommit;
								$stop_ommit  = $beginning_ommit;

								$count_dir    = "Rc";
								$qual_dir     = "Rq";
								$map_qual_dir = "Rmq";
							}

							#									print $_->{qual}," > ",$minbasequal," ",
							#										 $_->{mq}," > ",$minmapqual," ",
							#										 $_->{pos}," > ",$start_ommit," ",
							#										 $pile{$chr}{ $pos + $stop_ommit }
							#										{data}[$i]," ",
							#										 $pile{$chr}{ $pos + $stop_ommit }
							#										{data}[$i]->{pos}," == ",
							#										($_->{pos} + $stop_ommit),"\n";
							if (   $_->{qual} > $minbasequal
								&& $_->{mq} > $minmapqual
								&& $_->{pos} > $start_ommit
								&& $pile{$chr}{ $pos + $stop_ommit }{data}[$i]
								&& $pile{$chr}{ $pos + $stop_ommit }{data}[$i]
								->{pos} == $_->{pos} + $stop_ommit )
							{

								#										print "base is processed!\n";
								$qual_statistic_filtered_all{sum} += $_->{qual};
								$qual_statistic_filtered_all{count} += 1;
								$map_qual_statistic_filtered_all{sum} +=
								  $_->{mq};
								$map_qual_statistic_filtered_all{count} += 1;
								if (
									uc( $_->{base} ) eq
									uc( $pile{$chr}{$pos}{rfba} ) )
								{
									$coverage{Tc}                += 1;
									$coverage{$count_dir}        += 1;
									$qual_statistic_ref{sum}     += $_->{qual};
									$qual_statistic_ref{count}   += 1;
									$map_qual_statistic_ref{sum} += $_->{mq};
									$map_qual_statistic_ref{count} += 1;
								} elsif ( $_->{base} ne "*" ) {

		  # we count the covarage and the coverage per allele for all non indels
									my $allele_string =
									  $pile{$chr}{$pos}{rfba} . "/"
									  . uc( $_->{base} );
									$alleles{$allele_string}{Tc}  += 1;
									$alleles{$allele_string}{Tq}  += $_->{qual};
									$alleles{$allele_string}{Tmq} += $_->{mq};
									$coverage{Tc}                 += 1;
									$alleles{$allele_string}{$count_dir} += 1;
									$alleles{$allele_string}{$qual_dir} +=
									  $_->{qual};
									$alleles{$allele_string}{$map_qual_dir} +=
									  $_->{mq};
									$coverage{$count_dir}        += 1;
									$qual_statistic_var{sum}     += $_->{qual};
									$qual_statistic_var{count}   += 1;
									$map_qual_statistic_var{sum} += $_->{mq};
									$map_qual_statistic_var{count} += 1;
								} else {
									$qual_statistic_indel{sum}   += $_->{qual};
									$qual_statistic_indel{count} += 1;
									$map_qual_statistic_indel{sum} += $_->{mq};
									$map_qual_statistic_indel{count} += 1;
								}
							} else {
								$qual_statistic_skipped{sum}     += $_->{qual};
								$qual_statistic_skipped{count}   += 1;
								$map_qual_statistic_skipped{sum} += $_->{mq};
								$map_qual_statistic_skipped{count} += 1;
							}
							$i++;
						}

						#print $pos, Dumper (%alleles,%coverage);

						# write coverage to mysql import file
						my $Tc = ( $coverage{Tc} ? $coverage{Tc} : 0 );
						my $Fc = ( $coverage{Fc} ? $coverage{Fc} : 0 );
						my $Rc = ( $coverage{Rc} ? $coverage{Rc} : 0 );
						print COVERAGE
						  "$dbpilename\t$chr\t$pos\t$Tc\t$Fc\t$Rc\n";
						foreach my $variant ( keys %alleles ) {
							my $vTc = (
								  $alleles{$variant}{Tc}
								? $alleles{$variant}{Tc}
								: 0
							);
							my $vFc = (
								  $alleles{$variant}{Fc}
								? $alleles{$variant}{Fc}
								: 0
							);
							my $vRc = (
								  $alleles{$variant}{Rc}
								? $alleles{$variant}{Rc}
								: 0
							);
							my $vTq = (
								$alleles{$variant}{Tq}
								? sprintf( "%.2f",
									$alleles{$variant}{Tq} / $vTc )
								: 0
							);
							my $vFq = (
								$alleles{$variant}{Fq}
								? sprintf( "%.2f",
									$alleles{$variant}{Fq} / $vFc )
								: 0
							);
							my $vRq = (
								$alleles{$variant}{Rq}
								? sprintf( "%.2f",
									$alleles{$variant}{Rq} / $vRc )
								: 0
							);
							my $vTmq = (
								$alleles{$variant}{Tmq}
								? sprintf( "%.2f",
									$alleles{$variant}{Tmq} / $vTc )
								: 0
							);
							my $vFmq = (
								$alleles{$variant}{Fmq}
								? sprintf( "%.2f",
									$alleles{$variant}{Fmq} / $vFc )
								: 0
							);
							my $vRmq = (
								$alleles{$variant}{Rmq}
								? sprintf( "%.2f",
									$alleles{$variant}{Rmq} / $vRc )
								: 0
							);
							print VARIANTS
"$dbpilename\t$chr\t$pos\t$variant\t$vTc\t$vFc\t$vRc\t$vTq\t$vFq\t$vRq\t$vTmq\t$vFmq\t$vRmq\n";
						}
					}
				}

				#						print "Skipped number of bases:\t",
				#						  $qual_statistic_skipped{count},
				#						  "\tmean quality: ",
				#						  $qual_statistic_skipped{sum} /
				#						  $qual_statistic_skipped{count}, "\n";
				#						print "Included number of bases:\t",
				#						  $qual_statistic_filtered_all{count},
				#						  "\tmean quality: ",
				#						  $qual_statistic_filtered_all{sum} /
				#						  $qual_statistic_filtered_all{count}, "\n";
				#						print "Number of reference bases:\t",
				#						  $qual_statistic_ref{count},
				#						  "\tmean quality: ",
				#						  $qual_statistic_ref{sum} / $qual_statistic_ref{count},
				#						  "\n";
				#						print "Number of variant bases:\t",
				#						  $qual_statistic_var{count},
				#						  "\tmean quality: ",
				#						  $qual_statistic_var{sum} / $qual_statistic_var{count},
				#						  "\n";
				#						print "Number of indel bases:\t",
				#						  $qual_statistic_indel{count},
				#						  "\tmean quality: ",
				#						  $qual_statistic_indel{sum} /
				#						  $qual_statistic_indel{count}, "\n";
				#						print "Skipped number of bases:\t",
				#						  $map_qual_statistic_skipped{count},
				#						  "\tmean map_quality: ",
				#						  $map_qual_statistic_skipped{sum} /
				#						  $map_qual_statistic_skipped{count}, "\n";
				#						print "Included number of bases:\t",
				#						  $map_qual_statistic_filtered_all{count},
				#						  "\tmean map_quality: ",
				#						  $map_qual_statistic_filtered_all{sum} /
				#						  $map_qual_statistic_filtered_all{count}, "\n";
				#						print "Number of reference bases:\t",
				#						  $map_qual_statistic_ref{count},
				#						  "\tmean map_quality: ",
				#						  $map_qual_statistic_ref{sum} /
				#						  $map_qual_statistic_ref{count}, "\n";
				#						print "Number of variant bases:\t",
				#						  $map_qual_statistic_var{count},
				#						  "\tmean map_quality: ",
				#						  $map_qual_statistic_var{sum} /
				#						  $map_qual_statistic_var{count}, "\n";
				#						print "Number of indel bases:\t",
				#						  $map_qual_statistic_indel{count},
				#						  "\tmean map_quality: ",
				#						  $map_qual_statistic_indel{sum} /
				#						  $map_qual_statistic_indel{count}, "\n";
				#
				#						foreach ( sort { $a <=> $b } keys %qual_by_pos ) {
				#							print "$_\t";
				#						}
				#						print "\n";
				#						foreach ( sort { $a <=> $b } keys %qual_by_pos ) {
				#							printf( "%.1f",
				#								$qual_by_pos{$_}{sum} /
				#								  $qual_by_pos{$_}{count} );
				#							print "\t";
				#						}
				#						print "\n";
			}
		);
	}
}

# import indatabase

$Fork->schedule(
	label        => "load_database",
	run_after    => ["extract_variants"],
	run_on_start => sub {

		open( COV, "+>>/var/tmp/coverage.tmp" ) || die("Cannot Open File");

		foreach (@cov_tmp_files) {
			my $filename = $_;
			open( TEMP, "$filename" ) || die("Cannot Open File $filename\n");

			# concatenate all files
			while (<TEMP>) {
				print COV $_;
			}
			close(TEMP);
			unlink($filename);
		}

		close(COV);

		system(
"mysql -u mirnaseq -pmirnaseq -e \"ALTER TABLE coverage DISABLE KEYS; LOAD DATA INFILE '/var/tmp/coverage.tmp' INTO TABLE coverage\" mirnaseq &"
		);

		# re-enable the mysql keys
		system(
"mysql -u mirnaseq -pmirnaseq -e \"ALTER TABLE coverage ENABLE KEYS;\" mirnaseq &"
		);

		#unlink("/var/tmp/coverage.tmp");
	}
);

$Fork->schedule(
	label        => "load_database",
	run_after    => ["extract_variants"],
	run_on_start => sub {

		open( VAR, "+>>/var/tmp/variants.tmp" ) || die("Cannot Open File");

		foreach (@var_tmp_files) {
			my $filename = $_;
			open( TEMP, "$filename" ) || die("Cannot Open File $filename\n");

			# concatenate all files
			while (<TEMP>) {
				print VAR $_;
			}
			close(TEMP);
			unlink($filename);
		}

		close(VAR);

		system(
"mysql -u mirnaseq -pmirnaseq -e \"ALTER TABLE variants DISABLE KEYS; LOAD DATA INFILE '/var/tmp/variants.tmp' INTO TABLE variants\" mirnaseq &"
		);

		# re-enable the mysql keys
		system(
"mysql -u mirnaseq -pmirnaseq -e \"ALTER TABLE variants ENABLE KEYS;\" mirnaseq &"
		);

		#unlink("/var/tmp/variants.tmp");

	}
);

# set all forks as ready
$Fork->ready_all;

# run the ready forks
$Fork->poll;

#wait for the forks to finish
$Fork->wait_all();

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

=item B<-d --database>	[required] the name of the database to import the reads and variants into

=item B<-b --bam>		[required] the sorted bam file to process of a directory containing sorted bam files

=item B<-t --temp>		The directory to use as a temporary directory

=item B<-g --genome>	[required] The fasta file for the genome the reads where mapped on

=item B<--mapqual>	The minimal mapping quality for the read of a variant to be inserted into the database

=item B<--basequal>	The minimal base quality score for a variant to be inserted into the database

=item B<--regions -r>	a file containing the regions of interest in a <name>\t<chromosome>\t‹<start>\t<stop>
format WARNING: regions should be non overlapping!!!

=item B<--ignore_start>	Ignore this manny bases from the start of an alignment

=item B<--ignore_end>	Ignore this manny bases from the end of an alignment

=item B<--min_cov>		The minimal coverage at any givven base befor it will be considered for variatn calling

=back

=head1 DESCRIPTION

B<extract_variants_pooled> will process data from a (list of) bam file(s) extract the variants and the coverage, and insert this information into a database.

=cut
