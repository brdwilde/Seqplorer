package Seqplorer::Model::Query;
use strict;
use warnings;
#use base qw/Mojo::Base/;
use Mojo::Base -base;
use JSON::XS;
use Mojo::JSON;
use Carp qw/croak/;
use Mojo::JSON 'j';
use Mango::BSON ':bson';
use Mango::BSON::ObjectID;
use Mojo::Util qw(encode md5_sum);

has [qw/ app mongoDB /];

sub count {
	my $self = shift;
	my $whereRef = shift;
	my $collection = shift;
	my $countVal = 0;
	my $cache = $self->app->cache;
	my $cacheKey = $self->md5Key($whereRef, $collection );
	# check Mojo in memory cache
	if( defined $cache->get($cacheKey) && $cache->get($cacheKey) > 0 ){
		$self->app->log->debug("Found Count Query in cache: ".$cacheKey.' => '.$cache->get($cacheKey));
		return $cache->get($cacheKey);
	};
	$self->app->log->debug("Count Query not in cache: ".$cacheKey);
	# check Mongo count cache collection
	#my $countDoc = $self->mongoDB->db->collection('counts')->find_one({'_id' => $cacheKey }); #TO RESTORE
	#if(defined $countDoc){
	#	$countVal = $countDoc->{'counts'};
	#	$cache->set($cacheKey, $countVal);
	#	return $countVal;
	#}
	#$self->app->log->debug('count: in collection '.$collection.' and where = '.Dumper($whereRef));
	# Perform new count and safe to mongo
	my $countCursor = $self->mongoDB->db->collection($collection)->find( $whereRef );
	my $count=$countCursor->count();#sub {
	#	my ($cursor, $err, $count) = @_;
	#$self->mongoDB->db->collection('counts')->insert({'_id' => $cacheKey, 'counts' => $count }); #TO RESTORE
	#$self->app->log->debug("Count Query callback running, ".$cacheKey);
	#});
	#Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
	#sleep 1;
	# Wait a bit and check mongo again
	#$countDoc = $self->mongoDB->db->collection('counts')->find_one({'_id' => $cacheKey });
	if(defined $count && $count > 0){
		$countVal = $count;
		$cache->set($cacheKey, $count);
	}
	return $countVal;
}

sub fetch {
	my $self = shift;
	my $where = shift;
	my $options = shift;
	my @returnRows;
	#my $view = Seqplorer::Model::View->get({_id => $options->{'view'}});
	#$self->app->log->debug('fetch: in collection '.$options->{'collection'}.' and where = '.Dumper($where).' options = '.Dumper($options));

	# get us a cursor on the requested collections
	my $cursor = $self->mongoDB->db->collection($options->{'collection'})->find( $where );

	# get all the options and build the query
	$cursor->sort($options->{'sort'}) if (defined $options->{'sort'});
	
	if (defined $options->{'fields'}){
		my $hashFields;
		foreach my $field (@{$options->{'fields'}}){
			if (ref($field) eq 'ARRAY') {
				$hashFields->{join('.',@{$field})} = 1;
			} else {
				$hashFields->{$field} = 1;
			}
		}
		$cursor->fields($hashFields);
	}
	$cursor->limit($options->{'limit'}) if (defined $options->{'limit'});
	$cursor->skip($options->{'skip'}) if (defined $options->{'skip'} && $options->{'skip'} > 0);

	#$cursor->slave_okay(1);
	#$self->app->log->debug('fetch: in collection first result = '.Dumper($cursor->next) );

	# restriction rules
	# we create some restriction rules to limit users viewing other users data!!
	# at this time we only have one restriction rule for the variants database
	my $config = $self->app->config;
	my $variants = $config->{database}->{collections}->{variants} ? $config->{database}->{collections}->{variants} : "variants";
	
	my @restrictionData;
	if($options->{'collection'} eq $variants){
		my 	@restrict = ({"find" => ["sa"],"restrict" => ["id"]});

		foreach my $restrict (@restrict){
			$restrict->{'values'}=[];
			
			# create the full key set for the restriction fields
			$restrict->{'setKey'}=[@{$restrict->{'find'}}];
			push @{$restrict->{'setKey'}}, @{$restrict->{'restrict'}};

			# manipulate the where fields to obtain the restriction data
			my $whererestrict = {%{$where}};

			my @lookupKeys;
			foreach (@{$restrict->{'setKey'}}){
				push @lookupKeys, $_;
				if(defined $whererestrict->{join('.',@lookupKeys)} ){
					$whererestrict=$whererestrict->{join('.',@lookupKeys)};
				}
			}

			#$self->app->log->debug('fetch: after set whererestrict in loop = '.Dumper($whererestrict) );
			#$self->app->log->debug('fetch: restrict in loop = '.Dumper($restrict) );
			
			# find the element we want to match the document elements to
			# by descending into the where using the restrict array
			$restrict->{'values'} = $self->_gethashbyarray($whererestrict,$restrict->{'restrict'});
			#$self->app->log->debug('fetch: restrictionData = '.Dumper($whererestrict) );

			# remove potential mongodb operators at this level
			# mostly $in, $all,... at this level, only $in is relevant? # TODO: check this!
			# if (ref($whererestrict) eq "HASH"){
			# 	foreach my $key (keys %{$whererestrict}){
			# 		$restrict->{'values'} = [@{$whererestrict->{$key}}] if ($key =~ /^\$in/);
			# 	}
			# }elsif(ref($whererestrict) eq "ARRAY"){ #parent element must have been $all
			# 	#go over the diff $elemMatch object inside the $all
			# 	foreach my $allArrayEl (@{$whererestrict}){
			# 		if( defined $allArrayEl->{'$elemMatch'} ){
			# 			push @{$restrict->{'values'}}, $self->_gethashbyarray($allArrayEl->{'$elemMatch'},$restrict->{'restrict'});
			# 		}
			# 	}
			# }
			push @restrictionData, $restrict;
		}
	}
	use Data::Dumper;
	#$self->app->log->debug('fetch: restrictionData = '.Dumper(\@restrictionData) );
	
	#my @all;
	#eval { @all=$cursor->all; };
	while(my $doc = $cursor->next){
		last if(!defined $doc);
		#$self->app->log->debug('fetch: in next loop doc:'.Dumper($doc) );
		if(scalar(@restrictionData) > 0){
			foreach my $restrict (@restrictionData){
				my @approvedDocs;
				foreach my $subDoc ( @{$self->_gethashbyarray($doc,$restrict->{'find'})} ){
					#$self->app->log->debug('fetch: starting looping doc for restrict key :'.Dumper($restrict->{'find'}) );
					my %thisDoc = %{$subDoc};
					foreach (@{$restrict->{'restrict'}}){
						if(defined $subDoc->{$_}){
							# a sub document was found -> we move one level deeper
							$subDoc=$subDoc->{$_};
						}
						if( grep { $subDoc eq $_ } @{$restrict->{'values'}} ){
							# this sub document is in list of restricted values -> add to approved docs
							push @approvedDocs, \%thisDoc;
						}
					}
				}
				#$self->app->log->debug('fetch: reset doc array = '.Dumper($restrict->{'setKey'}).' approved = '.Dumper(@approvedDocs) );
				$doc = $self->_sethashbyarray($doc, $restrict->{'setKey'}, \@approvedDocs);
			}
		}
		#$self->app->log->debug('fetch: restricted doc :'.Dumper($doc) );
		push @returnRows, {%{$doc}};
	}	
	return \@returnRows;
}

sub add_elementMatch {
	my $self = shift;
	my $subjectsArg = shift;
	my $subjectsType = ref($subjectsArg);
	my %subjectsRef= %{$subjectsArg};
	croak 'Subjects passed to _add_elementMatch needs to be reference of a hash' unless ($subjectsType);
	my $arg = shift;
	return \%subjectsRef unless(defined $arg);
	my @elementmatch = @{ $arg };
	MATCHES:
	for my $matches (@elementmatch) {
		my $i=-1;
		my $j=0;
		my $tmpSubjectsRef = \%subjectsRef;
		for my $match (@$matches) {
			$i++;
			if( $subjectsType eq 'HASH' && defined $tmpSubjectsRef->{$match} ){
				if( $i == $#$matches ){
					my $val = $tmpSubjectsRef->{$match};
					$tmpSubjectsRef->{$match} = undef;
					$tmpSubjectsRef->{$match}{'$elemMatch'}=$val;
					$val = undef;
				}else{
					$tmpSubjectsRef = $tmpSubjectsRef->{$match};
				}
			}
			$j++;
		}
	}
	return \%subjectsRef;
}
# sub parseSampleList {
# 	my $self = shift;
# 	my $where= shift;
# 	my %sa;
# 	use Data::Dumper;
# 	my @sampleList=@{$where->{'sampleList'}};
# 	#if(defined $where->{'sa'}){
# 	#	%sa=%{$where->{'sa'}};
# 	#}
# 	my @whereSa;# will go here { 'sa' => { '$all' => [ *insert* ] }} 
# 	#generate $elemMatch objects for each sample that needs to be checked
# 	if(scalar(@sampleList) < 1 ){ 
# 		# do nothing no sample specific stuff needed
# 	}elsif(scalar(@sampleList) == 1 ){ 
# 		my $sample;
# 		# search same on all samples
# 		$sample = $self->add_mongoid($sampleList[0], [['id']]);
# 		$where->{'sa'} = { '$elemMatch' =>  $sample };
# 	}else{
# 		# diff search criteria for multiple samples
# 		for my $sample (@sampleList) {
# 			$sample = $self->add_mongoid($sample, [['id']]);
# 			push @whereSa, { '$elemMatch' => $sample };
# 		}
# 		$where->{'sa'}={ '$all' => \@whereSa }
# 	}
# 	#for my $saKeys (keys %sa) {
# 	#	$where->{'sa'}{$saKeys}=$sa{$saKeys};
# 	#}
# 	delete $where->{'sampleList'};
# 	return $where;
# }
# sub add_mongoid {
# 	my $self = shift;
# 	my $subjectsArg = shift;
# 	$self->app->log->debug('add_mongoid: subjectsArg = '.Dumper($subjectsArg));
# 	my $subjectsType = ref($subjectsArg);
# 	croak 'Subjects passed to add_mongoid needs to be reference of an array or hash' unless ($subjectsType);
# 	my %subjectsRef= %{$subjectsArg};
# 	my $arg = shift;
# 	return \%subjectsRef unless(defined $arg);
# 	my @mongoids = @{ $arg };
# 	my %mongoOper = map { $_ => 1 } ('$in','$all','$nin');
# 	MATCHES:
# 	for my $matches (@mongoids) {
# 		$self->app->log->debug("### checking ".join('.',@$matches));
# 		my $i=-1;
# 		my $j=0;
# 		my $tmpSubjectsRef = \%subjectsRef;
# 		for my $match (@$matches) {
# 			$i++;
# 			if( defined $tmpSubjectsRef->{$match} ){
# 				$self->app->log->debug("match for ".join('.',@$matches)." now at $match");
# 				if( $i == $#$matches ){
# 					my $val = $tmpSubjectsRef->{$match};
# 					if (ref($val) eq "HASH") {
# 						$self->app->log->debug("last el matched is hash");
# 						for my $matchOperKey ( grep defined($mongoOper{$_}), keys %$val) {
# 							$self->app->log->debug("oper with array of ids");
# 							my $length = @{$val->{$matchOperKey}};
# 							foreach (my $i=0; $i<$length; $i++){ # for each operater we replace all values in it
# 								$val->{$matchOperKey}->[$i] = Mango::BSON::ObjectID->new($val->{$matchOperKey}->[$i]);
# 							}
# 						}
# 						$tmpSubjectsRef->{$match}=$val;
# 					} else {
# 						$self->app->log->debug("simple id");
# 						# replace the value by its mongo object id
# 						$tmpSubjectsRef->{$match}=Mango::BSON::ObjectID->new($val);
# 					}
# 					$val = undef;
# 				}else{
# 					$tmpSubjectsRef = $tmpSubjectsRef->{$match};
# 				}
# 			}
# 			$j++;
# 		}
# 	}
# 	return \%subjectsRef;
# }

sub object2dotnotation{
	my $self = shift;
	my $valueArg = shift;
	my $dotkey = shift;
	my $value;
	my $return; # hashredf to contain the dotnotated object in the form {'return'=>$dotnotatedobject,'dotkey'=>$thelastdotkeyused}
	if (ref($valueArg) eq "HASH") {
		$value={%{$valueArg}};
		foreach my $key (keys %{$value}) {
			# check if we are using an operator to query (eg. $in, $nin, $all, $elemtmatch...)
			# we convert each to its dot notationn mongoid
			# my @operators =('$ne','$in','$all','$nin','$elemMatch','$and','$or','$nor');
			if ($key =~ /^\$/){
				#$self->app->log->debug('object2dotnotation: key = '.Dumper($key).' value = '.Dumper($value->{$key}));
				#my $returnobj = $self->object2dotnotation($value->{$key}, '');
				my ($returnobj, $returnkey) = $self->object2dotnotation($value->{$key}, '');
				if($dotkey eq ''){
					$return->{'return'}->{$key} = $returnobj;
				}else{
					$return->{'return'}->{$dotkey}->{$key} = $returnobj;
				}
				$return->{'dotkey'} = $dotkey;
			} else {
				my $newkey = '';
				if ($dotkey){
					$newkey = $dotkey.'.'.$key;
				} else {
					$newkey = $key;
				}
				my ($returnobj, $returnkey) = $self->object2dotnotation($value->{$key}, $newkey);
				if (ref($returnobj) eq "HASH"){
					foreach my $objkey (keys %{$returnobj}){
						$return->{'return'}->{$objkey} = $returnobj->{$objkey};
					}
					$return->{'dotkey'} = $returnkey;
				} else {
					$return->{'return'}->{$returnkey} = $returnobj;
					$return->{'dotkey'} = $returnkey;
				}
			}
		}
	} elsif (ref($valueArg) eq "ARRAY") {
		$value=[@{$valueArg}];
		#$self->app->log->debug('object2dotnotation:  array ref section, value= '.Dumper($value));
		# arrays can contain values but also hashes
		# we convert each element to its dot notation 
		foreach my $val (@{$value}){
			my ($returnobj, $returnkey) = $self->object2dotnotation($val, '');
			push (@{$return->{'return'}}, $returnobj);
		}
		$return->{'dotkey'} = $dotkey;
	}elsif (ref($valueArg) eq 'JSON::XS::Boolean'){
		# json boolean true is not the same as mongodb boolean true!
		#$value = ( $value ? boolean::true : boolean::false );
		$return->{'return'} = ( $valueArg ? Mojo::JSON->true : Mojo::JSON->false );
		$return->{'dotkey'} = $dotkey;
	}else{
		$return->{'return'} = $valueArg;
		$return->{'dotkey'} = $dotkey;
	}
	return ($return->{'return'},$return->{'dotkey'});
}

# descend in to a nested hash following the keys givven by an array and return the deepest result
sub _gethashbyarray{
	my $self = shift;
	my $hashArg = shift;
	#$self->app->log->debug('_gethashbyarray: arg of type '.ref($hashArg).', value = '.Dumper($hashArg));
	my $hash = {%{$hashArg}};
	my $array = shift;
	#$self->app->log->debug('_gethashbyarray: array of type '.ref($array).', value = '.Dumper($array));

	if (ref($hash) eq "HASH"){
		my @keys = keys($hash);
		if ($keys[0] =~ /^\$/){
			$hash = $hash->{$keys[0]};
		} 
	}

	# we descend into the hash using the array values as keys
	foreach my $key (@{$array}){
		if (defined($hash->{$key})){
			if (ref($hash->{$key}) eq "HASH"){
				my @keys = keys($hash->{$key});
				if ($keys[0] =~ /^\$/){
					$hash = $hash->{$key}->{$keys[0]};
				} else {
					$hash = $hash->{$key};
				}
			} elsif (ref($hash->{$key}) eq "ARRAY"){
				$hash = $hash->{$key}; # set the value attached to the key of the hash to be the new hash
			}
		}
	}
	#$self->app->log->debug('_gethashbyarray: return of type '.ref($hash));#.', value = '.Dumper($hash));
	return ($hash);
}

# set the value of a nested hash to a certain value by following an array as keys
sub _sethashbyarray{
	my $self = shift;
	my $hash = shift;
	my $arrayArg = shift;
	my @array = @{$arrayArg};
	my $set = shift;
	#$self->app->log->debug('_sethashbyarray: hash '.Dumper($hash).', array = '.Dumper($arrayArg).', set = '.Dumper($set));
	
	if (ref($hash) eq "HASH"){
		my %return;
		# buld a new hash identical to the input hash but when the key matches the first element of the input array
		# we desend into the hash and repeat the function
		my $first = shift(@array);
		foreach my $key (keys %{$hash}){
			if (defined($first) && $key eq $first){
				$return{$key} = $self->_sethashbyarray($hash->{$key},\@array,$set);
			}else{
				$return{$key} = $hash->{$key};
			}
		}
		# return a ref to the newly created hash
		return (\%return);
	}else{
		# if we did not receive a hash, we return the value we received
		return ($set);
	}
}

sub md5Key {
	my $whereRef = shift;
	my $collection = shift;
	my $whereRefSortedKeys = [ sort {$whereRef->{$a} cmp $whereRef->{$b}} keys %{$whereRef} ];
	my $sortedWhere = map { $_ => $whereRef->{$_} } sort { $whereRef->{$a} cmp $whereRef->{$b} } keys %{$whereRef} ;
	my $hashKey = md5_sum(j({'where' => $sortedWhere, 'collection' => $collection }));
	return $hashKey;
}

sub log {
	my $self = shift;
}

1;