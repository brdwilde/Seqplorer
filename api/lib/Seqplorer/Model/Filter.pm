package Seqplorer::Model::Filter;
use strict;
use warnings;
use Carp qw/croak/;
#use base qw/Mojo::Base/;
use Mojo::Base -base;
#use Mojo::Base;
use Mojo::Util qw(encode md5_sum);
use List::Util qw(first);
use Mango::BSON ':bson';
use Scalar::Util qw(looks_like_number);


has [qw/ app mongoDB /];

sub get {
    my $self = shift;
		my $config = shift;
		my $filterCollection = $self->mongoDB->db->collection('adv_filter');
		my $filterId = $config->{'_id'};
		#my $cache = $self->app->cache;
		#if( defined $cache->get($viewId) ){
		#	$self->app->log->debug("Cache hit for get view: $viewId");
		#	return $cache->get($viewId);
		#}
		#$self->app->log->debug("Cache miss for get view: $viewId");
		my $filterID_OID = ( $filterId =~ /^[0-9a-fA-F]{24}$/ ) ? Mango::BSON::ObjectID->new($filterId) : { '_id' => $filterId };
		$self->app->log->debug("Get filter from mongo: $filterId = $filterID_OID => ".ref($filterID_OID));
		my $filterDoc = $filterCollection->find_one($filterID_OID);
		#$cache->set($viewId, \%viewReturn);
		#if( defined $cache->get($viewId) ){
		#	$self->app->log->debug("Cache saved for get view: $viewId ");
		#}
		return $filterDoc;
}

sub save {
  my $self = shift;
	my $data = shift;
	my $filterCollection = $self->mongoDB->db->collection('adv_filter');
	my $filterDoc = {} ;
	if( defined $data->{'_id'} ){
		$filterDoc->{'_id'} = $data->{'_id'};
		$filterDoc = $self->get({'_id' => $data->{'_id'}});
		#my $filterID_OID = Mango::BSON::ObjectID->new($data->{'_id'});
		#$filterDoc->{'_id'} = $filterID_OID;
	}
	if(defined $data->{'_id'}){
		$filterDoc->{'_id'} = $data->{'_id'};
	}
	if(defined $data->{'name'}){
		$filterDoc->{'name'} = $data->{'name'};
	}
	if(defined $data->{'filter'}){
		$filterDoc->{'filter'} = $data->{'filter'};
	}
	if(defined $data->{'name'}){
		$filterDoc->{'name'} = $data->{'name'};
	}
	if(defined $data->{'projects'}){
		$filterDoc->{'projects'} = $data->{'projects'};
	}
	if(defined $data->{'where'}){
		$filterDoc->{'where'} = $data->{'where'};
	}
	my $filterDocId = $filterCollection->save($filterDoc);
	$self->app->log->debug("Edit: Saved filter doc to mongo: ".$filterDocId);
	return $filterDocId;
}

sub editKey {
  my $self = shift;
	my $id = shift;
	my $key = shift;
	my $value = shift;
	my $filterCollection = $self->mongoDB->db->collection('adv_filter');
	my $filterDocId = $filterCollection->update({'_id' => $id},{ $key => $value });
	$self->app->log->debug("Edit: filter doc $key key: ".$filterDocId);
	return $filterDocId;
}

sub delete {
    my $self = shift;
    #placeholder
}

1;
__END__