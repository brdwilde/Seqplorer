package Seqplorer::Model::View;
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
		my $viewCollection = $self->mongoDB->db->collection('views');
		my $viewId = $config->{'_id'};
		if($viewId eq "variants"){
			$viewId = "50d1def9721c5a2c32000000";
		}elsif($viewId eq "samples"){
			$viewId = "50d1df0a721c5a1d31000000";
		}elsif($viewId eq "projects"){
			$viewId = "50d1df83721c5a0f33000000";
		}
		my $cache = $self->app->cache;
		if( defined $cache->get($viewId) ){
			$self->app->log->debug("Cache hit for get view: $viewId");
			return $cache->get($viewId);
		}
		$self->app->log->debug("Cache miss for get view: $viewId");
		my $viewID_OID = ( $viewId =~ /^[0-9a-fA-F]{24}$/ ) ? Mango::BSON::ObjectID->new($viewId) : { '_id' => $viewId };
		$self->app->log->debug("Get view from mongo: $viewId = $viewID_OID => ".ref($viewID_OID));
		my $viewDoc = $viewCollection->find_one($viewID_OID);
		#$self->app->log->debug("na find_one");
		my %viewReturn;
		$viewReturn{'columns'}=();
		$viewReturn{'_id'}=$viewDoc->{'_id'};
		$viewReturn{'view'}=$viewDoc->{'_id'};
		$viewReturn{'dom'}=$viewDoc->{'dom'};
		$viewReturn{'restrict'}=$viewDoc->{'restrict'};
		my $collection = $viewDoc->{'collection'};
		$viewReturn{'collection'}=$collection;
		$viewReturn{'fields'}=();
		$viewReturn{'mongoid'}=();
		use Data::Dumper;
		#$self->app->log->debug("voor collection_names ".Dumper($self->mongoDB->db->collection_names));
		#my $existsUnique = grep { /${collection}_unique'/ } @{$self->mongoDB->db->collection_names};
		my $existsUnique=1;
		for my $column (@{$viewDoc->{'columns'}}) {
			#$self->app->log->debug("viewDoc is: ".Dumper($column	));
			#create dot notation from queryname
			if(defined $column->{'queryname'}){
				$column->{'dotnotation'} = join('.',@{$column->{'queryname'}});
			}
			#hash: key dotnotation to valus: queryname (query array)
			#->unused in frontend
			$viewReturn{'queryarray'}{$column->{'dotnotation'}}=$column->{'queryname'} if defined $column->{'dotnotation'};
			#create array of dotnotation names of all cols
			#->unused in frontend
			push @{$viewReturn{'fields'}}, $column->{'dotnotation'} if defined $column->{'dotnotation'};
			#add extra info from _unique collection
			if($existsUnique  > 0 && defined $column->{'dotnotation'}){
				my $uniqueDoc = $self->mongoDB->db->collection($collection.'_unique_tmp')->find_one({'_id' => $column->{'dotnotation'} });
				if(defined $uniqueDoc){
					$column->{'searchtype'}=$uniqueDoc->{'type'};
					if(defined $uniqueDoc->{'values'} && scalar(@{$uniqueDoc->{'values'}}) > 1 ){
						$column->{'list'}=$uniqueDoc->{'values'};
					}
					if($uniqueDoc->{'type'} eq 'mongo_id'){
						push @{$viewReturn{'mongoid'}}, $uniqueDoc->{'querykeys'};
					}
					
				}
			}
			push @{$viewReturn{'columns'}}, $column;
		}
		if(!defined $viewReturn{'mongoid'} ){
			$viewReturn{'mongoid'}=$viewDoc->{'mongoid'}
		}
		$cache->set($viewId, \%viewReturn);
		if( defined $cache->get($viewId) ){
			$self->app->log->debug("Cache saved for get view: $viewId ");
		}
		return \%viewReturn;
}

sub edit {
  my $self = shift;
	my $data = shift;
	my $viewCollection = $self->mongoDB->db->collection('views');
	my $viewDoc = {} ;
	if( defined $data->{'_id'} ){
		$viewDoc->{'_id'} = $data->{'_id'};
		my $viewID_OID = Mango::BSON::ObjectID->new($viewDoc->{'_id'});
		$self->app->log->debug("Edit: Get view doc from mongo: ".$viewDoc->{'_id'}." = $viewID_OID => ".ref($viewID_OID));
		$viewDoc = $viewCollection->find_one($viewID_OID);
	}
	$viewDoc->{'columns'}=$data->{'columns'};
	$viewDoc->{'dom'}=$data->{'dom'};
	$viewDoc->{'restrict'}=$data->{'restrict'};
	$viewDoc->{'collection'}=$data->{'collection'};
	$viewDoc->{'projects'}=$data->{'projects'};
	$viewDoc->{'name'}=$data->{'name'};
	my $viewDocId = $viewCollection->save($viewDoc);
	$self->app->log->debug("Edit: Saved view doc to mongo: ".$viewDocId);
	return $viewDocId;
}

sub editKey {
  my $self = shift;
	my $id = shift;
	my $key = shift;
	my $value = shift;
	my $filterCollection = $self->mongoDB->db->collection('views');
	my $filterDocId = $filterCollection->update({'_id' => $id},{ $key => $value });
	$self->app->log->debug("Edit: view $key key: ".$filterDocId);
	return $filterDocId;
}

sub delete {
    my $self = shift;
    #placeholder
}

sub _applyTemplate {
	my $self = shift;
	my $templateArg = shift;
	my $stashRef = shift || {};
	my $templateString = '';
	if(scalar(keys %{$stashRef}) < 1){
		$self->app->log->debug('no values passed to template, returning empty string');
		return '';
	}
	if(ref($templateArg) eq 'HASH'){
		$templateString = $self->_getTemplate($templateArg);
	}else{
		$templateString = $templateArg;
	}
	my $cache = $self->app->cache;
	my $templateKey = md5_sum( join('_',keys %{$stashRef}).md5_sum($templateString) );
	my $output;
  #my $mt = Mojo::Template->new($templateString);
	my $mt = $cache->get($templateKey);
	$mt ||= $cache->set($templateKey => Mojo::Template->new)->get($templateKey);
	#$self->app->log->debug("Rendering with stash = ".Dumper($stashRef));
	if($mt->compiled){
		$self->app->log->debug("Rendering cached template with new stash values.");
		$output = $mt->interpret(values %{$stashRef});
	}else{
		my $prepend='';
		# add Stash values to template
		$prepend = '% my( $';
		$prepend .= join(', $', grep {/^\w+$/} keys %{$stashRef} );
		$prepend .= ') = @_;'."\n";
		$output = $mt->render($prepend.$templateString, values %{$stashRef})
	}
	#$self->app->log->debug('rendered template = '.$templateString.' result = '.$output);
	return $output;
}

sub _getTemplate {
	my $self = shift;
	my $templateNameOpt = shift;
	my $output ='';
	my $templateName = $templateNameOpt->{'name'} || 'default';
	if( $templateName eq 'default'){
		#pass $value array and concats with string defined in option
		my $concatWith = $templateNameOpt->{'option'} || '</br>';
		$output = '<%= $value %>';
	}elsif( $templateName eq 'concat'){
		#pass $value array and concats with string defined in option
		my $concatWith = $templateNameOpt->{'option'} || '</br>';
		$output = '<%= join \''.$concatWith.'\', @$value %>';
	}elsif( $templateName eq 'mergecolumn'){
		#has $value array and corresponding $mergevalue array
		$output = <<'EOF';
				  <ul>
					% my $i = 1;
					% for my $val (@$value) {
					% my $mVal = shift @$mergevalue;
					% my $class = $i % 2 ? 'sub_odd_sample' : 'sub_even_sample';
					% $i++;
					<li class='<%= $class %>'><%= $val %>: <%= $mval %></li>
					% }
				  </ul>
EOF
	}elsif( $templateName eq 'object'){
		$output = <<'EOF';
			<ul>
				% my $i = 1;
				% for my $object (@$value) {
				% my $class = $i % 2 ? 'sub_odd_sample' : 'sub_even_sample';
				<li class='<%= $class %>'>
					<table>
					% for my $oKey (keys %{$object}) {
						<tr><th><%= $oKey %></th><td><%= $object->{$oKey} %></td></tr>
					% }
					</table>
				</li>
				% $i++;
				% }
			</ul>
EOF
	}elsif( $templateName eq 'list'){
		$output = <<'EOF';
			<ul>
				% my $i = 1;
				% for my $line (@$value) {
				% my $class = $i % 2 ? 'sub_odd_sample' : 'sub_even_sample';
				<li class='<%= $class %>'>
					% if(ref($line) eq 'ARRAY'){
						<%= join(' ',@$line) %>
					% }else{
						<%= $line %>
					%}
				</li>
				% $i++;
				% }
			</ul>
EOF
	}
	return $output;
}

1;
__END__