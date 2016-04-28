package Seqplorer::Controller::User;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Util qw(encode md5_sum);
use strict;

sub get {
	my $self = shift;
	$self->app->log->debug("Controller: get user info");
	my $userId = $self->stash('userid');

	my $userModel = $self->model('user');
	my $userReturn = $userModel->get($userId);

	$self->render( json => $userReturn );
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

	my $userModel = $self->model('user');
	my $userReturn = $userModel->create(\%user);

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

	my $userModel = $self->model('user');
	my $userReturn = $userModel->update($userId,\%userdata);

	$self->render( json => $userReturn );
}

sub addrole {
	my $self = shift;
	my $userId = $self->stash('userid');
	my $role = $self->param('role');
	$self->app->log->debug("Controller: adding role ".$role." to user ".$userId);

	my $userModel = $self->model('user');
	my $userReturn = $userModel->addrole($userId,$role);

	$self->render( json => $userReturn );
}

sub revoquerole {
	my $self = shift;
	my $userId = $self->stash('userid');
	$self->app->log->debug("Controller: update user ".$userId);

	my %userdata;
	# get the new role for the user
	$userdata{role} = $self->param('role') if ($self->param('role'));

	my $userModel = $self->model('user');
	my $userReturn = $userModel->update($userId,\%userdata);

	$self->render( json => $userReturn );
}

sub delete {
	my $self = shift;
	my $userId = $self->stash('userid');
	$self->app->log->debug("Controller: delete user ".$userId);

	my $userModel = $self->model('user');
	my $userReturn = $userModel->delete($userId);

	$self->render( json => $userReturn );
}

sub authenticate {
	my $self = shift;
	my $email = uc($self->param('email'));
	my $password = md5_sum($self->param('password'));
	
	my $return = { Success => 0, Message => "Unable to login, please check your credentials"};

	$self->app->log->debug("Authenticating user ".$email." with password ".$password);	

	my $userid;
	if ($email && $password){
		my $userModel = $self->model('user');
		my $userReturn = $userModel->getid($email,$password);

		if ($userReturn->{Success}){
			$userid = $userReturn->{userdata}->{_id}."";
			$self->session(userid => $userid);
			$self->session(role => $userReturn->{userdata}->{role});
			$self->session(email => $userReturn->{userdata}->{email});
			$self->session(firstname => $userReturn->{userdata}->{firstname});
			$self->session(lastname => $userReturn->{userdata}->{lastname});
			$self->session->{groups} = undef;
			$self->session->{samples} = undef;
			$return = { Success => 1, Message => "Logged in user ".$email};

			$self->app->log->debug("Authentication succesfull");	
		}
	}

	# # get the user groups
	# my $groupModel = $self->model('group');
	# my $groupReturn = $groupModel->getid($userid);
	# if ($groupReturn->{Success}){
	# 	$self->session(groups => encode_json($groupReturn->{groupids}));
	# 	$self->app->log->debug("Groups found");
	# }

	
	$self->render( json => $return );
}

sub logout {
	my $self = shift;

	my $user = '';
	$user = $self->session('email') if $self->session('email');

	$self->session(expires => 1);

	$self->app->log->debug("Controller: logged out user ".$user);

	$self->redirect_to('/');
}

sub activate {
	my $self = shift;
	my $userId = $self->stash('userid');
	$self->app->log->debug("Controller: activating user ".$userId);
	my $userModel = $self->model('user');
	my $userReturn = $userModel->activate($userId);

	if ($userReturn->{Success}){
		$self->redirect_to('/');
	} else {
		$self->render( json => $userReturn );
	}
}


1;