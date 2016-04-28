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
		my $groupReturn = $groupModel->getmongoids($self->session('userid'));
		
		$where = {'groups' => { 'id' => { '$in' => $groupReturn->{groupids} }}};
	} elsif (@$where) {
		my @idarray;
		foreach my $val (@$where){
			push @idarray, Mango::BSON::ObjectID->new($val);
		}
		$where = {'project' => { 'id' => { '$in' => \@idarray }}} if $collection eq "samples";
		$where = {'sa' => { 'id' => { '$in' => \@idarray }}} if $collection eq "variants";
	} elsif ($viewId eq 'only_variants') {
		$where = {};
	} else {
		$self->app->log->debug("Where query was empty ");
		$output->{'aaData'}=[ [ ( 'Please specify some input and try again!', map { '' } 2..$countColumns ) ] ];
		$self->render( json => $output );
		return;
	}

	## Get fields we want to display from the view	my $fields;
	my $viewModel = $self->model('view');
	my $queryModel = $self->model('query');
	my $viewDoc = $viewModel->get({'_id' => $viewId});
	my $fields;
	my $counter = 0;
	foreach my $column (@{$viewDoc->{'columns'}}){
		push (@$fields, $column->{'queryname'}) if ($column->{'queryname'});

		#$where = $queryModel->_sethashbyarray($where,$column->{'queryname'},$self->param('sSearch_'.$counter)) if $self->param('sSearch_'.$counter);

		if ($self->param('sSearch_'.$counter)){
			my $value;
			if ($column->{type} eq 'numerical'){
				$value += $self->param('sSearch_'.$counter);
			} else {
				$value = $self->param('sSearch_'.$counter);
			}
			$where = $self->_sethashbyarray($where,$column->{'queryname'},$value);
		}
		$counter++;
	}

	my $queryOptions = {
		'collection' => $collection,
		'skip' => 0,
		'limit' => 1,
		'view' => $viewId,
		'fields' => $fields
	};

	## Check 'advanced where' filter
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
		#$self->app->log->debug("Element match: ".Dumper($viewDoc->{'elementmatch'}));
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
		
		#use Data::Dumper;
		#$self->app->log->debug("## where query: ".Dumper($where));
		#$self->app->log->debug("## options: ".Dumper($queryOptions));

		# fetch the results with the options set
		my $records=$queryModel->fetch($where, $queryOptions);
	
		# run through the results formatting them
		for my $record (@$records){
		

			#$self->app->log->debug('#### recordloop: record = '.Dumper($viewDoc,$record));#.' to be dearrayed with '.Dumper($viewDoc->{'queryarray'}));
		

			# for my $queryArrayKey ( keys %{$viewDoc->{'queryarray'}} ){
			# 	my $queryArrayVal = $viewDoc->{'queryarray'}{$queryArrayKey};
			# 	$record->{$queryArrayKey}= $self->_dearray($record, $queryArrayVal);
			# }
			# $self->app->log->debug('#### After dearrya: record = '.Dumper($record));

			my $row=[];
			my $colIndex = 0;
			for my $col ( @{$viewDoc->{'columns'}} ){
				if ($col->{queryname}) {

					#my %stash;
					#%stash = %{$col->{'stash'}} if defined $col->{'stash'};
					#delete $stash{'value'} if defined $stash{'value'};
					#for my $stashKey (keys %stash){
						#check if some stash values are references to other columns
					#	if(ref($stash{$stashKey}) eq 'HASH' && defined $record->{$stash{$stashKey}}){
					#		$stash{$stashKey}=$record->{$stash{$stashKey}};
					#	}
					#}
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
					
					my %stash;
					my $template = { 'name'=>'list' };
					$template = $col->{template} if ($col->{template});
					
					# this is a record field, get the values
					$stash{'value'} = $self->_getvals($record,$col->{queryname});
					
					if (ref($stash{'value'}) eq 'ARRAY'){
						# multiple values render according to template
						$row->[$colIndex]= $viewModel->_applyTemplate($template, \%stash );
					} else {
						# simple column, no rendering
						$row->[$colIndex]= $stash{'value'};
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

				$colIndex++;
			}
			#$self->app->log->debug('row value = '.Dumper($row));
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
			my $var = $rec->{$key} ? $rec->{$key} : '-';
			push @$return, $var;
		}
	} else {
		if (@keys > 0){
			# remaining levels, get the values
			$return = $self->_getvals($record->{$key},\@keys);
		} else {
			# last level, return the remaining record
			$return = $record->{$key} ? $record->{$key} : '-';
		}
	}
	return $return;
}

sub _sethashbyarray{
	my $self = shift;
	my $hash = shift;
	my $arrayArg = shift;
	my @array = @{$arrayArg};
	my $set = shift;

	#$self->app->log->debug('hash is:'.Dumper($hash));

	my $key = shift(@array);
	if ($key) {
		# array had an element, we continue
		if (ref($hash) eq 'HASH'){
			# hash truely is a hash
			if ($hash->{$key}){
				# the hash key already exists
				$hash->{$key} = $self->_sethashbyarray($hash->{$key},\@array,$set);
				return $hash;
			} else {
				# key might exist under a mongo operator
				LOOP: foreach my $operator (keys %{$hash}){
					if ($operator =~ /^\$/){
						if ($hash->{$operator}->{$key}){
							# found operator and key under it, continue	
							$hash->{$operator}->{$key} = $self->_sethashbyarray($hash->{$operator}->{$key},\@array,$set);
							return $hash;
						} else {
							# we found an operator, but no key under it, we create it
							$hash->{$operator}->{$key} = $self->_sethashbyarray(undef,\@array,$set);
							return $hash;
						}
						last LOOP;
					}
				}
			}
		}
		# create a hashref with the key set
		$hash->{$key} = $self->_sethashbyarray(undef,\@array,$set);
		return $hash;
	} else {
		#last element of array reached, we return the value
		return $set;
	}
}


1;