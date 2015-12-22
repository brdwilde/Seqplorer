package Seqplorer::Controller::Query;
use Mojo::Base 'Mojolicious::Controller';
use strict;
use Mojo::JSON 'j';
use Mojo::ByteStream 'b';
# This action will render a template

sub submit {
	my $self = shift;
	my $json = Mojo::JSON->new;
	my $collection = $self->stash('collection');
	my $output;
	# TODO Depreciated? Set record_height for table/list in row styling
	#$output->{'record_height'} = 0;
	## Check 'where' filter
	my $where = $self->param('where');
	my $countColumns = $self->param('iColumns') || 2;
	if(!defined $where || length $where < 3 ){
		$self->app->log->debug("Where query was empty ");
		$output->{'aaData'}=[ [ ( 'Please specify some input and try again!', map { '' } 2..$countColumns ) ] ];
		$self->render( json => $output );
		return;
	}
	$where = j( b( $self->param('where') )->encode('UTF-8') );

	if ($collection eq "projects"){
		my $groupModel = $self->model('group');
		my $groupReturn = $groupModel->getmongoids();
	
		$where = {'groups' => { 'id' => { '$in' => $groupReturn->{groupids} }}};
	}

	
	## Get view used to display this query
	my $viewId = $self->param('view');
	my $fields;
	my $viewModel = $self->model('view');
	my $viewDoc = $viewModel->get({'_id' => $viewId});
	$self->app->log->debug("View response: ".Dumper($viewDoc));
	foreach my $column (@{$viewDoc->{'columns'}}){
		push (@$fields, $column->{'queryname'}) if ($column->{'queryname'});		
	}
	#} 
	if ($collection eq 'projects') {
		$fields = ["_id","name",['groups','name'],['groups','id'],"description"];
	}

	my $queryOptions = {
		'collection' => $collection,
		'skip' => 0,
		'limit' => 1,
		'view' => $viewId,
		'fields' => $fields
	};
	
	## Check 'advanced where' filter
	my $queryModel = $self->model('query');
	my $advWhere;
	if(defined $self->param('advanced_filter') && length $self->param('advanced_filter') > 2 ){
		$advWhere = j( b( $self->param('advanced_filter') )->encode('UTF-8') );
		if(defined $advWhere->{'sampleList'} ){#&& ! defined $where->{'sa'} ){
			$advWhere = $queryModel->parseSampleList($advWhere);
			#$advWhere = Seqplorer::Model::Query->add_elementMatch(\$advWhere,$viewDoc->{'elementmatch'});
		}
		#$advWhere = Seqplorer::Model::Query->add_elementMatch(\$advWhere,$viewDoc->{'elementmatch'});
		
		#$advWhere = $queryModel->add_mongoid($advWhere,$viewDoc->{'mongoid'});
	}else{
		## Add mongo ids where needed according to the view
		#$where = $queryModel->add_mongoid($where,$viewDoc->{'mongoid'});
		## Add elmatch where needed accordign to the view
		$where = $queryModel->add_elementMatch($where,$viewDoc->{'elementmatch'});
	}
	$queryOptions->{'restrict'}=$viewDoc->{'restrict'} if (exists $viewDoc->{'restrict'});
	#$self->app->log->debug('before object to dot: query = '.Dumper($where));
	## Change to dotnotation
	( $where, undef ) = $queryModel->object2dotnotation($where,'');
	( $advWhere, undef ) = $queryModel->object2dotnotation($advWhere,'') if defined $advWhere;
	use Data::Dumper;
	#$self->app->log->debug("## where query: ".Dumper($where));
	#$self->app->log->debug("## advWhere query: ".Dumper($advWhere));
	
	## Get query counts
	my $iTotalRecords=$queryModel->count($where,$collection);
	#use Hash::Merge qw( merge );
	#Hash::Merge::set_set_behavior('RETAINMENT_PRECEDENT');
	$where = $advWhere if defined $advWhere;
	my $iTotalDisplayRecords=$queryModel->count($where,$collection);
	
	if($iTotalDisplayRecords > 0){
		## All fields
		# DEPRECIATED
		
		## Single col filter
		#TODO ignored for now
		
		## Get sorting info
		my %sortQuery;
		if(defined $self->param('iSortingCols') && $self->param('iSortingCols') && $self->param('iSortCol_0') != 0 ){
			my $sortCount=$self->param('iSortingCols')-1;
			for my $i (0..$sortCount){
				unless(defined $self->param('iSortCol_'.$i) && length $self->param('iSortCol_'.$i)){
					next;
				}
				if($self->param('sSortDir_'.$i) eq 'desc'){
					$sortQuery{$viewDoc->{'columns'}->[$self->param('iSortCol_'.$i)]->{'dotnotation'}}=1;
				}
				if($self->param('sSortDir_'.$i) eq 'asc'){
					$sortQuery{$viewDoc->{'columns'}->[$self->param('iSortCol_'.$i)]->{'dotnotation'}}=-1;
				}
			}
		}
		
		##set limit and skip
		if(defined $self->param('iDisplayStart')){
			$queryOptions->{'skip'}=$self->param('iDisplayStart');
			$queryOptions->{'limit'}=$self->param('iDisplayLength');
		}
		$queryOptions->{'sort'} = \%sortQuery if (%sortQuery);
		#execute query with where {"project":{"id":{"$in":["5130ca73721c5a7223000004"]}}}
		
		# fetch the results with the options set
		$self->app->log->debug("## queryOptions: ".Dumper($where,$queryOptions));
		my $records=$queryModel->fetch($where, $queryOptions);
	
		# run through the results formatting them
		for my $record (@$records){
			$self->app->log->debug('#### recordloop: record = '.Dumper($record));#.' to be dearrayed with '.Dumper($viewDoc->{'queryarray'}));
			for my $queryArrayKey ( keys %{$viewDoc->{'queryarray'}} ){
				my $queryArrayVal = $viewDoc->{'queryarray'}{$queryArrayKey};
				$record->{$queryArrayKey}= $self->_dearray($record, $queryArrayVal);
			}
			my $row=[];
			my $colIndex = 0;
			for my $col ( @{$viewDoc->{'columns'}} ){
				#$self->app->log->debug('col value = '.Dumper($col));
				my %stash;
				%stash = %{$col->{'stash'}} if defined $col->{'stash'};
				delete $stash{'value'} if defined $stash{'value'};
				for my $stashKey (keys %stash){
					#check if some stash values are references to other columns
					if(ref($stash{$stashKey}) eq 'HASH' && defined $record->{$stash{$stashKey}}){
						$stash{$stashKey}=$record->{$stash{$stashKey}};
					}
				}
				if(defined $col->{'dotnotation'} && defined $record->{$col->{'dotnotation'}}){
					$stash{'value'} = $record->{$col->{'dotnotation'}};
				}
				if(!defined $col->{'template'} && defined $col->{'dotnotation'} ){
					if(defined $record->{$col->{'dotnotation'}} && ref($record->{$col->{'dotnotation'}}) eq 'ARRAY' ){
						$row->[$colIndex]= $viewModel->_applyTemplate({ 'name'=>'list' }, \%stash );
					}else{
						$row->[$colIndex]= $record->{$col->{'dotnotation'}} || '';
					}
				}else{
					$row->[$colIndex]= $viewModel->_applyTemplate($col->{'template'}, \%stash );
				}
				$colIndex++;
			}
			push @{$output->{'aaData'}}, $row;
		}
	}else{
		$output->{'aaData'}=[ [ ( 'No results found in database!', map { '' } 2..$countColumns ) ]];
	}
	$output->{'exportquery'} = j($where);
	$output->{'sEcho'} = $self->param('sEcho');
	$output->{'iTotalRecords'} = $iTotalRecords;
	$output->{'view'} = $viewId;
	$output->{'iTotalDisplayRecords'} = $iTotalDisplayRecords;
	
	$self->render(
		json => $output
	);
}

# Function that will generate a dot notation replacing the object style
# input are an object and an array of dot notation keys
# record entry. eg:
# record[group][name] = "x" will be converted in record[group.name] = "x"
# special attention will go to arrays in the record object:
# record[group][0][name] = "x"
# record[group][1][name] = "y" will be converted in:
# record[group.name] = ["x","y"] respecting the relative positions in the array
sub _dearray{ #$record, $column
	my $self = shift;
	my $recordRef = shift;
	#$self->app->log->debug('_dearray: recordRef is '.ref($recordRef).' with value '.Dumper($recordRef));
	my $record=$recordRef;
	#$record = {%{$recordRef}} if(ref($recordRef) eq 'HASH');
	#$record = [@{$recordRef}] if(ref($recordRef) eq 'Array');
	my $queryArrayRef = shift;
	#$self->app->log->debug('_dearray: recordArrayRef is '.Dumper($queryArrayRef) );
	
	my @column = @{$queryArrayRef};
	my $return = {};
	my $key = shift @column ;
	return $record unless defined $key;
	if (ref($record) eq 'HASH' && defined $record->{$key}){
			$return = {};
			$return = $self->_dearray($record->{$key}, \@column);
			return $return;
	} else {
			unshift @column, $key;
			$return = [];
			if (ref($record) eq 'ARRAY'){
				for my $subRecord (@{$record}){
					if (ref($subRecord) eq 'HASH'){
						if (defined $subRecord->{$key}){
							push @{$return}, $self->_dearray($subRecord, \@column);
						}else{
							push @{$return}, '';
						}
					}
				}
			}
			if(scalar @{$return} < 1){
				$return = '';
			}
			return $return;
	}

}
1;