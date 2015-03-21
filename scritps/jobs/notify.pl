#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use BitQC;

######################################################################################
# INITIALISE BITQC MODULE
######################################################################################

# Make BitQC object
# settings will come from environment variables
my $BitQC = new BitQC();

# Load bitqc configuration from the given database
$BitQC->load(
	'script_args' => {
		'subject'		=> { type => 'string' },
		'message'		=> { type => 'string' },
		'finish_master'		=> { type => 'bool' },
		'finish_master_message'		=> { type => 'string' },
		'nextscript'		=> { type => 'string' },
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $CONFIG_ID 				= $BitQC->getRunConfig('config_id');
my $DATABASE_HOST 			= $BitQC->getRunConfig('bitqc_host');
my $DATABASE_PORT 			= $BitQC->getRunConfig('bitqc_port');
my $DATABASE_NAME 			= $BitQC->getRunConfig('bitqc_db');
my $CONFIG_COLL   			= $BitQC->getRunConfig('bitqc_config_coll');
my $MASTER_PROCESS_ID 		= $BitQC->getRunConfig('master_process_log_id');
my $SUBJECT					= $BitQC->getRunConfig('subject');
my $MESSAGE					= $BitQC->getRunConfig('message');
my $FINISH_MASTER			= $BitQC->getRunConfig('finish_master');
my $FINISH_MASTER_MESSAGE	= $BitQC->getRunConfig('finish_master_message');
my $RUN_SUBSEQUENT			= $BitQC->getRunConfig('nextscript');
# emails
my $TO_EMAIL			= $BitQC->getRunConfig('email_to');
my $FROM_EMAIL			= $BitQC->getRunConfig('email_from');
#Queue
my $BITQC_PBS_QUEUE  = $BitQC->{node_config}->{pbs}->{queue};
my $BITQC_PBS_SERVER = $BitQC->{node_config}->{pbs}->{server};

#Get command
my $COMMAND = $BitQC->getCommand('command');

######################################################################################
# SEND THE MAIL
######################################################################################	

foreach my $to_email (@{$TO_EMAIL}){
	$BitQC->sendEmail(
		to 		=> $to_email, 
		from 	=> $FROM_EMAIL, 
		subject	=> $SUBJECT,
		message	=> $MESSAGE
	);
	
	$BitQC->log_message(
		message => "Notification sent to $to_email"
	);
}

######################################################################################
# SUBMIT JOB FOR SUBSEQUENT SCRIPT
######################################################################################	

if ($RUN_SUBSEQUENT){
	
	my $scriptname;
	( $scriptname, my $scriptath, my $scriptext ) = fileparse( $RUN_SUBSEQUENT, '\..*' );
	
	$BitQC->createPBSJob(
		cmd 		=> $RUN_SUBSEQUENT." --config_id $CONFIG_ID --bitqc_host $DATABASE_HOST --bitqc_port $DATABASE_PORT --bitqc_db $DATABASE_NAME --bitqc_config_coll $CONFIG_COLL",
		name 		=> $scriptname,
		job_opts 	=> {
			cput   => '72000',
	#		nodes  => $BITQC_PBS_SERVER # enable this if jobs cannot submit other jobs from the pbs nodes
		} 
	);

	$BitQC->submitPBSJobs();
}

######################################################################################
# FINISH SCRIPT
######################################################################################

# finish logging
$BitQC->finish_log();

if ($FINISH_MASTER) {
	# finish the master process by mimicking the masterprocess by taking its ID
	$BitQC->{log_id} = $MASTER_PROCESS_ID;

	my $message;
	if ($FINISH_MASTER_MESSAGE){
		if (-e $FINISH_MASTER_MESSAGE){
			open( my $read, "<", $FINISH_MASTER_MESSAGE);
			while(<$read>){
				$message .= $_;
			}
			close ($read);
		} else {
			$message = $FINISH_MASTER_MESSAGE;
		}
	}

	$BitQC->finish_log( message => $message );
}
