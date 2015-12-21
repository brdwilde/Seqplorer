package Seqplorer::Controller::Group;
use Mojo::Base 'Mojolicious::Controller';
use strict;

sub get {
	my $self = shift;
	$self->app->log->debug("Controller: get group info");
	my $userId = $self->stash('userid');

	my $groupModel = $self->model('group');
	my $groupReturn = $groupModel->getid($userId);

	$self->render( json => $groupReturn );
}

1;