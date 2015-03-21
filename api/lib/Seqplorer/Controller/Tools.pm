package Seqplorer::Controller::Tools;
use Mojo::Base 'Mojolicious::Controller';
use strict;

# This action will render a template
sub md5sum{
	my $self = shift;
	$self->app->log->debug("Controller: get md5sum ");
	my $viewModel = $self->model('query');
	my $toDigest=$self->req->json;
	unless( defined $toDigest->{'where'} && defined $toDigest->{'collection'}){
		$self->app->log->error('md5sum needs a where and collection parameter in the posted value');
		$self->render( json => { 'error' => 'md5 needs a where and collection parameter in the posted value' } );
	}
	my $viewReturn = $viewModel->md5Key($toDigest->{'where'}, $toDigest->{'collection'});
	$self->app->log->debug('md5sum generated for '.$toDigest->{'collection'}.' => '.$viewReturn);
	$self->render( json => { 'md5' => $viewReturn } );
}
1;