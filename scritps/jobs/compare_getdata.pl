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
		'chromosome'	=> { type => 'string' },
		'pval_outfile'	=> { type => 'string' },
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

#Other
my $REFSAMPLEID       = $BitQC->getRunConfig('refsampleid');
my $REFBAM 		      = $BitQC->getRunConfig('refbam');
my $COMPSAMPLEID      = $BitQC->getRunConfig('compsampleid');
my $COMPBAM       	  = $BitQC->getRunConfig('compbam');
my $VARIANTSCOLL      = $BitQC->getRunConfig('variantscol');
my $INTERVAL		  = $BitQC->getRunConfig('interval');
my $CHROMOSOME        = $BitQC->getRunConfig('chromosome');
my $PVAL_OUTFILE	  = $BitQC->getRunConfig('pval_outfile');

#Get command
my $SAMTOOLS_COMMAND = $BitQC->getCommand('samtools');

#Get index for given organismbuild
my $SAMTOOLS_INDEX = $BitQC->getGenomeIndex('samtools');

######################################################################################
# COMPARE THE VARIATNS FOUND ON CHROMOSOME $CHROMOSOME
######################################################################################

# set query timeout to infinite value
$MongoDB::Cursor::timeout = -1;
my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();

my $variants_collection = $mongodb->$VARIANTSCOLL;

# hold compassison results
my %result;

# store values for CGH profile
my @cgh_log;
my @cgh_chr;
my @cgh_pos;

# build the query
my $cursor = $variants_collection->find({
	'sa.id' => { 
		'$in' => [ 
			MongoDB::OID->new( value => $COMPSAMPLEID )
		]
	},
	'c' => $CHROMOSOME
});

# get only fields we need
$cursor->fields({
	"_id" => 1,
	"sa.id" => 1,
	"c" => 1,
	"e" => 1,
	"t" => 1,
	"r" => 1,
	"vp" => 1,
	"v" => 1,
	"vr" => 1,
	"a" => 1
});

# make reading form slave nodes OK
$cursor->slave_okay(1);

# get all matching variants
my @docs = $cursor->all;
my %docs;
my $totalrecs = @docs;

$BitQC->log_message( message => "Working on $totalrecs variant positions for chromosome $CHROMOSOME" );

# create a position based hash
foreach my $doc (@docs) {
	$docs{$doc->{vp}} = $doc;
};
# free memory?
undef(@docs);

my $refbam = $BitQC->{fileadapter}->getLocalFile($REFBAM,'bam');
my $refbamfile = $refbam->getInfo('file');
my $compbam = $BitQC->{fileadapter}->getLocalFile($COMPBAM,'bam');
my $compbamfile = $compbam->getInfo('file');

# some variables
my $start = 0;
my $end = 0;
my %compcov;
my %refcov;

# get the positions and sort
my @pos = sort {$a <=> $b} (keys %docs);

my $i = 0;
foreach my $pos (@pos){
	# to speed up the process of getting the raw data we do not do this for each variant individually 
	# but instead group variants that are les than $INTERVAL bases appart, this reduces the number of
	# requests to the BAM files
	if ($pos >= $end){
		# create the new region
		$start = $pos;
		my $j = 0;
		my $endindex = $i + $j;
		while(defined($pos[$i + $j]) && ($pos[$i + $j] - $pos) <= $INTERVAL){
			$endindex = $i + $j;
			$j++;
		}
		$endindex = $endindex - 1 if (!defined($pos[$endindex]));
		$end = $pos[$endindex];

		# get all the positions in between this position and the $INTERVAL next elements
		my @positions = @pos[$i..$endindex];
		my $region = $CHROMOSOME.":".$start."-".$end;
		# get the coverage data
		%compcov = _getcoverage($compbamfile, $region, \@positions);
		%refcov = _getcoverage($refbamfile, $region, \@positions);
	}
	# get the variant record
	my $doc = $docs{$pos};

	# parse the variant string to get the reference and variant base
	my $rfba = $doc->{"r"};
	my $altba = $doc->{"a"};
	my $variantid = $doc->{"_id"}->{value};

	if ($doc->{"t"} eq "del"){
		my $vcfrfba = $doc->{"vr"};
		my $vcfaltba = $rfba;
		$vcfrfba =~ s/$rfba//;
		$vcfaltba =~ s/$altba//;
		$rfba = $vcfrfba;
		$altba = "-".length($vcfaltba).$vcfaltba;
	}

	if ($doc->{"t"} eq "ins"){
		my $vcfrfba = $doc->{"vr"};
		my $vcfaltba = $altba;
		$vcfrfba =~ s/$rfba//;
		$vcfaltba =~ s/$rfba//;
		$rfba = $vcfrfba;
		$altba = "+".length($vcfaltba).$vcfaltba;
	}

	# variables to hold the coverage
	my $comprefcov = 0;
	my $refrefcov = 0;
	my $compvarcov = 0.00000000000000001; 	# to ensure calculation of positions deleted in the sample we set $compvarcov to a verry low value
	my $refvarcov = 0;

	$comprefcov = $compcov{$pos}{$rfba} if ($compcov{$pos}{$rfba});
	$compvarcov = $compcov{$pos}{$altba} if ($compcov{$pos}{$altba});
	$refrefcov = $refcov{$pos}{$rfba} if ($refcov{$pos}{$rfba});;
	$refvarcov = $refcov{$pos}{$altba} if ($refcov{$pos}{$altba});		

	# calculate the variant base proportions in the sample
	my $cra = $compvarcov/($compvarcov+$comprefcov);
	my $rra = 0;
	if ($refvarcov || $refrefcov){
		$rra = $refvarcov/($refvarcov+$refrefcov);
	}

	# the coverage was
	$result{$variantid}{'crc'} = $comprefcov;
	$result{$variantid}{'cvc'} = $compvarcov;
	$result{$variantid}{'rrc'} = $refrefcov;
	$result{$variantid}{'rvc'} = $refvarcov;
	# calculate the p value

	#	        sample1 sample2
	#  ref		x1		y1		| ref total
	#  var		x2		y2		| var total
	#           --------------
	#           total1	total2	  grand total
	# _contingency_test($x1, $y1, $x2, $y2);

	$result{$variantid}{'p'} = _contingency_test($comprefcov, $refrefcov, $compvarcov, $refvarcov);
	$result{$variantid}{'cra'} = $cra;
	$result{$variantid}{'rra'} = $rra;
	# calculate the difference in variant coverage ratio
	$result{$variantid}{'dra'} = $cra - $rra;

	# keep memory foorprint low?
	delete($docs{$pos});
	$i++;
}

######################################################################################
# WRITE RESULTS TO OUTPUT FILES
######################################################################################

open(my $pvalpointer, ">", $PVAL_OUTFILE);

foreach my $id (keys %result){
	print $pvalpointer $id;
	print $pvalpointer "\t".$result{$id}{'crc'};
	print $pvalpointer "\t".$result{$id}{'cvc'};
	print $pvalpointer "\t".$result{$id}{'rrc'};
	print $pvalpointer "\t".$result{$id}{'rvc'};
	print $pvalpointer "\t".$result{$id}{'p'};
	print $pvalpointer "\t".$result{$id}{'cra'};
	print $pvalpointer "\t".$result{$id}{'rra'};
	print $pvalpointer "\t".$result{$id}{'dra'};
	print $pvalpointer "\n";
}
close($pvalpointer);

# finish logging
$BitQC->finish_log( message => "End job: Chromosome $CHROMOSOME variants processed" );

######################################################################################
# FUNCTIONS
######################################################################################

# this function wil return a pval for a 2 x 2 contingency table
# if all of the values are > 5 fisher test fwill be used
#          sample1  sample2
#  var		x1		y1		| var total
#  ref		x2		y2		| ref total
#           --------------
#           total1	total2	  grand total
# use: $pval = contingency_test(x1, y1, x2, y2);
use Statistics::ChisqIndep;
use Text::NSP::Measures::2D::Fisher::twotailed;

sub _contingency_test {

	my $x1 = shift;
	my $y1 = shift;
	my $x2 = shift;
	my $y2 = shift;
	my $pval;

# commented code will allow calculation of chi sqrd test (for speedup) if count values are high
# the lines where removed as we did no see a significant speedup for exome datasets
#	if ( $x1 < 6 || $y1 < 6 || $x2 < 6 || $y2 < 6 ) {

		#          pool1  pool2
		#  tumor    n11      n12 | n1p
		#  const    n21      n22 | n2p
		#           --------------
		#           np1      np2   npp
		$pval = calculateStatistic(
			n11 => $x1,
			n1p => $x1 + $y1,
			np1 => $x1 + $x2,
			npp => $x1 + $x2 + $y1 + $y2,
		);
#	} else {
#		my @obs = ( [ $x1, $y1 ], [ $x2, $y2 ] );
#		my $chi = new Statistics::ChisqIndep;
#		$chi->load_data( \@obs );
#		$pval = $chi->{p_value};
#	}
	return ($pval);
}

# function to get the raw coverage data for a list of positions for a bam file

sub _getcoverage {
	my $bamfile = shift;
	my $region = shift;
	my $positions = shift;

	my @positions = @{$positions};

	# return will hold counts for each position for each base
	my %return;

	# get the first position we search
	my $searchpos = shift(@positions);

	open(my $cov, "-|", "$SAMTOOLS_COMMAND mpileup -B -r $region -f $SAMTOOLS_INDEX $bamfile") or die $!;

	while(<$cov>){
		my @a = split( /\t/, $_ );
	
		#$a[0] =~ /^chr(.+)/; # chop off the 'chr' part of the chromosome
		#my $chr  = $a[0];
		my $pos  = $a[1];
		while ($pos > $searchpos){
			$searchpos = shift(@positions);
		}
		if ($pos == $searchpos){
			# get new searchpos
			$searchpos = shift(@positions);

			# get the relevant data and store in the return hash	
			my $rfba = uc( $a[2] ); # the reference base
			my $seq  = $a[4]; # the bases sequenced
		
			# remove indels from $seq string
			while ( $seq =~ m/(\+|\-)([0-9]+)([ACGTNacgtn]+)/ ) {
				my $cutoutlength = length($1) + length($2) + $2;
				# do not use length ($3) because a snp might follow an indel!!!
				my $indel = uc(substr( $seq, $-[0], $cutoutlength, "" ));
				$return{$pos}{$indel} += 1;
			}
			# remove mapping quality scores
			while ( $seq =~ m/(\^)(.)/ ) {
				substr( $seq, $-[0], 2, "" );
			}
		
			# split al the bases
			my @base = split( //, $seq );
			
			# count the occurence of the reference and non reference bases
			foreach (@base) {
				if ($_ eq '.' || $_ eq ','){
					$return{$pos}{$rfba} += 1;
				} else {
					$return{$pos}{uc($_)} += 1;
				}
			}
		}
	}
	return %return;
}
