package Seqplorer::Controller::View;
use Mojo::Base 'Mojolicious::Controller';
use strict;

# This action will render a template
sub get {
	my $self = shift;
	my $viewId = $self->stash('viewid');
	if($viewId eq "variants" || $viewId eq "samples" || $viewId eq "projects"){
		$self->render(template => "view/".$viewId, format => 'json');
	} else {
		$self->app->log->debug("Controller: get view ".$viewId);
		my $viewModel = $self->model('view');
		my $viewReturn = $viewModel->get({'_id' => $viewId});
		$self->render( json => $viewReturn );		
	}
}

sub create {
	my $self = shift;
	#my $viewId = $self->stash('viewid');
	$self->app->log->debug("Controller: save new view");
	my $parsedJSON=$self->req->json;
	unless(defined $parsedJSON->{'columns'} &&  defined $parsedJSON->{'collection'} && defined $parsedJSON->{'projects'} && defined $parsedJSON->{'restrict'} && defined $parsedJSON->{'dom'} && defined $parsedJSON->{'name'} ){
		$self->app->log->debug("Controller: save new view failed, missing values");
		$self->render( json => { 'failureNoticeHtml' => '<p>Needed values were not defined. Please try again.</p>'} );
		return;
	}
	my $viewData={};
	if(defined $parsedJSON->{'name'}){
		$viewData->{'name'} = $parsedJSON->{'name'};
	}else{
		$viewData->{'name'} = 'NO NAME';
	}
	my $viewModel = $self->model('view');
	my $viewId = $viewModel->edit({
		'columns' => $parsedJSON->{'columns'},
		'collection' => $parsedJSON->{'collection'},
		'projects' => $parsedJSON->{'projects'},
		'restrict' => $parsedJSON->{'restrict'},
		'dom' => $parsedJSON->{'dom'},
		'name' => $viewData->{'name'}
	});
	#my $viewId = $viewSaveReturn->{'_id'};
	$self->app->log->debug("Controller: new view with id = ".$viewId);
	my $viewReturn = $viewModel->get({'_id' => $viewId});
	$self->render( json => $viewReturn );
}
sub edit {
	my $self = shift;
	my $viewId = $self->stash('viewid');
	$self->app->log->debug("Controller: edit view");
	my $parsedJSON=$self->req->json;
	$self->app->log->debug($parsedJSON);
	unless(defined $parsedJSON->{'columns'} &&  defined $parsedJSON->{'collection'} && defined $parsedJSON->{'projects'} && defined $parsedJSON->{'restrict'} && defined $parsedJSON->{'dom'} && defined $parsedJSON->{'name'} ){
		$self->app->log->debug("Controller: edit view failed, missing values");
		$self->render( json => { 'failureNoticeHtml' => '<p>Needed values were not defined. Please try again.</p>'} );
		return;
	}
	my $viewData={};
	if(defined $parsedJSON->{'name'}){
		$viewData->{'name'} = $parsedJSON->{'name'};
	}else{
		$viewData->{'name'} = 'NO NAME';
	}
	my $viewModel = $self->model('view');
	my $viewSaveReturn = $viewModel->edit({
		'_id' => $viewId,
		'columns' => $parsedJSON->{'columns'},
		'collection' => $parsedJSON->{'collection'},
		'projects' => $parsedJSON->{'projects'},
		'restrict' => $parsedJSON->{'restrict'},
		'dom' => $parsedJSON->{'dom'},
		'name' => $viewData->{'name'}
	});
	my $viewReturn = $viewModel->get({'_id' => $viewId});
	$self->render( json => $viewReturn );
}

sub editname {
	my $self = shift;
	my $viewId = $self->stash('viewid');
	$self->app->log->debug("Controller: edit view name");
	my $parsedJSON=$self->req->json;
	unless(defined $parsedJSON->{'name'} ){
		$self->app->log->debug("Controller: edit view failed, missing name value");
		$self->render( json => { 'failureNoticeHtml' => '<p>Needed name value was not defined. Please try again.</p>'} );
		return;
	}
	my $viewModel = $self->model('view');
	$viewId = $viewModel->editKey($self->stash('viewid'),'name',$parsedJSON->{'name'});
	$self->app->log->debug("Controller: edit name in view = ".$viewId);
	my $viewReturn = $viewModel->get({'_id' => $viewId});
	$self->render( json => $viewReturn );
}
1;