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
	my $param = shift;

	my $config = $self->app->config;
	my $viewcoll = $config->{database}->{collections}->{views} ? $config->{database}->{collections}->{views} : "views";
	my $viewCollection = $self->mongoDB->db->collection($viewcoll);

	my $variants_unique_coll = $config->{database}->{collections}->{variants_unique} ? $config->{database}->{collections}->{variants_unique} : "variants_unique";
	my $variant_coll = $config->{database}->{collections}->{variants} ? $config->{database}->{collections}->{variants} : "variants";
	my $samples_coll = $config->{database}->{collections}->{samples} ? $config->{database}->{collections}->{samples} : "samples";
	my $projects_coll = $config->{database}->{collections}->{projects} ? $config->{database}->{collections}->{projects} : "projects";
	my $plots_coll = $config->{database}->{collections}->{plots} ? $config->{database}->{collections}->{plots} : "plots";

	my $viewId = $param->{'_id'};

	my $templates = {
		'variants' => {
			"_id" => "variants",
			"collection" => $variant_coll,
			"view" => "variants",
			"dom" => "iCr<'H'>t",
			"mongoid" => [["_id"],["sa","id"]],
			"elementmatch" => [["sa"]],
			"columns" => [],
			"colvis" => []
		},
		'samples' => {
			"_id" => "samples",
			"collection" => $samples_coll,
			"view" => "samples",
			"name" => "samples",
			"dom" => "<'H'f>rt",
			"mongoid" => [["_id"],["project","id"]],
			"columns" => [],
			"colvis" => []
		},
		'projects' => {
			"_id" => "projects",
			"collection" => $projects_coll,
			"view" => "projects",
			"name" => "projects",
			"dom" => "<'H'f>rt",
			"mongoid" => [["_id"],["groups","id"]],
			"columns" => [],
			"colvis" => []
		}
	};

	my $return;
	my $columns;

	if ($viewId eq "variants" || $viewId eq "variants_only"){
		$return = $templates->{'variants'};
		$return->{_id} = $viewId;
		$return->{view} = $viewId;
		$return->{name} = $viewId;
		$columns = [
				_html_column({
					'name' => "Detail",
					'type' => "img",
					'stashvars' => {"variantid" => "_id"},
					'imagename' => "details_open.png"}),
				_html_column({
					'name' => "View IGV",
					'type' => "link",
					'link' => "http://localhost:60151/goto?locus=<%c%>:<%s%>-<%e%>",
					'classes' => ["igv","table_icon"],
					'stashvars' => {"chromosome" => "c", "start" => "s", "end" => "e"},
					'imagename' => "IGV_32.png"}),
				_html_column({
					'name' => "Ensembl",
					'type' => "link",
					'link' => "http://www.ensembl.org/Homo_sapiens/Location/Overview?r=<%c%>:<%s%>-<%e%>",
					'target' => "_blank",
					'classes' => ["ensembl","table_icon"],
					'stashvars' => {"chromosome" => "c", "start" => "s", "end" => "e"},
					'imagename' => "Ensembl.jpg"}),
				"b","c","karyo","s","e","v","va","vp","r","t","name",
				"sa.sn","sa.DP","sa.allelequal",
				"tr.gene","tr.tr","tr.str","tr.cdnas","tr.con","tr.peps","tr.ppos","tr.pphe","tr.pphes","tr.sift","tr.sifts"
		];
	} elsif ($viewId eq "projects"){
		$return = $templates->{"projects"};

		$columns = [ 
				_html_column({
					'name' => "View",
					'type' => "img",
					'classes' => ["pane"],
					'atributes' => { 'showtable' =>'samples'},
					'stashvars' => {"projectsid" => "_id", "projectsname"=>"name"},
					'imagename' => "details_open.png"}),
				 _html_column({
					'name' => "Select",
					'type' => "checkbox",
					'classes' => ["multi_select"],
					'stashvars' => {"projectsid" => "_id", "projectsname"=>"name"}}),
			    { "sName" => "ID", "queryname" => [ "_id" ], "unshowable" => 1, "bVisible" => \0 },
			    { "sName" => "Name", "queryname" => [ "name" ], "sorting" => \1 },
			    { "sName" => "Groups", "queryname" => [ "groups", "name" ], "template" => { "name" => "concat", "option" => "_" } },
			    { "sName" => "Group ID", "queryname" => [ "groups", "id" ], "unshowable" => 1, "bVisible" => \0, },
			    { "sName" => "Description", "queryname" => [ "description" ] }
			];

	} elsif ($viewId eq "samples"){
		$return = $templates->{"samples"};

		$columns = [
				_html_column({
					'name' => "View",
					'type' => "img",
					'classes' => ["pane"],
					'atributes' => { 'showtable' =>'variants'},
					'stashvars' => {"samplesid" => "_id", "samplesname"=>"name"},
					'imagename' => "details_open.png"}),
				 _html_column({
					'name' => "Select",
					'type' => "checkbox",
					'classes' => ["multi_select"],
					'stashvars' => {"samplesid" => "_id", "samplesname"=>"name"}}),
			    { "sName" => "ID", "queryname" => [ "_id" ], "unshowable" => 1, "bVisible" => \0 },
			    { "sName" => "Name", "queryname" => [ "name" ], "sorting" => \1 },
			    { "sName" => "Description", "queryname" => [ "description" ] },
			    { "sName" => "Genomebuild", "queryname" => [ "genome" ] },
			    { "sName" => "Project", "queryname" => [ "project", "name" ], "template" => { "name" => "concat", "option" => "\/" }, "bSortable" => \0 },
			    { "sName" => "Project ID", "queryname" => [ "project", "id" ], "unshowable" => 1, "bVisible" => \0 },
			    { "sName" => "File name", "queryname" => [ "files", "name" ], "bSortable" => \0  },
			    { "sName" => "File type", "queryname" => [ "files", "filetype" ], "bSortable" => \0  },
			    { "sName" => "File location", "queryname" => [ "files", "type" ], "bSortable" => \0  },
			    { "sName" => "Filename", "queryname" => [ "files", "file" ], "unshowable" => 1, "bVisible" => \0 },
			    { "sName" => "Compression", "queryname" => [ "files", "compression" ], "bSortable" => \0  },
			    { "sName" => "File host", "queryname" => [ "files", "host" ], "bSortable" => \0  },
			    { "sName" => "Username", "queryname" => [ "files", "user" ], "bSortable" => \0 },
		    	_html_column({
					'name' => "Edit",
					'type' => "img",
					'classes' => ["resample","table_icon"],
					'atributes' => { 'action' => 'edit_sample'},
					'stashvars' => {"sampleid" => "_id", "samplesname"=>"name"},
					'imagename' => "edit.png"}),
		    	_html_column({
					'name' => "Delete",
					'type' => "img",
					'classes' => ["resample","table_icon"],
					'atributes' => { 'action' => 'remove_sample'},
					'stashvars' => {"sampleid" => "_id", "samplesname"=>"name"},
					'imagename' => "cancel.png"}),
			];
	} else {
		my $viewID_OID = ( $viewId =~ /^[0-9a-fA-F]{24}$/ ) ? Mango::BSON::ObjectID->new($viewId) : { '_id' => $viewId };
		#$self->app->log->debug("Get view from mongo: $viewId = $viewID_OID => ".ref($viewID_OID));
		my $viewDoc = $viewCollection->find_one($viewID_OID);
		
		my $collection = $viewDoc->{'collection'};

		$return = $templates->{$collection};	
		#	my $cache = $self->app->cache;
		#	if( defined $cache->get($viewId) ){
		#		$self->app->log->debug("Cache hit for get view: $viewId");
		#		return $cache->get($viewId);
		#	}
		#	$self->app->log->debug("Cache miss for get view: $viewId");
	
		$return->{'_id'} = $viewDoc->{'_id'};
		$return->{'name'} = $viewDoc->{'name'};
		$columns = $viewDoc->{'columns'};
	}

	# walk through the columns and add the columns referred to by the "stash" variables as invisible columns if they are not there yet
	my %stashcolumns;
	my %allcolumns;
	foreach my $column (@$columns) {
		if (ref$column eq 'HASH') {
			if ($column->{stash}){
				foreach my $key (keys %{$column->{stash}}){
					$stashcolumns{$column->{stash}->{$key}} = 1;
				}
			}
			$allcolumns{join(".",$column->{queryname})} = 1 if ($column->{queryname});
		} else {
			$allcolumns{$column} = 1;
		}
	}

	foreach my $col (keys %stashcolumns){
		push (@$columns,{"queryname" => [$col], "unshowable" => 1, "bVisible" => \0 }) unless ($allcolumns{$col});
	}
	# now add all the mongoid columns to the view
	if ($return->{'mongoid'}){
		foreach my $col (@{$return->{'mongoid'}}){
			my $colstring = join(".",@$col);
			push (@$columns,{"queryname" => $col, "unshowable" => 1, "bVisible" => \0 }) unless ($allcolumns{$colstring} || $stashcolumns{$colstring});
		}
	}

	# now remove the stashcolumns if the are already part of the columns
	my $index = 0;
	for my $column (@$columns) {
		my $filter = undef;
		if (ref$column eq 'HASH') {
			# this column element is fully encoded in the view record
			push @{$return->{'columns'}}, $column;
			# add the colum index with the unshowable argument to the colvis section of the header
			#push @{$return->{'colvis'}}, $index if ($column->{unshowable} && !$column->{unshowable});
			push @{$return->{'colvis'}}, $index if (defined($column->{unshowable}) && $column->{unshowable});
			delete $column->{unshowable};
		} else {
			# in case of column dot notation: create a default column
			my @arraynotation = split(/\./,$column);
			my $element = { "sName" => $column, "queryname" => \@arraynotation };
			# if(defined $column->{'queryname'}){
			# 	$column->{'dotnotation'} = join('.',@{$column->{'queryname'}});
			# }
			# #hash: key dotnotation to valus: queryname (query array)
			# #->unused in frontend
			# $return->{'queryarray'}{$column->{'dotnotation'}}=$column->{'queryname'} if defined $column->{'dotnotation'};
			# #create array of dotnotation names of all cols
			# #->unused in frontend
			# push @{$return->{'fields'}}, $column->{'dotnotation'} if defined $column->{'dotnotation'};
			# #add extra info from _unique collection
			
			if($return->{collection} eq 'variants'){
				# get record form "unique" collection
				my $uniqueDoc = $self->mongoDB->db->collection($variants_unique_coll)->find_one({'_id' => $column});
				if($uniqueDoc){
					$element->{'sName'} = $uniqueDoc->{'name'} if $uniqueDoc->{'name'};
					$element->{'queryname'} = $uniqueDoc->{'querykeys'};
					$element->{'type'} = $uniqueDoc->{'type'} if $uniqueDoc->{'type'};
					$element->{'description'} = $uniqueDoc->{'description'} if $uniqueDoc->{'description'};
					$element->{'stats'} = $uniqueDoc->{'stats'} if $uniqueDoc->{'stats'};
					use Data::Dumper;
					if ($uniqueDoc->{'graph'}){
						my $plotDoc = $self->mongoDB->db->collection($plots_coll)->find_one({'_id' => $uniqueDoc->{'graph'}->{'_id'}});
						if ($plotDoc){
							# list with more than 20 elements connot be displayed
							if (@{$plotDoc->{data}->{values}} < 21) {
								# TODO: when bug is fixed in mapreduce operation we don't want to remove this first value anymore!!!
								shift ($plotDoc->{data}->{values});
								shift ($plotDoc->{data}->{counts});
								$element->{'values'} = $plotDoc->{data}->{counts};
								$element->{'tooltip'} = $plotDoc->{data}->{values};
							}
						}
						$element->{'graphid'} = $uniqueDoc->{'graph'}->{'_id'}."";
					}

					if ($uniqueDoc->{'type'} eq 'text'){
						if (ref($uniqueDoc->{'values'}[0]) ne 'ARRAY'){
							my @values = sort { lc($a) cmp lc($b) } @{$uniqueDoc->{'values'}};
							$filter = { 
								type => "select",
								values => \@values
							};							
						} else {
							$filter = {	type => "text"};
						}
					} elsif ($uniqueDoc->{'type'} eq 'numerical'){
						$filter = { type => "number"};
					}
					push @{$return->{'colvis'}}, $index if ($uniqueDoc->{'type'} eq 'mongo_id');
					$element->{'bVisible'} = \0 if $uniqueDoc->{'type'} eq 'mongo_id';
					#$column->{'searchtype'}=$uniqueDoc->{'type'};
					#if(defined $uniqueDoc->{'values'} && scalar(@{$uniqueDoc->{'values'}}) > 1 ){
					# 	$column->{'list'}=$uniqueDoc->{'values'};
					# }
					# if($uniqueDoc->{'type'} eq 'mongo_id'){
					# 	push @{$return->{'mongoid'}}, $uniqueDoc->{'querykeys'};
					# }
					
				}
			}
			push @{$return->{'columns'}}, $element;
		}
		push @{$return->{'columnfilter'}}, $filter;
		$index ++;
	}
#	$cache->set($viewId, \%return);
#	if( defined $cache->get($viewId) ){
#		$self->app->log->debug("Cache saved for get view: $viewId ");
#	}
	return $return;
}

sub edit {
	my $self = shift;
	my $data = shift;

	my $config = $self->app->config;
	my $viewcoll = $config->{database}->{collections}->{views} ? $config->{database}->{collections}->{views} : "views";
	my $viewCollection = $self->mongoDB->db->collection($viewcoll);

	my $viewDoc = {};

	# get old values if an id was submitted
	if( defined $data->{'_id'} && $data->{'_id'} ne '' ){
		$viewDoc->{'_id'} = $data->{'_id'};
		my $viewID_OID = Mango::BSON::ObjectID->new($viewDoc->{'_id'});
		$self->app->log->debug("Edit: Get view doc from mongo: ".$viewDoc->{'_id'}." = $viewID_OID => ".ref($viewID_OID));
		$viewDoc = $viewCollection->find_one($viewID_OID);
	}
	# update values to new one's
	$viewDoc->{'columns'} = $data->{'columns'} if $data->{'columns'};
	$viewDoc->{'collection'} = $data->{'collection'} if $data->{'collection'};
	$viewDoc->{'projects'} = $data->{'projects'} if $data->{'projects'};
	$viewDoc->{'name'} = $data->{'name'} if $data->{'name'};

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

sub _html_column {
	my $args = shift;

	my $name = $args->{'name'};
	my $type = $args->{'type'};
	my $link = $args->{'link'};
	my $target = $args->{'target'};
	my $classes = $args->{'classes'};
	my $atributes = $args->{'atributes'};
	my $stashvars = $args->{'stashvars'};
	my $imagename = $args->{'imagename'};

	my $html = '';
	my $stash;

	if ($type eq 'link'){
		$html .= "<a href='".$link."'";
		$html .= " target='".$target."'" if $target;
		$html .=">";
	}
    if ($type eq 'img' || $imagename){
    	$html .= "<img src='img\/".$imagename."' ";
    } elsif ($type eq 'checkbox'){
    	$html .= "<input type='checkbox' ";
    }

    if ($classes){
    	$html .= "class='";
    	foreach my $class (@$classes){
    		$html .= $class." ";
    	}
    	$html .= "' ";
    }
    if ($atributes){
    	foreach my $key (keys %$atributes){
	    	$html .= $key."='".$atributes->{$key}."' ";
    	}
    }
    if ($stashvars){
    	foreach my $key (keys %$stashvars){
	    	$html .= $key."='<%".$stashvars->{$key}."%>' ";
    	}
    }
    $html .= "title='".$name."'\/>";

    if ($type eq 'link'){
		$html .= "</a>";
	}


	my $column = {
		"sName" => $name,
		"bSortable" => \0,
		"bSearchable" => \0,
		"row_detail" => \0,
      	"unshowable" => 0,
      	"template" => $html,
      	"stash" => $stashvars
	};

	return $column;	    
}

sub _applyTemplate {
	my $self = shift;
	my $templateArg = shift;
	my $stashRef = shift || {};
	my $templateString = '';
	if(scalar(keys %{$stashRef}) < 1){
		#$self->app->log->debug('no values passed to template, returning empty string');
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
		#$self->app->log->debug("Rendering cached template with new stash values.");
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
				  <ul class='ul_table'>
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
			<ul class='ul_table'>
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
			<ul class='ul_table'>
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