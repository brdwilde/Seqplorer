package Seqplorer;
use Mojo::Base 'Mojolicious';
use strict;
use Data::Dumper;
use feature "state";
use utf8;
use Mango;
use Seqplorer::Model;
use Mojolicious::Plugin::JSONConfig;
use Mojolicious::Plugin::Authorization;
use Mojolicious::Plugin::Mail;

# This method will run once at server start
sub startup {
	my $self = shift;

	$self->secrets(['a31e1943e20fdf6a0c73aee6fd7b49b36ccd3edf']);

	# get the confguration file
	my $configfile = '';
 	$configfile = 'seqplorer.json' if ( -e 'seqplorer.json' );
 	$configfile = '../seqplorer.json' if ( -e '../seqplorer.json' );
 	$configfile = '../../seqplorer.json' if ( -e '../../seqplorer.json' );
 	$configfile = '/etc/seqplorer/seqplorer.json' if ( -e '/etc/seqplorer/seqplorer.json' );
	#my $config = plugin JSONConfig => {file => $configfile};

	my $config = $self->plugin('JSONConfig',{
		file => $configfile
	});

	$self->plugin('mail',{
		from => $config->{mailfrom} ? $config->{mailfrom} : '',
    	type => 'text/html',
    	how      => 'sendmail',
  	});

	$self->plugin('Authorization' => {
        'is_role'    => sub { 
				my ($self, $role, $extradata) = @_;
	        	return 1 if ($self->session('role') && grep(/$role/, @{$self->session('role')}));
        		return 0
        	},
        'user_role'  => sub {
        		my ($self,$extradata) = @_;
       			return $self->session('role');
        	},
        'user_privs' => sub {}, # not working with user privileges at this time
        'has_priv'   => sub {} # not working with user privileges at this time
    });
    
	#$self->plugin( 'CSSLoader' );
	
	# Documentation browser under "/perldoc"
	$self->plugin('PODRenderer');
	
	#$ENV{MOJO_REVERSE_PROXY} = 1;

	# Connect to mongo
	$self->helper(cache => sub { state $cache = Mojo::Cache->new });

	# Init Seqplorer Model for db interaction
	my $dbname = $config->{database}->{dbname} ? $config->{database}->{dbname} : "seqplorer";
	my $dbhost = $config->{database}->{host} ? $config->{database}->{host} : "localhost";
	my $dbport = $config->{database}->{port} ? $config->{database}->{port} : "27017";
	my $dbuser = $config->{database}->{user} ? $config->{database}->{user} : undef;
	my $dbpassword = $config->{database}->{password} ? $config->{database}->{password} : undef;
	$dbhost = $dbuser.':'.$dbpassword.'@'.$dbhost if ($dbuser);

	my $model = Seqplorer::Model->new( app => $self, mongoDB => Mango->new('mongodb://'.$dbhost.':'.$dbport.'/'.$dbname.'?readPreference=secondaryPreferred') );
	$self->helper(model => sub { $model->model($_[1]) });
	$self->helper(db => sub { $model->db() });
#	$self->hook( before_dispatch => sub {
#		my $self = shift;
		# notice: url must be fully-qualified or absolute, ending in '/' matters.
#		$self->req->url->base(Mojo::URL->new(q{http://localhost/~tomsante/seqplorer/api/}));
#	});

	# Routes
	my $r = $self->routes;
	$r->namespaces(['Seqplorer::Controller']);

	# default: load the main page
	$r->get('/')->to('site#public');

	#my $auth_r = $r->under('/user/login')->to('user#login');

	# login and out
	$r->get('/logout')->to('user#logout');
	$r->post('/login')->to('user#authenticate');

	# user routes
	# anyone can create or activate a user
	$r->post('/user')->to('user#create');
	$r->post('/user/activate/:userid')->to('user#activate');
	# users can read and update their own info
	$r->get('/user/:userid')->over(is => 'user')->to('user#get');
	$r->post('/user/:userid')->over(is => 'user')->to('user#update');
	# admins can add roles and delete
	$r->post('/user/addrole/:userid')->over(is => 'admin')->to('user#addrole');
	$r->delete('/user/:userid')->over(is => 'admin')->to('user#delete');

	# anyone can get groups either by user id or all public groups
	$r->get('/group')->to('group#get');
	$r->get('/group/:userid')->to('group#get');

	# the forms
	$r->get('/forms/login')->to('forms#login');
	$r->get('/forms/register')->to('forms#register');
	$r->get('/forms/forgot')->to('forms#forgot');
	$r->get('/forms/add_project')->to('forms#add_project');
	$r->get('/forms/add_sample')->to('forms#add_sample');
	$r->get('/forms/jobs_opt')->to('forms#jobs_opt');
	$r->get('/forms/map_reads')->to('forms#map_reads');
	$r->get('/forms/call_variants')->to('forms#call_variants');
	$r->get('/forms/start_igv')->to('forms#start_igv');

	$r->post('/qsub')->over(is => 'user')->to('qsub#submit');
	
	$r->route('/query/:collection')->to('query#submit');
	
	# get update and rename the views
	# anyone can get the views
	$r->get('/view/:viewid')->to('view#get');
	# only valid users can update rename or remove views
	$r->post('/view/:viewid')->over(is => 'user')->to('view#edit');
	$r->post('/view/name/:viewid')->over(is => 'user')->to('view#editname');
	#$r->post('/view')->over(is => 'user')->to('view#create');
	$r->post('/view/create/')->to('view#create');

	# tools
	$r->route('/md5')->via('POST')->to('tools#md5sum');

	# the filters
	$r->get('/filter/:filterid')->over(is => 'user')->to('filter#get');
	$r->post('/filter')->over(is => 'user')->to('filter#edit');
	$r->post('/filter/:filterid')->over(is => 'user')->to('filter#edit');
	$r->post('/filter/name/:filterid')->over(is => 'user')->to('filter#editname');

}

1;