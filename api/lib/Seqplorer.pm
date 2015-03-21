package Seqplorer;
use Mojo::Base 'Mojolicious';
use strict;
use Data::Dumper;
use feature "state";
use utf8;
use Mango;
use Seqplorer::Model;

# This method will run once at server start
sub startup {
  my $self = shift;
  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer');
  $self->secrets(['a31e1943e20fdf6a0c73aee6fd7b49b36ccd3edf']);
	$ENV{MOJO_REVERSE_PROXY} = 1;
	# Connect to mongo
	#my $mongo_uri = 'mongodb://localhost/nxtvat';
	#$self->helper(mango => sub { state $mango = Mango->new($mongo_uri) });
	$self->helper(cache => sub { state $cache = Mojo::Cache->new });
	# Init Seqplorer Model for db interaction
	my $model=Seqplorer::Model->new( app => $self, mongoDB => Mango->new('mongodb://localhost/nxtvat?readPreference=secondaryPreferred') );
	$self->helper(model => sub { $model->model($_[1]) });
	$self->helper(db => sub { $model->db() });
	$self->hook( before_dispatch => sub {
	               my $self = shift;
	               # notice: url must be fully-qualified or absolute, ending in '/' matters.
	               $self->req->url->base(Mojo::URL->new(q{http://localhost/~tomsante/seqplorer/api/}));
	});
	# Routes
	my $r = $self->routes;
	$r->namespaces(['Seqplorer::Controller']);
	# $r->route('/qsub/:jobid', jobid => qr/\d+/ )->via('GET')->to('qsub#get'); TODO
	$r->post('/qsub')->to('qsub#submit');
	$r->route('/query/:collection')->to('query#submit');
	$r->get('/view/:viewid')->to('view#get');
	$r->post('/view/:viewid')->to('view#edit');
	$r->post('/view/name/:viewid')->to('view#editname');
	$r->post('/view')->to('view#create');
	$r->route('/md5')->via('POST')->to('tools#md5sum');
	$r->get('/filter/:filterid')->to('filter#get');
	$r->post('/filter/:filterid')->to('filter#edit');
	$r->post('/filter/name/:filterid')->to('filter#editname');
	$r->post('/filter')->to('filter#edit');
	
	
}

1;
