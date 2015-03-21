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

# get the version of the script for logging
my $svn_version = &script_version();

my $current_time = DateTime->now( time_zone => 'floating' );
my $host = hostname;

# get the configurations specified in the config file
my $config   = XMLin('config.xml');
my $samtools = $config->{executables}->{samtools};
my $picard   = $config->{executables}->{picard};
my $bwa      = $config->{executables}->{bwa};
my $bowtie   = $config->{executables}->{bowtie};
#...


#default settings
my $man     = 0;
my $help    = 0;
my $version = 0;
my $quiet   = 0;
my $procs   = 0;

pod2usage("$0: No arguments specified.") if ( @ARGV == 0 );
GetOptions(
	'help|?'    => \$help,
	man         => \$man,
	'version|v' => \$version,
	'quiet|q'   => \$quiet,
	'procs|p'   => \$procs
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

die "$0, $svn_version.\n" if $version;

# check command line arguments
# check file for existence, dir for writability...

##---
## Display general run information
##---
print(
	"###################\n", "# template.pl #\n",
	"###################\n", "#\n#\t$svn_version\n",
	"#\tHost: $host\n",      "#\tRuntime: $current_time\n",
	"#\tProcess id: $$\n",   "#\n###################\n\n",
) unless $quiet;

##---
## Display relevant command line params
##---

# we love forking!
# this is the easy way of doing it

# set the sigterm reaction for the script and the children in case we want to fork
my $Fork = new Parallel::Forker( use_sig_child => 1 );
$SIG{CHLD} = sub { Parallel::Forker::sig_child($Fork); };
$SIG{TERM} = sub {
	$Fork->kill_tree_all('TERM') if $Fork && $Fork->in_parent;
	die "Quitting...\n";
};
$Fork->max_proc($procs);

my @fastq;

foreach (@fastq) {
	$Fork->schedule(
		label        => "label",
		run_on_start => sub {
			print "Fork is runing with pid: $$\n";
		}
	);
}

# set all forks as ready
$Fork->ready_all;

# run the ready forks
$Fork->poll;

#wait for the forks to finish
$Fork->wait_all();

__END__

=head1 NAME

template.pl - A script template

=head1 SYNOPSIS

template.pl [options]

Use -? to see options

=head1 OPTIONS

=over 8

=item B<-h -? --help>	Print a brief help message and exits.

=item B<-m --man>		Displays the manual page.

=item B<-v --version>	Displays the version of the script.

=item B<-q --quiet>		Quiet, supress all output.

=item B<-p --procs>		Number of processes to use.

=back

=head1 DESCRIPTION

B<template> a script template

=cut
