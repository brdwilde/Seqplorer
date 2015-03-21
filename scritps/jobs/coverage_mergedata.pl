#!/usr/bin/perl -w
use strict;
use warnings;
use Statistics::Descriptive;
use JSON;
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
		'genename'		=> { type => 'string'},
		'chromosome'	=> { type => 'string', array => 1 },
	}
);

######################################################################################
# RETRIEVE VARIABLES FROM BitQC OBJECT AND SET STANDARD VARIABLES
######################################################################################

my @BAM;
@BAM 				= @{$BitQC->getRunConfig('bam')};
my @CHROMOSOMES;
@CHROMOSOMES      	= @{$BitQC->getRunConfig('chromosome')};
my $GENENAME		= $BitQC->getRunConfig('genename');
my $SAMPLEIDS		= $BitQC->getRunConfig('sampleids');
my $MAX_PROCESSES	= $BitQC->{node_config}->{system}->{mappingcores};
my $NORMALIZE		= $BitQC->getRunConfig('normalizeto');
my $MEANNORMALIZE	= $BitQC->getRunConfig('meannormalize');
my $OFFTARGET		= $BitQC->getRunConfig('offtarget');
my $RAWDATA 		= $BitQC->getRunConfig('rawdata');
my $THRESHOLD 		= $BitQC->getRunConfig('threshold');
my $BININTERVAL		= $BitQC->getRunConfig('bininterval');
my $EXPORT			= lc($BitQC->getRunConfig('export'));
my $PLOTSCOLL		= $BitQC->getRunConfig('plotscoll');

#Supported export formats
my %EXPORT_FORMATS=(
	pdf => "pdf",
	json => "json",
	html => "html",
	txt => "txt",
	mongodb => "mongodb",
);

###########################################################################
# Change to ths working directory
###########################################################################

# create temp dir as a working dir and change to it
my $wd = $BitQC->workingDir();

######################################################################################
# GET THE COVERAGE DATA FORM THE GET DATA SCRIPT
######################################################################################

my @bamfiles = $BitQC->{fileadapter}->getLocal(\@BAM,'bam');

# get the flagstats for the bam files to determine global statistics
#my $fork_manager= new Parallel::ForkManager(1);

#collect all data and report back to user
foreach my $bamfile (@bamfiles){

	my $bamname = $bamfile->getInfo('name');

	my $filename = $wd.$bamname.'';
	$filename =~ s/\.//g;
	my $statsfilename = $filename.'.json.gz';

	# create local file object
	my $statsfile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
		'filetype' => 'json',
		'file' => $statsfilename,
	    'type' => 'local',
	    'ext' => '.json.gz'
	});

	# create file pointer for writing
	my $statsfilepointer = $statsfile->getWritePointer();

	my $rawdatawritepointer;
	if ($RAWDATA){
		# open file for reading chromosome specific raw data
		my $rawdatafile = $BitQC->{fileadapter}->createFile( {
			'compression' => 'gzip',
			'filetype' => 'txt',
			'file' => $filename.'_raw.txt.gz',
		    'type' => 'local',
		    'ext' => '.txt.gz'
		});

		# create file pointer for reading
		$rawdatawritepointer = $rawdatafile->getWritePointer();
	}

	my $stats = Statistics::Descriptive::Full->new();
	my %stats;
	%stats = %{$BitQC->getRunConfig($bamname.'_stats')} if ($BitQC->getRunConfig($bamname.'_stats'));
	$stats{'stats'}{'totalbases'} = 0;
	$stats{'stats'}{'threshbases'} = 0 if ($THRESHOLD);
	$stats{'stats'}{'threshold'} =  '>='.$THRESHOLD if ($THRESHOLD);
	$stats{'stats'}{'normalizationfactor'} = 1 unless ($stats{'stats'}{'normalizationfactor'});
	
	foreach my $chr (@CHROMOSOMES){

		# open file for reading chromosome specific raw data
		my $chrdatafile = $BitQC->{fileadapter}->createFile( {
			'compression' => 'gzip',
			'filetype' => 'txt',
			'file' => $filename."_".$chr.'_raw.txt.gz',
		    'type' => 'local',
		    'ext' => '.txt.gz'
		});

		# create file pointer for reading
		my $chrdatareadpointer = $chrdatafile->getReadPointer();
		
		my @coverage;
		while (<$chrdatareadpointer>){
			# merge all raw data in one file if required
			print $rawdatawritepointer $_ if ($RAWDATA);

			chomp;
			my @line = split("\t", $_);

			$line[4] = $line[4]*$stats{'stats'}{'normalizationfactor'};

			$stats{'stats'}{'totalbases'}++;
			$stats{'stats'}{'threshbases'}++ if ($THRESHOLD && $line[4] >= $THRESHOLD);

			push (@coverage, $line[4]);
		}
		close ($chrdatareadpointer);
		$stats->add_data(@coverage);
	}

	if ($MEANNORMALIZE){
		#$stats->add_data(@coverage);
		my $mean = $stats->mean();
		$stats{'stats'}{'meannorm'} = $mean;
		#$stats->clear();
		my @coverage;
		foreach my $cov (@{ $stats->{data} }){
			push (@coverage,$cov/$mean);
			undef($cov)
		}
		$stats->clear();
		# recalculate the normalized dataset
		$stats->add_data(@coverage);
		$stats{'stats'}{'normalizationfactor'} = $stats{'stats'}{'normalizationfactor'}/$mean;
		$BININTERVAL = $BININTERVAL*$stats{'stats'}{'normalizationfactor'};
	}
	
	# calculate the stats

	#$stats->add_data(@coverage);
	$stats{'stats'}{'mean'} = $stats->mean();		
	$stats{'stats'}{'max'} = $stats->quantile(4);
	$stats{'stats'}{'min'} = $stats->quantile(0);
	$stats{'stats'}{'median'} = $stats->quantile(2);
	$stats{'stats'}{'Q1'} = $stats->quantile(1);
	$stats{'stats'}{'Q3'} = $stats->quantile(3);
	$stats{'stats'}{'stdev'} = $stats->standard_deviation();
	# determine bins for frequency dist plot
	my @bin;
	my $i = 0;
	while ($i <= $stats{'stats'}{'max'}){
		push (@bin, $i) if $i >= $stats{'stats'}{'min'};
		$i += $BININTERVAL;
	}
	# add last bin
	push (@bin, $i);

	$stats{'stats'}{'freq_dist'} = $stats->frequency_distribution_ref(\@bin);

	my $json = encode_json(\%stats);

	print $statsfilepointer $json."\n";

	$stats->clear();

	#$fork_manager->finish;
}
#Wait till all processes are finished
#$fork_manager->wait_all_children;

my %globalstats;

my $rawdatawritepointer;
if ($RAWDATA){
	# open file for reading chromosome specific raw data
	my $rawdatafile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
		'filetype' => 'txt',
		'file' => 'raw_coverage.txt.gz',
	    'type' => 'local',
	    'ext' => '.txt.gz'
	});

	# create file pointer for reading
	$rawdatawritepointer = $rawdatafile->getWritePointer();

	print $rawdatawritepointer "chromosome\tposition\tregion\tfile\tcoverage\n";
}

foreach my $bam (@BAM){
	my $bamfile = $BitQC->{fileadapter}->createFile($bam);

	my $bamname = $bamfile->getInfo('name');

	# get the global stats from the config for this bam file
	#$globalstats{$bamname} = $BitQC->getRunConfig($bamname.'_stats');

	my $filename = $wd.$bamname.'';
	$filename =~ s/\.//g;

	my $statsfilename = $filename.'.json.gz';

	# create local file object
	my $statsfile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
		'filetype' => 'json',
		'file' => $statsfilename,
	    'type' => 'local',
	    'ext' => '.json.gz'
	});

	# create file pointer for writing
	my $statsfilepointer = $statsfile->getReadPointer();

	my $json;
	while (<$statsfilepointer>){
		$json .= $_;
	}

	$globalstats{$bamname} = decode_json($json) if ($json);

	if ($RAWDATA){
		# open file for reading chromosome specific raw data
		my $rawdatafile = $BitQC->{fileadapter}->createFile( {
			'compression' => 'gzip',
			'filetype' => 'txt',
			'file' => $filename.'_raw.txt.gz',
		    'type' => 'local',
		    'ext' => '.txt.gz'
		});

		# create file pointer for reading
		my $rawdatareadpointer = $rawdatafile->getReadPointer();
		
		while (<$rawdatareadpointer>){
			print $rawdatawritepointer $_;
		}

	}

}


if ($EXPORT eq $EXPORT_FORMATS{json}){

	# create local file object
	my $resultsfile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
		'filetype' => 'json',
		'file' => $wd.$GENENAME.'_coverage.json.gz',
	    'type' => 'local',
	    'ext' => '.json.gz'
	});

	# create file pointer for writing
	my $resultsfilepointer = $resultsfile->getWritePointer();

	print $resultsfilepointer encode_json(\%globalstats);

	close($resultsfilepointer);

} elsif ($EXPORT eq $EXPORT_FORMATS{mongodb}){

	my %plotrecord = (
		"sampleids" => $SAMPLEIDS,
		"data" => {
			"Filename" => [],
		},
		"factor" => ["Filename"],
		"header" => ["Filename"],
		"name" => "Coverage statistics for ".$GENENAME,
	);

	my %freqdistrecord = (
		"data" => { 
			"Bin" => [],
			"Filename" => [],
			"Value" => []
		},
		"factor" => ["Filename"],
		"header" => ["Bin","Filename", "Value"],
		"name" => "Cumulative coverage distribution for ".$GENENAME
	);

	my @stats = (keys %{$globalstats{(keys %globalstats)[0]}{'stats'}});
	foreach my $stat (@stats){
		if ($stat ne 'freq_dist'){
			push (@{$plotrecord{header}},$stat);
		}
	}

  	foreach my $bamname (keys %globalstats){
		push (@{$plotrecord{data}{Filename}},$bamname);
		foreach my $stat (@stats){
			if ($stat ne 'freq_dist'){
				push (@{$plotrecord{data}{$stat}},$globalstats{$bamname}{'stats'}{$stat});
			} else {
				my $sum = 0;
				foreach my $bin ( keys %{$globalstats{$bamname}{'stats'}{$stat}} ){
					$sum += $globalstats{$bamname}{'stats'}{$stat}{$bin};
				}
				# print the data itself
				my $fraction = 1;
				foreach my $bin ( sort {$a<=>$b} keys %{$globalstats{$bamname}{'stats'}{$stat}} ){
					push (@{$freqdistrecord{data}{Bin}},$bin);
					push (@{$freqdistrecord{data}{Filename}},$bamname);
					push (@{$freqdistrecord{data}{Value}},$fraction);
					# remove the fraction in this bin form the total
					$fraction -= ($globalstats{$bamname}{'stats'}{$stat}{$bin}/$sum) if ($sum);
				}
			}
		}
	}

	my $mongodb = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
	my $plots_collection = $mongodb->$PLOTSCOLL;

	
	my $freqdistrecord = $plots_collection->insert( \%freqdistrecord, { safe => 1 } );

	# add the plot id of the frequency distribution plot to the stats plot data
	$plotrecord{cumulativeid} = $freqdistrecord->value;
	my $plotrecord = $plots_collection->insert( \%plotrecord, { safe => 1 } );

	print "$plotrecord\n";
	print "$freqdistrecord\n";

} elsif ($EXPORT eq $EXPORT_FORMATS{txt}){

 	###########################################################################
 	# GENERATE TXT RESPONSE
 	###########################################################################	

 	# print the global coverage statistics per bam file

	# create global stats file object
	my $regionstatsfile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
		'filetype' => 'txt',
		'name' => $GENENAME.'_coverage_stats',
		'path' => $wd,
		'type' => 'local',
		'ext' => '.txt.gz'
	});

	# create file pointer for writing
	my $regionstatsfilepointer = $regionstatsfile->getWritePointer();

	# create global freq dist file object

	my $regionfreqdistfile = $BitQC->{fileadapter}->createFile( {
		'compression' => 'gzip',
		'filetype' => 'txt',
		'name' => $GENENAME.'_freq_dist',
		'path' => $wd,
		'type' => 'local',
		'ext' => '.txt.gz'
	});
	# create file pointer for writing
	my $regionfreqdistfilepointer = $regionfreqdistfile->getWritePointer();

	my @stats = (keys %{$globalstats{(keys %globalstats)[0]}{'stats'}});
	print $regionstatsfilepointer "File\t";
	foreach my $stat (@stats){
		print $regionstatsfilepointer $stat."\t" unless ($stat eq 'freq_dist');
	}
	print $regionstatsfilepointer "\n";

	# the frequency distribution is printed to another file
	# print the bin header
	print $regionfreqdistfilepointer "file\tbin\tvalue\n";
	# cycle over the coverage stats
	foreach my $bamname (keys %globalstats){
		print $regionstatsfilepointer $bamname."\t";
		foreach my $stat (@stats){
			if ($stat eq 'freq_dist'){
				# the frequency distribution is printed to another file
				my $sum = 0;
				foreach my $bin ( keys %{$globalstats{$bamname}{'stats'}{$stat}} ){
					$sum += $globalstats{$bamname}{'stats'}{$stat}{$bin};
				}
				# print the data itself
				my $fraction = 1;
				foreach my $bin ( sort {$a<=>$b} keys %{$globalstats{$bamname}{'stats'}{$stat}} ){
					print $regionfreqdistfilepointer $bamname."\t"
						.$bin."\t"
						.$fraction."\n";
					# remove the fraction in this bin form the total
					$fraction -= ($globalstats{$bamname}{'stats'}{$stat}{$bin}/$sum) if ($sum);
				}
			} else {
				#print the stats to the output file
				print $regionstatsfilepointer $globalstats{$bamname}{'stats'}{$stat}."\t";
			}
		}
		print $regionstatsfilepointer "\n";
	}
	close $regionstatsfilepointer;
	close $regionfreqdistfilepointer;

}
