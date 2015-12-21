package Seqplorer::Controller::Proxy;
use Mojo::Base 'Mojolicious::Controller';
use Mojolicious::Plugin::Proxy;
use strict;

sub redirect {
	my $self = shift;
	my $direction = $self->stash('direction');
	my $config = $self->app->config;
	my $url = $config->{site}->{$direction};
	$self->app->log->debug("Redirecting to $url");
	$self->proxy_to($url);
}
1;