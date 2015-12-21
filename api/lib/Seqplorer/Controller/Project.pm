package Seqplorer::Controller::Project;
use Mojo::Base 'Mojolicious::Controller';
use strict;

sub get {
	my $self = shift;
	$self->app->log->debug("Controller: get projects for user");
	my $userId = $self->stash('userid');

	my $projectModel = $self->model('project');
	my $projectReturn = $projectModel->get($userId);

	$self->render( json => $projectReturn );
}

sub create {
	my $self = shift;
	$self->app->log->debug("Controller: create user");

	my %user = (
		email => $self->param('email') ? $self->param('email') : "",
		password => $self->param('password') ? $self->param('password') : "",
		firstname => $self->param('firstname') ? $self->param('firstname') : "",
		lastname => $self->param('lastname') ? $self->param('lastname') : "",
		institution => $self->param('institution') ? $self->param('institution') : "",
		departement => $self->param('departement') ? $self->param('departement') : "",
		country => $self->param('country') ? $self->param('country') : ""
	);

	my $projectModel = $self->model('user');
	my $userReturn = $projectModel->create(\%user);

	# set an email with activatioin request
	if ($userReturn->{Success}){
		# get the base url for the site
		my $config = $self->app->config;
		$self->stash(activationurl => $config->{site}->{url}.'/user/activate/'.$userReturn->{userid});

		$self->mail(
			to => $self->param('email'),
		 	template => 'mail/newuser',
	    	format => 'mail',
	    	subject => 'Seqplorer user activation'
	    );

		use Data::Dumper::Simple;
		print Dumper ($self);
	}

	$self->render( json => $userReturn );
}

sub update {
	my $self = shift;
	my $userId = $self->stash('userid');
	$self->app->log->debug("Controller: update user ".$userId);

	my %userdata;
	# get the allowed parameters for the user
	$userdata{email} = $self->param('email') if ($self->param('email'));
	$userdata{password} = $self->param('password') if ($self->param('password'));
	$userdata{firstname} = $self->param('firstname') if ($self->param('firstname'));
	$userdata{lastname} = $self->param('lastname') if ($self->param('lastname'));
	$userdata{institution} = $self->param('institution') if ($self->param('institution'));
	$userdata{departement} = $self->param('departement') if ($self->param('departement'));
	$userdata{country} = $self->param('country') if ($self->param('country'));
	$userdata{role} = ($self->param('role')) if ($self->param('role'));

	my $projectModel = $self->model('user');
	my $userReturn = $projectModel->update($userId,\%userdata);

	$self->render( json => $userReturn );
}

sub delete {
	my $self = shift;
	my $userId = $self->stash('userid');
	$self->app->log->debug("Controller: delete user ".$userId);

	my $projectModel = $self->model('user');
	my $userReturn = $projectModel->delete($userId);

	$self->render( json => $userReturn );
}

1;