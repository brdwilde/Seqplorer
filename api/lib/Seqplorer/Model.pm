package Seqplorer::Model;
use strict;
use warnings;
use Carp qw/croak/;
use Mango;
#use Mango::BSON ':bson';
use utf8;
use Mojo::Loader;
use Mojo::Base -base;

#has modules => sub { {} };
#has db => sub { {} };
#
#sub new {
#	my $class = shift;
#	my $self = {};#{ 'db' => sub { {} } };
#	bless($self, $class);
#	$self->init(@_);
#	return $self;
#}
#
#sub init {
#	my ($self, $mongo_uri) = @_;
#	croak "No mongo uri was passed!" unless $mongo_uri;
#	$self->db = Mango->new($mongo_uri) unless( $self->db );
#	# Reloadable Model
#	#my $modules = Mojo::Loader->search('Seqplorer::Model');
#	#for my $module (@$modules) {
#	#    Mojo::Loader->load($module);
#	#		#print $module."\n";
#	#}
#	foreach my $pm ( @{Mojo::Loader->search('Seqplorer::Model')} ) {
#		my $e = Mojo::Loader->load($pm);
#		croak "Loading `$pm' failed: $e" if ref $e;
#		my ($basename) = $pm =~ /.*::(.*)/;
#		#$self->app->log->debug("Loaded model: ".lc $basename);
#		$self->modules->{lc $basename} = $pm->new( 'db' => $self->db );
#	}
#
#return $self;
#}

#sub model {
#    my ($self, $model) = @_;
#    return $self->{modules}{$model} || croak "Unknown model `$model'";
#}

#sub db {
#	my $self = shift;
#	return $self->{'_db'} if defined $self->{'_db'};
#	croak "You should init the Mango/Mongo connection!";
#}

#1;


has modules => sub { {} };
has 'mongoDB';

sub new {
    my $class = shift;
    my %args = @_;
    my $self = $class->SUPER::new(@_);

    foreach my $pm (grep { $_ ne 'Seqplorer::Model::Base' } @{Mojo::Loader->search('Seqplorer::Model')}) {
        my $e = Mojo::Loader->load($pm);
        croak "Loading `$pm' failed: $e" if ref $e;
        my ($basename) = $pm =~ /.*::(.*)/;
        $self->modules->{lc $basename} = $pm->new(%args);
    }
    return $self;
}

# Get a model object by name
sub model {
    my ($self, $model) = @_;
    return $self->{modules}{$model} || croak "Unknown model `$model'";
}

# Get a schema object by name
#sub schema {
#    my ($self, $schema) = @_;
#    return $self->root_schema->schema($schema) || croak "Unknown schema `$schema'";
#}

# Return why the last schema call failed
#sub schema_err { shift->root_schema->error }

# Return a list of avaialable model names
# Probably only for test code
sub models { return grep { $_ ne '' } keys %{$_[0]->{modules}} }

1;

