package Seqplorer::Controller::Filter;
use Mojo::Base 'Mojolicious::Controller';
use strict;

sub get {
	my $self = shift;
	$self->app->log->debug("Controller: get filter");
	my $filterId = $self->stash('filterid');
	my $filterModel = $self->model('filter');
	my $filterReturn = $filterModel->get({'_id' => $filterId});
	$self->render( json => $filterReturn );
}

sub edit {
	my $self = shift;
	$self->app->log->debug("Controller: save new filter");
	my $parsedJSON=$self->req->json;
	unless(defined $parsedJSON->{'filter'} &&  defined $parsedJSON->{'projects'} &&  defined $parsedJSON->{'where'} ){
		$self->app->log->debug("Controller: save new filter failed, no filter, projects or where defined");
		$self->render( json => { 'failureNoticeHtml' => '<p>Needed values were not defined. Please try again.</p>'} );
		return;
	}
	my $filterModel = $self->model('filter');
	my $filterData={};
	$filterData->{'filter'}=$parsedJSON->{'filter'};
	$filterData->{'projects'}=$parsedJSON->{'projects'};
	$filterData->{'where'}=$parsedJSON->{'where'};
	if(defined $parsedJSON->{'_id'}){
		$filterData->{'_id'} = $parsedJSON->{'_id'};
	}
	if(defined $parsedJSON->{'name'}){
		$filterData->{'name'} = $parsedJSON->{'name'};
	}else{
		$filterData->{'name'} = 'NO NAME';
	}
	my $filterId = $filterModel->save($filterData);
	#my $viewId = $viewSaveReturn->{'_id'};
	$self->app->log->debug("Controller: new filter with id = ".$filterId);
	my $filterReturn = $filterModel->get({'_id' => $filterId});
	$self->render( json => $filterReturn );
}
sub editname {
	my $self = shift;
	$self->app->log->debug("Controller: edit filter name");
	my $parsedJSON=$self->req->json;
	unless(defined $self->stash('filterid') && defined $parsedJSON->{'name'} ){
		$self->app->log->debug("Controller: edit name failed, name not defined");
		$self->render( json => { 'failureNoticeHtml' => '<p>Edit name failed, name not defined</p>'} );
		return;
	}
	my $filterModel = $self->model('filter');
	my $filterId = $filterModel->editKey($self->stash('filterid'),'name',$parsedJSON->{'name'});
	#my $viewId = $viewSaveReturn->{'_id'};
	$self->app->log->debug("Controller: edit name in filter = ".$filterId);
	my $filterReturn = $filterModel->get({'_id' => $filterId});
	$self->render( json => $filterReturn );
}
1;