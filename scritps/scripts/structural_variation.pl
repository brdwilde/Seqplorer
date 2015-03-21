#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use DateTime;
use Sys::Hostname;
use Getopt::Long;
use Pod::Usage;
use FindBin;
use lib $FindBin::Bin;
use lib::functions;

# get the version of the script for logging
my $svn_version = &script_version();

my $current_time = DateTime->now( time_zone => 'floating' );
my $host = hostname;

#default settings
my $man     = 0;
my $help    = 0;
my $version = 0;
my $quiet   = 0;
my @steps;
my $input = '';
my $genome = '';
my $outdir = 'output/';

pod2usage("$0: No arguments specified.") if ( @ARGV == 0 );
GetOptions(
	   'help|?'    => \$help,
	   man         => \$man,
	   'version|v' => \$version,
	   'quiet|q'   => \$quiet,
	   'steps:s{,}' => \@steps,
	   'input|i=s' => \$input,
	   'genome|g=s' => \$genome,
	   'outdir|o=s' => \$outdir,
	  ) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

die "$0, $svn_version.\n" if $version;

# check command line arguments
# check file for existence, dir for writability...

# Steps
if ( @steps < 1 ){
  @steps = ('aln_1','sort_index_1','flt_1','aln_2','sort_index_2');
}

# Genome
my $genomename;
my $genomepath;
( $genomename, $genomepath, my $genomeext ) = fileparse( $genome, '\..*' );

# Output
if (! -d $outdir ) {
    print "#\t Error: Output dir does not exist\n";
    exit;
}
$outdir = $outdir . "/" unless ( $outdir =~ /\/$/ );

# Input
( my $fastqname, my $dir, my $ext ) = fileparse( $input, '\..*' );

##---
## Display general run information
##---
print(
	"########################\n", "# Structural variation #\n",
	"########################\n", "#\n#\t$svn_version\n",
	"#\tHost: $host\n",      "#\tRuntime: $current_time\n",
	"#\tProcess id: $$\n",   "#\n########################\n#\n",
) unless $quiet;

##---
## Display relevant command line params
##---
print "#\tInput: $input\n";
print "#\tSteps: ".join(',',@steps)."\n";

foreach (@steps){

    if($_ eq 'aln_1'){
	print "#\tStarting: $_\n";
	system("/opt/bin/bwa-0.5.8a aln -t 14  $genomepath$genomename $input > ${outdir}${fastqname}.tier1.1.sai");
	system("/opt/bin/bwa-0.5.8a aln -t 14  $genomepath$genomename $dir${fastqname}_2$ext > ${outdir}${fastqname}.tier1.2.sai");
	system("/opt/bin/bwa-0.5.8a sampe $genomepath$genomename ${outdir}${fastqname}.tier1.1.sai ${outdir}${fastqname}.tier1.2.sai $input $dir${fastqname}_2$ext | samtools-0.1.8 view -bhS - -o ${outdir}${fastqname}.tier1.bam");
    }elsif($_ eq 'sort_index_1'){
	print "#\tStarting: $_\n";
	system("samtools-0.1.8 sort $outdir$fastqname.tier1.bam $outdir$fastqname.tier1-sorted");
	system("samtools-0.1.8 index $outdir$fastqname.tier1-sorted.bam");
    }elsif($_ eq 'flt_1'){
	print "#\tStarting: $_\n";
	my $input_bam = $outdir.$fastqname.'.tier1-sorted.bam';
	system( "samtools view -bF 0x2 $input_bam | /store/sequencing/svergult/analysis/scripts/Hydra-Version-0.5.3/bin/bamToFastq -bam stdin -fq1 $outdir${fastqname}.tier1.disc.1.fq -fq2 $outdir${fastqname}.tier1.disc.2.fq" );
    }elsif($_ eq 'aln_2'){
	print "#\tStarting: $_\n";
	if(! -e $outdir.$fastqname.'.tier1.disc.1.fq' || ! -e $outdir.$fastqname.'.tier1.disc.2.fq'){
	    print "#\t Error: can't run alignment for tier 2 if tier 1 isn't done\n";
	    exit;
	}
	system("/opt/bin/bwa-0.5.8a bwasw -t 14  $genomepath$genomename ${outdir}${fastqname}.tier1.disc.1.fq > ${outdir}${fastqname}.tier2.1.sai");
	system("/opt/bin/bwa-0.5.8a bwasw -t 14  $genomepath$genomename ${outdir}${fastqname}.tier1.disc.2.fq > ${outdir}${fastqname}.tier2.2.sai");
	system("/opt/bin/bwa-0.5.8a sampe $genomepath$genomename ${outdir}${fastqname}.tier2.1.sai ${outdir}${fastqname}.tier2.2.sai ${outdir}${fastqname}.tier1.disc.1.fq ${outdir}${fastqname}.tier1.disc.2.fq | samtools-0.1.8 view -bhS - -o ${outdir}${fastqname}.tier2.bam");
    }elsif($_ eq 'sort_index_2'){
	print "#\tStarting: $_\n";
	system("samtools-0.1.8 sort $outdir$fastqname.tier2.bam $outdir$fastqname.tier2-sorted");
	system("samtools-0.1.8 index $outdir$fastqname.tier2-sorted.bam");
    }
}
# we love forking!
# this is the easy way of doing it
# my @forks;
# my $pid;
# my @fastq;
# for (@fastq) {

# 	$pid = fork();
# 	if ($pid) {

# 		# parent

# 	}
# 	elsif ( $pid == 0 ) {

# 		# child

# 		exit(0);
# 	}
# 	else {
# 		die "couldn't fork : $! \n";
# 	}
# }

# foreach (@forks) {
# 	waitpid( $_, 0 );
# }

__END__

=head1 NAME

structural_variation.pl - A script to analyse structural variation
from paired end read data

=head1 SYNOPSIS

structural_variation.pl [options]

Use -? to see options

=head1 OPTIONS

=over 8

=item B<-h -? --help>	Print a brief help message and exits.

=item B<-m --man>		Displays the manual page.

=item B<-v --version>	Displays the version of the script.

=item B<-q --quiet>		Quiet, supress all output.


=back

=head1 DESCRIPTION

B<template> a script template

=cut
