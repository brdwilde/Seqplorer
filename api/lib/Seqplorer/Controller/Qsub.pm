package Seqplorer::Controller::Qsub;
use Mojo::Base 'Mojolicious::Controller';
use strict;
use PBS::Client;
use BitQC;
use Data::Dumper;
use Mojo::JSON 'j';
use Mojo::ByteStream 'b';


# This action will render a template
sub submit {
	my $self = shift;
	my $json   = Mojo::JSON->new;
	my $script = $self->param('script');
	my $config = j( b( $self->param('config') )->encode('UTF-8') );
	$self->app->log->debug("## QSUB submitted for $script config: ".Dumper($config));
	# config
	my $DATABASE_HOST    = $config->{'bitqc_host'};
	my $DATABASE_PORT    = $config->{'bitqc_port'};
	my $DATABASE_NAME    = $config->{'bitqc_db'};
	my $CONFIG_COLL      = $config->{'bitqc_config_coll'};
	my $SERVER_ID        = $config->{'server_id'};
	my $SERVERCOLLECTION = $config->{'bitqc_server_coll'};

	# INITIALISE BITQC MODULE

	#Make BitQC object
	my $BitQC = new BitQC();

	# create the database connection the user requested
	$BitQC->{run_config} = {
		'bitqc_host'        => $DATABASE_HOST,
		'bitqc_port'        => $DATABASE_PORT,
		'bitqc_db'          => $DATABASE_NAME,
		'config_coll' => $CONFIG_COLL,
		'server_id'         => $SERVER_ID,
		'server_coll' => $SERVERCOLLECTION,
	};
	$BitQC->{DatabaseAdapter} = new DatabaseAdaptor( $BitQC->{run_config} );

	# create the config and load the server object
	my $currentscript = $0;
	$0 = 'qsubdeamon';   # temporary set the script name to this arbitraty value
	my $config_id = $BitQC->createConfigurationEntry($config);
	$self->app->log->debug("## QSUB submitted for $script assigned config id: $config_id");
	$0 = $currentscript;
	$BitQC->loadServer();

	# get the path where the scripts are installed
	my $BITQC_SCRIPTS_PATH =
	  $BitQC->{node_config}->{executables}->{scripts}->{path};
	my $SCRIPT = $BITQC_SCRIPTS_PATH . $script;

	# CREATE AND SUBMIT THE JOB
	my %job_opts = (
		cput  => '72000', # make sure we can run a long job...
	);

	$BitQC->createPBSJob(
		cmd => $SCRIPT." --config_id $config_id --bitqc_host $DATABASE_HOST --bitqc_port $DATABASE_PORT --bitqc_db $DATABASE_NAME --config_coll $CONFIG_COLL",
		name => 'qsubdeamon_'.$script,
		job_opts => \%job_opts
	);

	my $pbsid = $BitQC->submitPBSJobs();
	$self->app->log->debug("## QSUB submitted for $script assigned pbs id: $pbsid");
	$self->render(
		json => {
			'jobid'     => $pbsid,
			'config_id' => $config_id
		}
	);
}

sub get {
	my $self = shift;

	# Render template "example/welcome.html.ep" with message
	$self->render(
		message => 'Welcome to the Mojolicious real-time web framework!');
}
1;