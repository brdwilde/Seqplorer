package Seqplorer::Model::User;
use strict;
use warnings;
use DateTime;
use Carp qw/croak/;
use Mojo::Base -base;
use Mojo::Util qw(encode md5_sum);
use List::Util qw(first);
use Mango::BSON ':bson';
use Scalar::Util qw(looks_like_number);


has [qw/ app mongoDB /];

sub get {
    my $self = shift;
    my $userId = shift;

    # get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# my $cache = $self->app->cache;
	# if( defined $cache->get($userId) ){
	# 	$self->app->log->debug("Cache hit for request to get user with id: $userId");
	# 	return $cache->get($userId);
	# }
	# $self->app->log->debug("Cache miss for request to get user with id: $userId");

	# get the data in the database
	my $userdata = $userCollection->find_one({ '_id' => Mango::BSON::ObjectID->new($userId)});

	if ($userdata){
		return ({ Success => 1, Message => "User found", userdata => $userdata});
	}
	return ({ Success => 0, Message => "User not found", userid => $userId})
}

sub getid {
    my $self = shift;
    my $email = shift;
    my $password = shift;

    # get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# get the data in the database, only for active users
	my $userdata = $userCollection->find_one({ 'email' => uc($email), 'password' => $password, 'active' => 1});

	if ($userdata){
		return ({ Success => 1, Message => "User found", userid => $userdata->{_id}, userdata => $userdata});
	}
	return ({ Success => 0, Message => "User ".$email." not found"})
}

sub create {
	# get the input data
	my $self = shift;
	my $userdata = shift;

	# get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# check the input data for validity
	$userdata->{email} = lc ($userdata->{email});
	# make sure the user provided an email adress and a password
	if (!$userdata->{email} || $userdata->{email} eq '' || !($userdata->{email} =~ /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,8}$/)){
		# only valid email is allowed (simple email format is chosen)
		return ({ Success => 0, Message => "Please provide a valid e-mail adress" });
	}
	if (!$userdata->{password} || $userdata->{password} eq ''){
		return ({ Success => 0, Message => "Please provide a valid password" });
	}

	# encrypt the password
	$userdata->{password} = md5_sum($userdata->{password});

	# new users will be created inactive and at the current time with default role
	$userdata->{role} = ['user'];
	$userdata->{active} = 0;
	$userdata->{member_since} = DateTime->now;

	# check for duplicate user e-mails
	if($userCollection->find_one({ 'email' => $userdata->{'email'} })) {
		return ({ Success => 0, Message => "User with e-mail adress ".$userdata->{'email'}." already registered." });
	}

	# create the new user and report back
	my $userDocId = $userCollection->save($userdata);
	$self->app->log->debug("Saved user doc to mongo: ".$userDocId);

	# now create the group for the user
	my $usernamestring = '';
	$usernamestring .= ' '.$userdata->{lastname} if $userdata->{lastname};
	$usernamestring .= ' '.$userdata->{firstname} if $userdata->{firstname};
	$usernamestring .= ' '.$userdata->{email} unless $usernamestring;

	my %groupdata = {
		'admin'=>$userDocId,
		'users'=>[$userDocId],
		'approved'=>[$userDocId],
		'description'=>'Private group of user'.$usernamestring,
		'name'=>'Private group',
		'public'=>'no'
	};

	my $groupModel = $self->model('group');
	my $groupuserReturn = $groupModel->create(\%groupdata);

	# check for duplicate user e-mails
	if(!$groupuserReturn->{Success}) {
		return ({ Success => 0, Message => "Group for user with e-mail adress ".$userdata->{'email'}." could not be created." });
	}

	#if a user was invited a group will be posted, we add the user to that group
	if ($userdata->{group}){
		$groupuserReturn = $groupModel->adduser($userDocId,$userdata->{group},1);
	}

	# retrun success
	return ({ Success => 1, Message => "User created", userid => $userDocId});
}

sub update {
	# get the input data
	my $self = shift;
	my $id = shift;
	my $updatedata = shift;

	# get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# get the data in the database
	my $userdata = $userCollection->find_one({ '_id' => Mango::BSON::ObjectID->new($id)});

	# change the info of the db record with the updated info
	foreach my $key (keys %{$updatedata}){
		$userdata->{$key} = $updatedata->{$key};
	}

	# check the input data for validity before we go back to the database	
	# if user waths to update his email
	if ($userdata->{email}){
		$userdata->{email} = lc ($userdata->{email});

		# make sure the user provided a valid email
		if ($userdata->{email} eq '' || !($userdata->{email} =~ /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,8}$/)){
			# only valid email is allowed (simple email format is chosen)
			return ({ Success => 0, Message => "Please provide a valid e-mail adress" });
		}
		# and it does not already exist in another record
		# cannot allow user to update email to existing email from other user
		my $cursor = $userCollection->find({ 'email' => $userdata->{'email'} });
		while (my $doc = $cursor->next){
			unless ($doc->{_id} eq $id) {
				return ({ Success => 0, Message => "User with e-mail adress ".$userdata->{'email'}." already registered." });
			}
		}
	}

	# make sure we only update passwords with valid passwords
	if ($userdata->{password}){
		if ($userdata->{password} eq ''){ #TODO: make password requirements more strict
			return ({ Success => 0, Message => "Please provide a valid password" });
		}
	}

	#encode the password
	$userdata->{password} = md5_sum($userdata->{password});

	# set the record update timestamp
	$userdata->{lastupdate} = DateTime->now;

	# update the user record
	$userCollection->update({'_id' => Mango::BSON::ObjectID->new($id)},$userdata);		
	$self->app->log->debug("Updates performed to doc ".$id);
	return ({ Success => 1, Message => "User record updated", userid => $id});
}

sub addrole {
	# get the input data
	my $self = shift;
	my $id = shift;
	my $role = shift;

	# get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# get the data in the database
	my $userdata = $userCollection->find_one({ '_id' => Mango::BSON::ObjectID->new($id)});

	# add the role
	use Data::Dumper::Simple;
	print Dumper (@{$userdata->{'role'}});
	if (grep(/$role/, @{$userdata->{'role'}})){
		return ({ Success => 0, Message => "User already has role ".$role });
	}

	# add the role
	push (@{$userdata->{'role'}}, $role);
	# set the record update timestamp
	$userdata->{lastupdate} = DateTime->now;

	# update the user record
	$userCollection->update({'_id' => Mango::BSON::ObjectID->new($id)},$userdata);		
	$self->app->log->debug("Role added to doc ".$id);
	return ({ Success => 1, Message => "Role ".$role." added", userid => $id});
}

sub revokerole {
	# get the input data
	my $self = shift;
	my $id = shift;
	my $role = shift;

	# get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# get the data in the database
	my $userdata = $userCollection->find_one({ '_id' => Mango::BSON::ObjectID->new($id)});

	# add the role
	if (!grep(/$role/, @$userdata->{'role'})){
		return ({ Success => 0, Message => "User does not have role ".$role });
	}

	# remove the role
	my @oldroles = @$userdata->{'role'};
	$userdata->{'role'} = undef;
	foreach my $oldrole (@oldroles){
		push (@$userdata->{'role'}, $oldrole) unless ($role eq $oldrole);
	}
	# set the record update timestamp
	$userdata->{lastupdate} = DateTime->now;

	# update the user record
	$userCollection->update({'_id' => Mango::BSON::ObjectID->new($id)},$userdata);		
	$self->app->log->debug("Role revoked from doc ".$id);
	return ({ Success => 1, Message => "Role ".$role." revoked", userid => $id});
}

sub activate {
	# get the input data
	my $self = shift;
	my $id = shift;

	# get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# get the data in the database
	my $userdata = $userCollection->find_one({ '_id' => Mango::BSON::ObjectID->new($id)});

	# change the info of the db record with the updated info
	$userdata->{active} = 1;

	# set the record update timestamp
	$userdata->{lastupdate} = DateTime->now;

	# update the user record
	$userCollection->update({'_id' => Mango::BSON::ObjectID->new($id)},$userdata);		
	$self->app->log->debug("User with id ".$id." activated");
	return ({ Success => 1, Message => "User activated", userid => $id});
}

sub delete {
 	# get the input data
	my $self = shift;
	my $id = shift;

	# get the configuration info to collect tot database
	my $config = $self->app->config;
	my $usercoll = $config->{database}->{collections}->{users} ? $config->{database}->{collections}->{users} : "users";
	my $userCollection = $self->mongoDB->db->collection($usercoll);

	# update the user record
	$userCollection->remove({'_id' => Mango::BSON::ObjectID->new($id)});		
	$self->app->log->debug("User with id ".$id." deleted");
	return ({ Success => 1, Message => "User deleted", userid => $id});
}

1;
__END__