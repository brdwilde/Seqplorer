#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use PBS::Client;
use SequencingTools;
use Data::Dumper::Simple;
use MIME::Lite;

# get the command line arguments
my $man         	= 0;
my $help        	= 0;
my $version     	= 0;
my $quiet       	= 0;
my $mongoserver 	= 0;
my $mongoport   	= 0;
my $mongodb     	= 0;
my $config_id   	= 0;
my $vals			= 0;
my $insert_sample	= 0;
my $to_email		= 0;
my $from_email		= 0;
my $subject			= 0;
my $message			= 0;
my $server_config	= 0;
my $analysis_server	= 0;
my $name			= 0;
my $command			= 0;
my $queue			= 0;
my $wallt			= 0;
my $cput			= 0;
my $connection;
my $database;
pod2usage("$0: No arguments specified.") if ( @ARGV == 0 );
my %command_args;
%{ $command_args{arguments} } = (@ARGV);
GetOptions(
	'help|?'     		=> \$help,
	man          		=> \$man,
	'version|v'  		=> \$version,
	'quiet|q'    		=> \$quiet,
	'config=s'  		=> \$config_id,
	'vals=s'			=> \$vals,
#	'sample=s'			=> \$insert_sample,
	'to_email=s' 		=> \$to_email,
	'from_email=s' 		=> \$from_email,
	'subject=s'   		=> \$subject,
#	'message=s'   		=> \$message,
	'server_config=s'   => \$server_config,
	'analysis_server=s'	=> \$analysis_server,
	'name=s'   			=> \$name,
	'command=s'   		=> \$command,
	'queue=s'   		=> \$queue,	
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

# specify default settings here
$mongoserver = "localhost" unless ($mongoserver);
$mongoport   = "27017"     unless ($mongoport);
$mongodb     = "nxtseq"    unless ($mongodb);

#Mongo collections
my %collections = ('variants' => 'variants',
				'users' => 'users',
				'samples' => 'samples',
				'projects'=>'projects',
				'configurations' => 'configurations');

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
#	startlog	 => 0
);

$sequencingtools->{run_config}->{to_email}       	= $to_email       	if ($to_email);
$sequencingtools->{run_config}->{from_email} 		= $from_email 		if ($from_email);
$sequencingtools->{run_config}->{subject}      		= $subject     	 	if ($subject);
$sequencingtools->{run_config}->{message}       	= $message       	if ($message);
$sequencingtools->{run_config}->{server_config}    	= $server_config    if ($server_config);
$sequencingtools->{run_config}->{analysis_server}  	= $analysis_server  if ($analysis_server);
$sequencingtools->{run_config}->{name}       		= $name       		if ($name);
$sequencingtools->{run_config}->{command}        	= $command        	if ($command);
$sequencingtools->{run_config}->{queue}       		= $queue       		if ($queue);


# check arguments
die "use -? to see correct command line arguments\n"
  unless ($config_id );
  
# Change where-clause to dot-notation
my %where;
deep_keys_value($sequencingtools->{run_config}->{where}, sub {
	my $tmp_keys = shift; 
    my @tmp_keys = @{$tmp_keys};
    $where{join('.',@tmp_keys)} = shift;
});

#Connect to mongo
$connection = MongoDB::Connection->new("host" => $mongo_server{host} . ":" . $mongo_server{port} );
$database = $connection->$mongodb;

#Get all variants for given info
my $data_collection=$collections{variants};
my $collection=$database->$data_collection;
my $data=$collection->find(\%where);

#retrieve where query to update variants
my $key;
my $samples;
my $i;
my @samples;
my $variant;
my $id;
while (my $entry = $data->next) {
	$id = $entry->{_id};
	$variant = $entry->{v};
	foreach $samples($entry->{sa}) {
		my $size = (scalar @$samples)-1;
		for $i(0..$size){ 
			if (@$samples[$i]->{id} eq MongoDB::OID->new(value => $vals)){
				$key = $i;
			}
		}
		@samples = @$samples[$key];
		$samples[0]->{'id'} = $sequencingtools->{run_config}->{sample}->{'id'};
		$samples[0]->{'sn'} = $sequencingtools->{run_config}->{sample}->{'name'}; 
	}
}
my $update = $collection->update({"_id" => $id,'v'=>$variant}, {'$addToSet' => {'sa' => $samples[0]}});


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#SUBROUTINES														+
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

sub deep_keys_value
{
    my ($hashref, $code, $args) = @_;

    while (my ($k, $v) = each(%$hashref)) {
        my @newargs = defined($args) ? @$args : ();
        push(@newargs, $k) unless $k =~ m/^[\$]/;
        if (ref($v) eq 'HASH' && $k !~ m/^[\$]/) {
            deep_keys_value($v, $code, \@newargs);
        }
        elsif ($k =~ m/^[\$]/){
            $code->(\@newargs,{$k=>$v});
        }
    }
}


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#MANUAL INFORMATION													+
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

__END__

=head1 NAME
create_unite_sample.pl - Script to create a new sample from two or more samples after filtering

=head1 SYNOPSIS

create_unite_sample.pl [options]

Use -? to see options

=head1 OPTIONS

=over 8

=item B<-h -? --help>	Print a brief help message and exits.

=item B<-m --man>		Displays the manual page.

=item B<-v --version>	Displays the version of the script.

=item B<--config>		A configuration ID to run the script

=item B<-p --procs>		Number of processes to use. [default 14]

=back

=head1 DESCRIPTION

B<export> function:
This function will create a sample from two or more samples after filtering. Variant information will be updated as well.

=cut