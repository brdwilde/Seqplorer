package Seqplorer::Controller::Site;
use Mojo::Base 'Mojolicious::Controller';
use strict;

sub public {
	my $self = shift;

	# get configuration info
	my $config = $self->app->config;

	# default role is guest, unless another role is set...
	$self->session(role => ['guest']) unless ($self->session('role'));

	# add some variables we will be needing for page rendering
	$self->stash(shiny_url => $config->{site}->{shiny});
	$self->stash(qsub_url => $config->{site}->{qsub});

	$self->stash(role     => $self->session('role'));

	$self->app->log->debug("Serving main page");
	$self->render(); # renders template site/public.html.ep
}

sub table {
	my $self = shift;
	my $viewId = $self->stash('tableid');

	my $viewModel = $self->model('view');
	my $viewReturn = $viewModel->get({'_id' => $viewId});

	$self->stash( table => $viewReturn->{view} );
	$self->stash( columns => $viewReturn->{columns} );

	$self->app->log->debug("Rendering table");
	$self->render(); # renders template site/public.html.ep
}
1;