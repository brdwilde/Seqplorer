package Seqplorer::Controller::User;
use Mojo::Base 'Mojolicious::Controller';
use strict;

# This action will render a template
sub login {
	my $self = shift;
	$self->app->log->debug("Controller: login form");
	
	$self->render();
}

# This action will render a template
sub register {
	my $self = shift;
	$self->app->log->debug("Controller: Register form");
	
	$self->render();
}

# This action will render a template
sub forgot {
	my $self = shift;
	$self->app->log->debug("Controller: Forgot form");
	
	$self->render();
}

# This action will render a template
sub add_project {
	my $self = shift;
	$self->app->log->debug("Controller: Add project form");
	
	$self->render();
}

# This action will render a template
sub add_sample {
	my $self = shift;
	$self->app->log->debug("Controller: Add sample form");
	
	$self->render();
}

# This action will render a template
sub map_reads {
	my $self = shift;
	$self->app->log->debug("Controller: Map reads form");
	
	$self->render();
}

# This action will render a template
sub cal_variants {
	my $self = shift;
	$self->app->log->debug("Controller: Call variants form");
	
	$self->render();
}

# This action will render a template
sub start_igv {
	my $self = shift;
	$self->app->log->debug("Controller: Add sample form");
	
	$self->render();
}

1;