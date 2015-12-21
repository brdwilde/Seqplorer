package Seqplorer::Model::Group;
use strict;
use warnings;
use DateTime;
use Carp qw/croak/;
use Mojo::Base -base;
use Mojo::Util qw(encode md5_sum);
use List::Util qw(first);
use Mango::BSON ':bson';
use Scalar::Util qw(looks_like_number);
use boolean;


has [qw/ app mongoDB /];

sub get {
    my $self = shift;
    my $userId = shift;

    # get the configuration info to connect to database
	my $config = $self->app->config;
	my $groupscoll = $config->{database}->{collections}->{groups} ? $config->{database}->{collections}->{groups} : "groups";
	my $groupCollection = $self->mongoDB->db->collection($groupscoll);

	# get the data in the database
	my $cursor;
	if ($userId){
		$cursor = $groupCollection->find({ 'approved' => Mango::BSON::ObjectID->new($userId)});
	} else {
		$cursor = $groupCollection->find({ 'public' => true});
	}

	my $groupdata;
	while(my $doc = $cursor->next){
		$self->app->log->debug('fetch: in next loop doc:'.$doc->{'_id'});
		last if(!defined $doc);
		push (@$groupdata,$doc);
	}

	if ($groupdata){
		return ({ Success => 1, Message => "Groups found", groupdata => $groupdata});
	} 

	return ({ Success => 0, Message => "Groups not found", userid => $userId});
}

sub getid {
    my $self = shift;
	my $userId = shift;

    # get the configuration info to connect to database
	my $config = $self->app->config;
	my $groupscoll = $config->{database}->{collections}->{groups} ? $config->{database}->{collections}->{groups} : "groups";
	my $groupCollection = $self->mongoDB->db->collection($groupscoll);

	# get the data in the database
	my $cursor;
	if ($userId){
		$cursor = $groupCollection->find({ 'approved' => Mango::BSON::ObjectID->new($userId)});
	} else {
		$cursor = $groupCollection->find({ 'public' => 'yes'});
	}

	my $groupdata;
	while(my $doc = $cursor->next){
		last if(!defined $doc);
		push (@$groupdata,$doc->{_id}."");
	}

	if ($groupdata){
		return ({ Success => 1, Message => "Groups found", groupids => $groupdata});
	} 

	return ({ Success => 0, Message => "Groups not found", userid => $userId});
}

#sub create {
#	# get the input data
#	my $self = shift;
#	my $userid = shift;
#	my $approve = shift;
#
#	my $collection = _connectdb();
#
#
#	# get the input data
#	my $self = shift;
#	my %groupdata = shift;
#
#	$groupdata->{admin};
#
#	my @memberusers = $groupdata->{users};
#	my @approvedusers = $groupdata->{users} if $groupdata->{approved};
#
#	%groupdata = {
#		'admin'=>$adminid,
#		'users'=>[$adminid],
#		'approved'=>[$adminid],
#		'description'=>$description,
#		'name'=>'Private group',
#		'public'=>'no'
#	)
#
#	# check the input data for validity
#	$groupdata->{email} = lc ($groupdata->{email});
#	# make sure the user provided an email adress and a password
#	if (!$groupdata->{email} || $groupdata->{email} eq '' || !($groupdata->{email} =~ /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,8}$/)){
#		# only valid email is allowed (simple email format is chosen)
#		return ({ Success => 0, Message => "Please provide a valid e-mail adress" });
#	}
#	if (!$groupdata->{password} || $groupdata->{password} eq ''){
#		return ({ Success => 0, Message => "Please provide a valid password" });
#	}
#
#	# encrypt the password
#	$groupdata->{password} = md5_sum($groupdata->{password});
#
#	# new users will be created inactive and at the current time with default role
#	$groupdata->{role} = ['user'];
#	$groupdata->{active} = 0;
#	$groupdata->{member_since} = DateTime->now;
#
#	# check for duplicate user e-mails
#	if($userCollection->find_one({ 'email' => $groupdata->{'email'} })) {
#		return ({ Success => 0, Message => "User with e-mail adress ".$groupdata->{'email'}." already registered." });
#	}
#
#	# create the new user and report back
#	my $userDocId = $userCollection->save($groupdata);
#	$self->app->log->debug("Saved user doc to mongo: ".$userDocId);
#
#	# now create the group for the user
#	$adminid = $groupdata->{adminid};
#	$description = $groupdata->{description};
#
#	$usernamestring = '';
#	$usernamestring .= ' '.$groupdata->{lastname} if $groupdata->{lastname};
#	$usernamestring .= ' '.$groupdata->{firstname} if $groupdata->{firstname};
#	$usernamestring .= ' '.$groupdata->{email} unless $usernamestring;
#
#	my $groupModel = $self->model('group');
#	my $groupuserReturn = $groupModel->create(\%groupdata);
#
#	$self->
#	$public_update = $collections['groups']->update(
#		array('name'=>'Public')
#		array('$addToSet'=>array('approved'=>$insert_arr['_id']
#		'users'=>$insert_arr['_id'])));
#	// if a user was invited a group will be posted, we add the user to that group
#
#	if ($userdata->{group}){
#		$invited_groups_insert = $collections['groups']->update(array('name'=>$group['name']),array('$addToSet'=>array('approved'=>$insert_arr['_id'],'users'=>$insert_arr['_id'])));
#	}
#
#	my $groupDocId = $collection->insert(\%groupdata);
#
#	if (!$groupDocId){
#		
#	}
#
#	# retrun success
#	return ({ Success => 1, Message => "Group created", groupid => $$groupDocId});
#}

sub update {
	# get the input data
	my $self = shift;
	my $id = shift;
	my $updatedata = shift;

	my $collection = _connectdb();

	my $groupDoc = $collection->find_one(Mango::BSON::ObjectID->new($id));

	# change the info of the db record with the updated info
	foreach my $key (keys %{$updatedata}){
		$groupDoc->{$key} = $updatedata->{$key};
	}

	# check the input data for validity before we go back to the database	
	# TODO: NO CHECKS ON THIS DATA?

	# update the user record
	$collection->update({'_id' => Mango::BSON::ObjectID->new($id)},$updatedata);		
	$self->app->log->debug("Updates performed to doc ".$id);
	return ({ Success => 1, Message => "Group record updated", groupid => $id});
}

sub adduser {
	# get the input data
	my $self = shift;
	my $id = shift;
	my $userid = shift;
	my $approve = shift;

	my $collection = _connectdb();

	my $groupDoc = $collection->find_one(Mango::BSON::ObjectID->new($id));

	push (@$groupDoc->{users}, $userid);

	my $updatereturn = update($groupDoc);

	if (!$updatereturn->{Success}){
		return ({ Success => 0, Message => "Unable to add user ".$userid." as a member of group ".$id, groupid => $id});		
	}

	my $approvestring ='';
	if ($approve){
		my $return = approveuser($id,$userid);
		return $return unless ($return->{Success});
		$approvestring .= ' and approved';
	}

	return ({ Success => 1, Message => "User ".$userid." added".$approvestring." to group", groupid => $id});
}

sub removeuser {
	# get the input data
	my $self = shift;
	my $id = shift;
	my $userid = shift;

	my $collection = _connectdb();

	my $groupDoc = $collection->find_one(Mango::BSON::ObjectID->new($id));

	# remove user from users array
	my @newusers;
	foreach my $user (@$groupDoc->{users}){
		push @newusers, $user unless $user eq $userid;
	}
	$groupDoc->{users} = \@newusers;

	# remove user from approved array
	my @approvedusers;
	foreach my $user (@$groupDoc->{approved}){
		push @approvedusers, $user unless $user eq $userid;
	}
	$groupDoc->{approved} = \@approvedusers;

	my $updatereturn = update($id, $groupDoc);

	if (!$updatereturn->{Success}){
		return ({ Success => 0, Message => "Unable to remove user ".$userid." as a member of group ".$id, groupid => $id});		
	}

	return ({ Success => 1, Message => "User ".$userid." removed from group", groupid => $id});
}

sub approveuser {
	# get the input data
	my $self = shift;
	my $id = shift;
	my $userid = shift;

	my $collection = _connectdb();

	my $groupDoc = $collection->find_one(Mango::BSON::ObjectID->new($id));

	push (@$groupDoc->{approved}, $userid);

	my $updatereturn = update($id, $groupDoc);

	if (!$updatereturn->{Success}){
		return ({ Success => 0, Message => "Unable to approve user ".$userid." as a member of group ".$id, groupid => $id});		
	}

	return ({ Success => 1, Message => "User ".$userid." approved as a member of group ".$id, groupid => $id});
}

sub delete {
 	# get the input data
	my $self = shift;
	my $id = shift;

	my $collection = _connectdb();

	# remove the group record
	$collection->remove(Mango::BSON::ObjectID->new($id));		
	$self->app->log->debug("Group with id ".$id." deleted");

	return ({ Success => 1, Message => "Group deleted", groupid => $id});
}

sub _connectdb {
	my $self = shift;
	# get the configuration info to collect tot database
	my $config = $self->app->config;
	my $groupcoll = $config->{database}->{collections}->{groups} ? $config->{database}->{collections}->{groups} : "groups";
	my $groupCollection = $self->mongoDB->db->collection($groupcoll);
	return $groupCollection;
}

1;
__END__