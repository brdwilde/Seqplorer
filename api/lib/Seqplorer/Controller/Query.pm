package Seqplorer::Controller::Query;
use Mojo::Base 'Mojolicious::Controller';
use strict;
use Mojo::JSON qw(decode_json encode_json);
use Mango::BSON;
use Mojo::ByteStream 'b';
# This action will render a template

sub submit {
	my $self = shift;

	my $collection = $self->stash('collection');
	my $where = decode_json($self->param('where'));
	my $viewId = $self->param('view');

	my $output;
	# TODO Depreciated? Set record_height for table/list in row styling
	#$output->{'record_height'} = 0;
	## Check 'where' filter

	my $countColumns = $self->param('iColumns') || 2;


	if ($collection eq "projects"){
		# for the projects the "where" is not submitted, we get it for the user
		my $groupModel = $self->model('group');
		my $groupReturn = $groupModel->getmongoids();
	
		$where = {'groups' => { 'id' => { '$in' => $groupReturn->{groupids} }}};
	} elsif (@$where) {
		my @idarray;
		foreach my $val (@$where){
			push @idarray, Mango::BSON::ObjectID->new($val);
		}
		$where = {'project' => { 'id' => { '$in' => \@idarray }}} if $collection eq "samples";
		$where = {'sa' => { 'id' => { '$in' => \@idarray }}} if $collection eq "variants";
	} else {
		$self->app->log->debug("Where query was empty ");
		$output->{'aaData'}=[ [ ( 'Please specify some input and try again!', map { '' } 2..$countColumns ) ] ];
		$self->render( json => $output );
		return;
	}


	$self->app->log->debug("## where query: ".Dumper($where));
	#$where = j( b( $self->param('where') )->encode('UTF-8') ) unless $where;	

	## Get fields we want to display from the view	my $fields;
	my $viewModel = $self->model('view');
	my $viewDoc = $viewModel->get({'_id' => $viewId});
	my $fields;
	foreach my $column (@{$viewDoc->{'columns'}}){
		push (@$fields, $column->{'queryname'}) if ($column->{'queryname'});		
	}

	my $queryOptions = {
		'collection' => $collection,
		'skip' => 0,
		'limit' => 1,
		'view' => $viewId,
		'fields' => $fields
	};

	use Data::Dumper;
	
	## Check 'advanced where' filter
	my $queryModel = $self->model('query');
	my $advWhere;
	if(defined $self->param('advanced_filter') && length $self->param('advanced_filter') > 2 ){
		#$advWhere = j( b( $self->param('advanced_filter') )->encode('UTF-8') );
		$advWhere = decode_json($self->param('advanced_filter') );
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
		$self->app->log->debug("Element match: ".Dumper($viewDoc->{'elementmatch'}));
		$where = $queryModel->add_elementMatch($where,$viewDoc->{'elementmatch'});
	}

	#$self->app->log->debug('before object to dot: query = '.Dumper($where));
	## Change to dotnotation
	( $where, undef ) = $queryModel->object2dotnotation($where,'');
	( $advWhere, undef ) = $queryModel->object2dotnotation($advWhere,'') if defined $advWhere;
	
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
		

			$self->app->log->debug('#### recordloop: record = '.Dumper($viewDoc,$record));#.' to be dearrayed with '.Dumper($viewDoc->{'queryarray'}));
		

			# for my $queryArrayKey ( keys %{$viewDoc->{'queryarray'}} ){
			# 	my $queryArrayVal = $viewDoc->{'queryarray'}{$queryArrayKey};
			# 	$record->{$queryArrayKey}= $self->_dearray($record, $queryArrayVal);
			# }
			# $self->app->log->debug('#### After dearrya: record = '.Dumper($record));

			my $row=[];
			my $colIndex = 0;
			for my $col ( @{$viewDoc->{'columns'}} ){
				if ($col->{queryname}) {
					if (ref($col->{queryname}) eq 'ARRAY'){
						# this is a record field, get the values
						my $values = $self->_getvals($record,$col->{queryname});
						$row->[$colIndex]= $values;
					} else {
						# simple column value
						$row->[$colIndex]= $record->{$col->{queryname}};
					}
				} else {
					my $html = $col->{template};
					if ($col->{stash}){
						for my $key (keys $col->{stash}){
							my $replaced = "<%".$col->{stash}->{$key}."%>";
							my $replace = $record->{$col->{stash}->{$key}};
							$html =~ s/$replaced/$replace/g;
						}
					}
					# html column
					$row->[$colIndex]= $html;
				}
				#$self->app->log->debug('col value = '.Dumper($col));
				# my %stash;
				# %stash = %{$col->{'stash'}} if defined $col->{'stash'};
				# delete $stash{'value'} if defined $stash{'value'};
				# for my $stashKey (keys %stash){
				# 	#check if some stash values are references to other columns
				# 	if(ref($stash{$stashKey}) eq 'HASH' && defined $record->{$stash{$stashKey}}){
				# 		$stash{$stashKey}=$record->{$stash{$stashKey}};
				# 	}
				# }
				# if(defined $col->{'dotnotation'} && defined $record->{$col->{'dotnotation'}}){
				# 	$stash{'value'} = $record->{$col->{'dotnotation'}};
				# }
				# if(!defined $col->{'template'} && defined $col->{'dotnotation'} ){
				# 	if(defined $record->{$col->{'dotnotation'}} && ref($record->{$col->{'dotnotation'}}) eq 'ARRAY' ){
				# 		$row->[$colIndex]= $viewModel->_applyTemplate({ 'name'=>'list' }, \%stash );
				# 	}else{
				# 		$row->[$colIndex]= $record->{$col->{'dotnotation'}} || '';
				# 	}
				# }else{
				# 	$row->[$colIndex]= $viewModel->_applyTemplate($col->{'template'}, \%stash );
				# }
				$colIndex++;
			}
			push @{$output->{'aaData'}}, $row;
		}
	}else{
		$output->{'aaData'}=[ [ ( 'No results found in database!', map { '' } 2..$countColumns ) ]];
	}
	$output->{'exportquery'} = encode_json($where);
	$output->{'sEcho'} = $self->param('sEcho');
	$output->{'iTotalRecords'} = $iTotalRecords;
	$output->{'view'} = $viewId;
	$output->{'iTotalDisplayRecords'} = $iTotalDisplayRecords;
	
	$self->render(
		json => $output
	);
}


sub _getvals{ #$record, $column
	my $self = shift;
	my $record = shift;
	#print Dumper($recordRef);
	#my $record=$recordRef;
	#$record = {%{$recordRef}} if(ref($recordRef) eq 'HASH');
	#$record = [@{$recordRef}] if(ref($recordRef) eq 'Array');
	my $keys = shift;
	#print Dumper($keysRef);
	
	my @keys = @{$keys};
	my $key = shift @keys;
	my $return = {};
	if (ref$record eq 'ARRAY'){
		$return = [];
		foreach my $rec (@$record) {
			push @$return, $rec->{$key};
		}
	} else {
		if (@keys > 0){
			# remaining levels, get the values
			$return = $self->_getvals($record->{$key},\@keys);
		} else {
			# last level, return the remaining record
			$return = $record->{$key};
		}
	}
	return $return;
}


1;