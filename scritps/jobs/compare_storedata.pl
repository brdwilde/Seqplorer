#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use Statistics::R;
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
		'pvalfiles'	=> { type => 'string', array => 1 }
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Retrieve configuration id
my $BITQC_CONFIG_ID = $BitQC->{run_config}->{config_id};

#Retrieve executable variables
my $R_COMMAND = $BitQC->getCommand('R');

#Other
my $REFSAMPLEID       = $BitQC->getRunConfig('refsampleid');
my $COMPSAMPLEID      = $BitQC->getRunConfig('compsampleid');
my $VARIANTSCOLL      = $BitQC->getRunConfig('variantscol');
my $SAMPLESCOLL       = $BitQC->getRunConfig('samplescol');

my $MULTITEST	  = $BitQC->getRunConfig('multitest');
my @PVAL_FILES		= @{$BitQC->getRunConfig('pvalfiles')};

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

######################################################################################
# GET THE INFORMATION FORM THE COMPARRISON
######################################################################################

my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
my $sample_collection   = $mongodb->$SAMPLESCOLL;
my $refsample              = $BitQC->{DatabaseAdapter}->findEntryById(
	collection => $SAMPLESCOLL,
	id         => MongoDB::OID->new( value => $REFSAMPLEID )
);
my $refsamplename = $refsample->{name};
my $compsample              = $BitQC->{DatabaseAdapter}->findEntryById(
	collection => $SAMPLESCOLL,
	id         => MongoDB::OID->new( value => $COMPSAMPLEID )
);
my $compsamplename = $compsample->{name};

my $variants_collection = $mongodb->$VARIANTSCOLL;

# hold comparison results
my %result;

my $all_pvals = $BitQC->{fileadapter}->createFile({
		name => 'allpvals',
		path => $wd,
		ext => '.txt',
		type => 'local'
	});
my $all_pvalpointer = $all_pvals->getWritePointer();

print $all_pvalpointer "ID\tpval\n";
foreach my $file (@PVAL_FILES){
	# open a file pointer to the pval file
	my $pvalfile = $BitQC->{fileadapter}->getLocalFile($file);
	my $pvalpointer = $pvalfile->getReadPointer();

	while (<$pvalpointer>) {
		my @a = split( /\t/, $_ );

		$result{$a[0]}{'crc'} += $a[1];
		$result{$a[0]}{'cvc'} += $a[2];
		$result{$a[0]}{'rrc'} += $a[3];
		$result{$a[0]}{'rvc'} += $a[4];
		$result{$a[0]}{'p'} += $a[5];
		$result{$a[0]}{'cra'} += $a[6];
		$result{$a[0]}{'rra'} += $a[7];
		$result{$a[0]}{'dra'} += $a[8];

		# we compared to sample:
		$result{$a[0]}{'refn'} = $refsamplename;
		$result{$a[0]}{'refid'} = MongoDB::OID->new( value => $REFSAMPLEID);

		print $all_pvalpointer $a[0]."\t".$a[5]."\n";
	}
}
close ($all_pvalpointer);

$BitQC->log_message( message => "Performing multiple testing correction" );

my @pvals;
foreach my $id (sort(keys %result)) {
	push(@pvals, $result{$id}{'p'});
}
  
# Create a communication bridge with R and start R
my $R = Statistics::R->new(r_bin=>$R_COMMAND);
  
# create variable containing p-values
$R->run(
	"data_list <- read.delim( '".$wd."allpvals.txt' , header = TRUE, sep = \"\t\", quote = \"\", dec = \".\")",
	"data_list\$padj <- p.adjust(data_list\$pval, method = c('$MULTITEST'), n = length(data_list\$pval))",
	"write.table(data_list, file = '".$wd."allpvals.txt', append = FALSE, quote = FALSE, sep = \"\t\", eol = \"\n\", na = \"NA\", dec = \".\", row.names = FALSE, col.names = FALSE)"
);

# get back the corrected p values
$all_pvalpointer = $all_pvals->getReadPointer();

# update the p values from the result hash with the multiple testing coorrected ones
while (<$all_pvalpointer>) {
	my @a = split(/\t/);
	#$result{$id}{'p'} += $output_pval[$index];
	$result{$a[0]}{'pc'} += $a[2];
}
close ($all_pvalpointer);

$R->stop();

$BitQC->log_message( message => "Updating database records" );

my $counter =0;
foreach my $id (keys %result) {
	my $values = $result{$id};
		
	# update the sample info with the p values
	$variants_collection->update(
		{ "_id" => MongoDB::OID->new( value => $id ) , "sa.id"    => MongoDB::OID->new( value => $COMPSAMPLEID ) },
		{ '$set'     => { 'sa.$.comp'              => $values } },
		{ 'multiple' => 1 }
	);
	$counter++;
}
$BitQC->log_message( message => "Updated $counter records" );

# finish logging
$BitQC->finish_log( message => "All variants compared" );

