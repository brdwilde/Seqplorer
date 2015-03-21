#Handle fastq files


#Steps that are taken
#1. Download
#2. Unzip
#3. Paired 1 & Paired 2
#4. Merged 1+2
#5. Start mapping

use Pod::Usage;
use Data::Dumper::Simple;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use File::Basename;
use Getopt::Long;
use strict;
use warnings;
use Archive::Extract;
use modules::SequencingTools::lib::SequencingTools;

#Subroutines
sub get_file_name($);
sub cat;
sub unzip;
sub is_archive;
sub remove_files;

#Variables
my $sample_name;
my $sample_name_alternative;
my $dir_source;
my $dir_destination;
my $dir_destination_sample;
my $dir_source_first_seq_sample;
my $dir_source_second_seq_sample;
my $dir_source_first_seq;
my $version_number;
my $version_original_date;
my $version_date;
my $version_author;
my $version_bugs;
my $unzip_files;
my $merge_files;
my $last_step;

#Program information constants
$version_number			="2.1";
$version_original_date	="21/09/2011";
$version_date			="12/10/2011";
$version_author			="Wouter De Meester";
$version_bugs			="no bugs reported";

#General constants
my $FTP_DIRECTORY="ftpserver_";

# get the command line arguments
my $man         	= 0;
my $help        	= 0;
my $version     	= 0;
my $quiet       	= 0;
my $mongoserver 	= 0;
my $mongoport   	= 0;
my $mongodb     	= 0;
my $to_email		= 0;
my $from_email		= 0;
my $config_id   	= 0;
my $subject			= 0;
my $message			= 0;
my $server_config	= 0;
my $analysis_server	= 0;
my $name			= 0;
my $command			= 0;
my $queue			= 0;
my $wallt			= 0;
my $cput			= 0;
my $info			= 0;
my $remove			= 0;
my $connection;
my $database;

#Uploadway constants
my $UPLOAD_MANUAL="manual";
my $UPLOAD_FTP="ftp";

#File formats constants
my $FORMAT_FASTQ	="fastq";
my $FORMAT_VCF		="vcf";
my $FORMAT_SAM		="sam";

#Fastq companies
my $COMPANY_ILLUMINA="illumina";


#Don't change the following code
#---------------------------------------------------------
#---------------------------------------------------------


#Arguments
pod2usage("$0: No arguments specified!\n") if ( @ARGV == 0 );
GetOptions(
	'help|?'     		=> \$help,
	man          		=> \$man,
	'version|v'  		=> \$version,
	'quiet|q'    		=> \$quiet,
	'config=s'  		=> \$config_id,
	'server_config=s'   => \$server_config,
	'analysis_server=s'	=> \$analysis_server,
	'name=s'   			=> \$name,
	'to_email=s' 		=> \$to_email,
	'from_email=s' 		=> \$from_email,
	'command=s'   		=> \$command,
	'queue=s'   		=> \$queue,	
	'info|i'			=> \$info,
	'remove|r'			=> \$remove
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $man;

#Print program information
if($info){
	print "Program info: \n";
	print "\tAuthor:\t\t $version_author\n";
	print "\tCreation date:\t $version_original_date\n";
	print "\tVersion:\t $version_number\n";
	print "\tVersion date:\t $version_date\n";
	print "\tVersion bugs:\t $version_bugs\n";
}

#Server settings
# specify default settings here
$mongoserver = "localhost" unless ($mongoserver);
$mongoport   = "27017"     unless ($mongoport);
$mongodb     = "nxtseq"    unless ($mongodb);


# get the configuration for the script
my %mongo_server = (
	host     => $mongoserver,
	port     => $mongoport,
	database => $mongodb
);

my $sequencingtools = new SequencingTools(
	mongo_server => \%mongo_server,
	config_id    => $config_id,
	stagein      => 1,
#	startlog	 => 0
);


# check arguments
die "use -? to see correct command line arguments\n"
  unless ($config_id );
  

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#STEP 0: FETCH GENERAL CONFIGURATION INFORMATION
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

print "Fetching general configuration information...\n" if($info);

#Retrieve general configuration information
my $uploadway	= $sequencingtools->{run_config}->{uploadway};
my $file_format	= $sequencingtools->{run_config}->{format};
my $paired		= $sequencingtools->{run_config}->{paired};
$to_email		= $sequencingtools->{run_config}->{to_email};
$from_email		= $sequencingtools->{run_config}->{from_email};
$remove			= $sequencingtools->{run_config}->{remove};
my $dna_number  = $sequencingtools->{run_config}->{samplename};

#Retrive input specific configuration
my $ftp_username;
my $ftp_password;
my @ftp_servers;
my $passive_mode;
my $file_input;
my $fastq_company;

if($uploadway eq $UPLOAD_MANUAL){
	$file_input		= $sequencingtools->{run_config}->{file_input};
}elsif($uploadway eq $UPLOAD_FTP){
	$ftp_username	= $sequencingtools->{run_config}->{username};
	$ftp_password	= $sequencingtools->{run_config}->{password};
	@ftp_servers 	= @{$sequencingtools->{run_config}->{ftp_servers}};
	$passive_mode	= $sequencingtools->{run_config}->{passive_mode};
	$fastq_company	= $sequencingtools->{run_config}->{fastq_company};
}

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#STEP 0.1: DETERMINE OUTPUTDIRECTORY
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

#Fetch last_step from config entry if exists
my $last_step_config= $sequencingtools->getLastStep();

#Set a step point
$sequencingtools->setStepPoint();

#Make a unique outputdirectory
my $temp_outdir		= $sequencingtools->{node_config}->{paths}->{tempdir}->{dir};
my $outdir="";

eval{
	my @timeData = localtime(time);
	my $currentdate= join('', @timeData);
	$outdir = $temp_outdir."addsample_".$currentdate;
	$sequencingtools->run_and_log(
		message => "Make new directory ($temp_outdir).",
		command => "mkdir $temp_outdir",
	);
};
unless($@){
	#Edit last step in config file
	$sequencingtools->setLastStep();
}else{
	$sequencingtools->log_error(
    	message => "Unexpected error when making new output-directory: $@"
    );
    exit;
}

#Update config entry with new outdir
my %outdir_hash=(outdir => $outdir);
$sequencingtools->updateFieldRunConfig(%outdir_hash);


#Set a step point
$sequencingtools->setStepPoint();

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#STEP 1: DOWNLOAD SAMPLE IF UPLOADWAY IS NOT FTP OR MAKE NEW FILE WHEN UPLOADWAY IS MANUAL
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

print "Fetching data from ftp or manual input...\n" if($info);

my $ftp_nr=0;
my @ftp_servers_output_directories=();

if($uploadway eq $UPLOAD_FTP){

	#For every given ftp-server make a new dir where to put the files
	for(@ftp_servers){
		$ftp_nr++;
		my $ftpserver=$_;
		$ftpserver =~ s/^ftp:\/\/(.*)$/$1/;
		my $output_directory=$outdir.$FTP_DIRECTORY.$ftp_nr."/";
		push @ftp_servers_output_directories, $output_directory;
		
		#Make directories for ftp-servers
		if($last_step_config < $sequencingtools->getCurrentStepPoint()){
			$sequencingtools->run_and_log(
				message => "Make new directory ($output_directory).",
				command => "mkdir $output_directory",
			);
			
			#Edit last step in config file
			$sequencingtools->setLastStep();
		}
		
		#Set a step point
		$sequencingtools->setStepPoint();
		
		#Download files from ftp-server (passive or active)
		if($last_step_config < $sequencingtools->getCurrentStepPoint()){
			eval{
						
				#Check if a username and password is necessary
				if($ftp_username ne "" && $ftp_password ne ""){
					if($passive_mode){
						$sequencingtools->run_and_log(
							message => "Download files from ftp-server ($ftpserver).",
							command => "wget -r ftp://$ftp_username:$ftp_password\@$ftpserver --no-directories --directory-prefix=$output_directory",
						);
					}else{
						$sequencingtools->run_and_log(
							message => "Download files from ftp-server ($ftpserver).",
							command => "wget --no-passive-ft -r ftp://$ftp_username:$ftp_password\@$ftpserver --no-directories --directory-prefix=$output_directory",
						);
					}
				}else{
					if($passive_mode){
						$sequencingtools->run_and_log(
							message => "Download files from ftp-server ($ftpserver).",
							command => "wget -r ftp://$ftpserver --no-directories --directory-prefix=$output_directory",
						);
					}else{
						$sequencingtools->run_and_log(
							message => "Download files from ftp-server ($ftpserver).",
							command => "wget --no-passive-ftp -r ftp://$ftpserver --no-directories --directory-prefix=$output_directory",
						);
					}
				}
				
			};
			unless($@){
				#Edit last step in config file
				$sequencingtools->setLastStep();
			}else{
				$sequencingtools->log_error(
			    	message => "Unexpected error when downloading files from ftp-server(s): $@"
			    );
			    exit;
			}
		}
	}
}elsif($uploadway eq $UPLOAD_MANUAL){
	$ftp_nr=1;
	
	#Make directory for the file
	my $output_directory=$outdir.$FTP_DIRECTORY.$ftp_nr."/";
	push @ftp_servers_output_directories, $output_directory;
	if($last_step_config < $sequencingtools->getCurrentStepPoint()){
		$sequencingtools->run_and_log(
			message => "Make new directory ($output_directory).",
			command => "mkdir $output_directory",
		);
		
		#Edit last step in config file
		$sequencingtools->setLastStep();
	}
	
	#Set a step point
	$sequencingtools->setStepPoint();
	
	#Create a new file
	if($last_step_config <= $sequencingtools->getCurrentStepPoint()){
		my $file_name=$output_directory."/file.".$file_format;
		
		$sequencingtools->run_and_log(
			message => "Make a new $file_format file.",
			command => "touch $file_name",
		);
		
		$sequencingtools->run_and_log(
			message => "Fill the new file with the given data.",
			command => "echo '$file_input' > $file_name",
		);
		
		#Edit last step in config file
		$sequencingtools->setLastStep();
	}
}


#Set a step point
$sequencingtools->setStepPoint();

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#STEP 2: EXTRACT FROM ARCHIVE
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

print "Extracting files from archives...\n" if($info);

if($last_step_config < $sequencingtools->getCurrentStepPoint()){
	
	#Extract files from archive
	my $archive_files_ref;
	eval{
		for(my $i=0; $i<$ftp_nr; $i++){
			my $zip_files=$ftp_servers_output_directories[$i]."*";
			$archive_files_ref=extract_from_archive($zip_files, $ftp_servers_output_directories[$i], $remove);
		}
	};
	
	
	#If error occured don't delete files
	if ($@) {
	    $sequencingtools->log_error(
	    	message => "Couldn't extract files from archive: $@"
	    );
	    exit;
	}else{
		remove_files($remove, $archive_files_ref);
		
		#Edit last step in config file
		$sequencingtools->setLastStep();
	}
}

#Set a step point
$sequencingtools->setStepPoint();


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#STEP 3: MERGE ALL PAIRED FILES
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

print "Merging all paired files...\n" if($info);

if($file_format == $FORMAT_FASTQ && $fastq_company && $fastq_company == $COMPANY_ILLUMINA){
	if($last_step_config < $sequencingtools->getCurrentStepPoint() && $paired ){
		for(my $i=0; $i<$ftp_nr; $i++){
			my $fastq_files=$ftp_servers_output_directories[$i]."*.".$file_format;
		
			#Determine all R1 and R2 files
			my @files = < $fastq_files >;
			@files = sort(@files);
			
			my @read_one_files=();
			my @read_two_files=();
			my $read_one_file=$ftp_servers_output_directories[$i].$dna_number.".$file_format";
			my $read_two_file=$ftp_servers_output_directories[$i].$dna_number."_2.$file_format";
			
			foreach my $fastq_file (@files) {
				my $index= index(get_file_name($fastq_file), "_R1_");
				if($index ne "-1"){
					push @read_one_files, $fastq_file;
				}else{
					$index= index(get_file_name($fastq_file), "_R2_");
					if($index ne "-1"){
						push @read_two_files, $fastq_file;
					}
				}
			}
			
			#Merge R1 files
			cat($read_one_file,\@read_one_files, 1, $remove, $sequencingtools, "R1");
		
			#Merge R2 files
			cat($read_two_file,\@read_two_files, 1, $remove, $sequencingtools, "R2");
		}
		
		#Edit last step in config file
		$sequencingtools->setLastStep();
	}
	elsif($last_step_config < $sequencingtools->getCurrentStepPoint() && !$paired){
		for(my $i=0; $i<$ftp_nr; $i++){
			my $fastq_files=$ftp_servers_output_directories[$i]."*.$file_format";
		
			#Determine all files
			my @files = < $fastq_files >;
			@files = sort(@files);
			
			my @read_files=();
			my $read_file=$ftp_servers_output_directories[$i].$dna_number.".$file_format";
			
			foreach my $fastq_file (@files) {
				push @read_files, $fastq_file;
			}
		
			#Merge files
			cat($read_file,\@read_files, 1, $remove, $sequencingtools, "R1");
		}
		
		#Edit last step in config file
		$sequencingtools->setLastStep();
	}
}

#Set a step point
$sequencingtools->setStepPoint();


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#STEP 4: CAT THE FILES FROM THE DIFFERENT FTP SERVERS
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

print "Merging all files from different ftp servers...\n" if($info);

#If there is only one ftp-server mentioned then just move merge files to output
#outputdirectory 
if($file_format == $FORMAT_FASTQ && $fastq_company && $fastq_company == $COMPANY_ILLUMINA){
	if($last_step_config < $sequencingtools->getCurrentStepPoint()){
		if($ftp_nr<2){
			my $input_directory	=$ftp_servers_output_directories[0];
			my $input_files		=$ftp_servers_output_directories[0].$dna_number."*.$file_format";
			
			$sequencingtools->run_and_log(
				message => "Move files to outputdirectory.",
				command => "mv $input_files $outdir"
			);
			
			if($remove){
				$sequencingtools->run_and_log(
					message => "Remove ftpserver directory.",
					command => "rm -fR $input_directory"
				);
			}
		}else{
			#Merge R1 files
			my $read_merged_file=$outdir.$dna_number.".$file_format";
			my @read_merged_files=();
			for(my $i=0; $i<$ftp_nr; $i++){
				my $input=$ftp_servers_output_directories[$i].$dna_number.".$file_format";
				push @read_merged_files, $input;
			}
			
			
			cat($read_merged_file, \@read_merged_files, 1, $remove, $sequencingtools, "all R1");
			
			
			if($paired){
				#Merge R2 files
				$read_merged_file=$outdir.$dna_number."_2.$file_format";
				@read_merged_files=();
				for(my $i=0; $i<$ftp_nr; $i++){
					my $input=$ftp_servers_output_directories[$i].$dna_number."_2.$file_format";
					push @read_merged_files, $input;
				}
			
				cat($read_merged_file, \@read_merged_files, 1, $remove, $sequencingtools, "all R2");
				
				$sequencingtools->run_and_log(
					message => "FTP-server directories removed!",
					command => "rm -Rf $outdir$FTP_DIRECTORY*",
				);
			}
		}
		
		#Edit last step in config file
		$sequencingtools->setLastStep();
	}
}

#Set a step point
$sequencingtools->setStepPoint();



#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#STEP 5: START MAPPING PROCES
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

print "Starting mapping process...\n" if($info);

#Fetch necessary data to make new configuration entry
my $build		= $sequencingtools->{run_config}->{build};
$from_email		= $sequencingtools->{run_config}->{from_email} unless($from_email);
$to_email		= $sequencingtools->{run_config}->{to_email}   unless($to_email);
my $organism_id	= $sequencingtools->{run_config}->{organism_id};

if($file_format == $FORMAT_FASTQ){
	
	#Setup configuration entry
	my %config_entry=(	'build' 		=> "GRCh37",
	   					$file_format	=> $outdir.$dna_number.".$file_format",
	   					'from_email' 	=> $from_email,
	   					'index'			=> boolean::true,
	   					'mapper'		=> "bwa_pe",
	   					'organism_id'	=> $organism_id,
	   					'outdir' 		=> $outdir,
	   					'paired'		=> boolean::true,
					   	'pileup' 		=> boolean::false,
					   	'recal'			=> boolean::true,
					   	'remove' 		=> $remove,
					   	'rmdup'			=> boolean::false,
	   					'script'		=> "map_reads.pl",
	   					'server'		=> "mellfire.ugent.be",
	   					'server_config'	=> "testing",
	   					'sort'			=> boolean::true,
	   					'to_email'		=> $to_email
	);

	#Create new entry
	my $config_entry_id = $sequencingtools->createConfigurationEntry(\%config_entry);
	
	#Start mapping
	$sequencingtools->run_and_log(
		message => "Start mapping of configuration: $config_entry_id",
		command => "perl map_reads --config $config_entry_id"
	);
}else{
	$sequencingtools->log_error(
    	message => "Only fastq files are currently supported!"
    );
    exit;
}




#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#FINISH LOGGING
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


# finish logging
$sequencingtools->finish_log();


print "Add new sample handles finished with succes!\n" if($info);

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#SUBROUTINES
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


sub get_file_name($){
	my $file_path=shift;
	my ($filename, $directory_path) = fileparse($file_path);
	return $filename;
}

#Check if given file is a archive type
sub is_archive{
	my $filepath=shift;
	my ($filename, $directory_path, $extension) = fileparse($filepath, qr/\.[^.]*/);
	my $is_archive=0;
	
	my @archive_types= (".tar", ".gz", ".Z", ".zip", ".lzma", ".xz");

	for my $type (@archive_types){
		if($type eq $extension){
			$is_archive=1;
		}
	}
	
	return $is_archive;
}

#Remove files
sub remove_files{
	my $remove=shift;
	my $filelist_ref=shift;
	my @filelist=@{$filelist_ref};
	my $size = scalar @filelist;
	
	if($remove && $size > 0 ){
		for my $file (@filelist){
			unlink $file;
		}
	}
}

sub extract_from_archive{
	#Determine souce directory of the given sample with zip files
	my $zip_files=shift;
	my $output_server_dir=shift;
	my $remove=shift;
	my @archive_files=();
	
	eval{
		#Read all archive files from given directory
		my @files = < $zip_files >;
		my $filename;
		my $directory_path;
		foreach my $file (@files) {

			if(is_archive($file)){
				my $archive_extract = Archive::Extract->new( archive => $file );
				print "\t$file is a archive file!\n";
				push @archive_files, $file;
				$archive_extract->extract(to => $output_server_dir);
				print "\textracted!\n";
			}
			
			#my $output_file=$file;
			#$output_file=~ s/^(.*)\.gz$/$1/;
			#my $status = gunzip $file => $output_file or die "gunzip failed: $GunzipError\n";
		}
	};
	
	if($@){
		die("Error occured: $@");
	}
	else{
		print "Files unzipped with success!\n";
		return \@archive_files;
	}
	
}

#Merge files
#use: cat($read_file, \@read_files, $read_number, 1, 1, $sequecingtools, $read_number)
sub cat{
	my $read_file=shift;
	my @read_files=@{ (shift) };
	@read_files=sort(@read_files);
	my $print_info=shift;
	my $remove=shift;
	my $sequencingtools=shift;
	my $read_number=shift;
	
	#Print given info
	if($print_info){
		print "Read file= $read_file\n";
		print "Read files:\n";
		for (@read_files){
			print "\t$_\n";
		}
	}

	eval{
		unless (-e $read_file) {
			#Create new file
			open FILE, ">$read_file" or die $!;

			#Loop over all given files to be concatenated
			foreach my $read_file_nr (@read_files) {
		
			  	open(READ_FILE, $read_file_nr) || die("Can't open file $read_file_nr\n");
		
				$|=1;
			  	while (<READ_FILE>) {
				 	print FILE $_;
			  	}
			
				$|=0;
			  	close(READ_FILE);
			  	
		   	}

			close(FILE);
		}
	};
	
	if ($@) {
		my @delete_files=($read_file);
	    $sequencingtools->log_error(
	    	message => "Couldn't merge $read_number files (into $read_file) due: $@"
	    );
	    remove_files($remove, \@delete_files);
	    exit;
	}else{
		remove_files($remove, \@read_files);
	}
}


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#MANUAL
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


__END__

=head1 NAME

add_sample_handler

=head1 SYNOPSIS

=head1 DESCRIPTION


=head2 EXPORT




=head1 SEE ALSO


=cut