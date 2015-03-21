#!/usr/bin/perl -w
use strict;
use warnings;
use File::Basename;
use File::Slurp;
use BitQC;
use Scalar::Util 'looks_like_number'; 

######################################################################################
# INITIALISE BITQC MODULE
######################################################################################

# Make BitQC object
# settings will come from environment variables
my $BitQC = new BitQC();

# Load bitqc configuration from the given database
$BitQC->load(
	'script_args' => {
		'region'		=> { type => 'string'},
		'vcfindex'   	=> { type => 'string'},
		'unknownvcf' 	=> { type => 'string'},
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

#config vairables
my $REGION 				= $BitQC->getRunConfig('region');
my @VCF 	 			= @{$BitQC->getRunConfig('vcf')};
my $VCFINDEX 			= $BitQC->getRunConfig('vcfindex');
my %INPUTVCF			= %{$VCF[$VCFINDEX]};
my $UNKNOWNFILE 		= $BitQC->getRunConfig('unknownvcf');
my $GENOMEBUILD   		= $BitQC->getRunConfig('genomebuild');
my $VARIANTSCOLL  		= $BitQC->getRunConfig('variantscol');
my $VCFHEADERCOLL 		= $BitQC->getRunConfig('vcfheadercol');
my @VCFSAMPLES    		= @{$INPUTVCF{samples}};
my $MINALLELEQUAL 		= $BitQC->getRunConfig('minallelequal') ? $BitQC->getRunConfig('minallelequal') : 0;
my $MINCOV 				= $BitQC->getRunConfig('mincov') ? $BitQC->getRunConfig('mincov') : 0;
my $PASSFILTER 			= $BitQC->getRunConfig('passfilter');
my $MINSAMPLECOVERAGE 	= $BitQC->getRunConfig('minsamplecov') ? $BitQC->getRunConfig('minsamplecov') : 0;
my $MINGENOTYPEQUALITY 	= $BitQC->getRunConfig('mingenotypequal') ? $BitQC->getRunConfig('mingenotypequal') : 0;

my $TABIX_COMMAND = $BitQC->getCommand('tabix');

my $ENSEMBL_REGISTRY = $BitQC->getCommand('ensemblAPI');

my $ENSEMBL_HOST = $BitQC->{node_config}->{executables}->{ensemblAPI}->{host};
my $ENSEMBL_USER = $BitQC->{node_config}->{executables}->{ensemblAPI}->{user};
my $ENSEMBL_PASS = $BitQC->{node_config}->{executables}->{ensemblAPI}->{pass};
my $ENSEMBL_PORT = $BitQC->{node_config}->{executables}->{ensemblAPI}->{port};

#Genomeinformation
my $ENSEMBL_ORGANISM = $BitQC->{genome}->{organism}->{ensemblname};

my %datatypes = (
	'integer'   => 'integer',
	'float'     => 'float',
	'flag'      => 'bool',
	'character' => 'string',
	'string'    => 'string',
);

######################################################################################
# GET THE HEADER INFO FROM THE DATABASE
######################################################################################

# get the info fields
my $info = $BitQC->{DatabaseAdapter}->findEntryById(
	collection => $VCFHEADERCOLL,
	id         => "INFO"
);

#turn them into a hash
my %dbinfo;
for my $info ( @{ $info->{'values'} } ) {
	my @arraykeys;
	@arraykeys = @{ $info->{'arraykeys'} } if ( $info->{'arraykeys'} );
	$dbinfo{ $info->{'id'} } = {
		'type'      => $datatypes{ lc( $info->{'type'} ) },
		'number'    => $info->{'number'},
		'arraykeys' => \@arraykeys
	};
}

# get the format fields
my $format = $BitQC->{DatabaseAdapter}->findEntryById(
	collection => $VCFHEADERCOLL,
	id         => "FORMAT"
);

# turn into hash
my %dbformat;
for my $format ( @{ $format->{'values'} } ) {
	my @arraykeys;
	@arraykeys = @{ $format->{'arraykeys'} } if ( $format->{'arraykeys'} );
	$dbformat{ $format->{'id'} } = {
		'type'      => $datatypes{ lc( $format->{'type'} ) },
		'number'    => $format->{'number'},
		'arraykeys' => \@arraykeys
	};
}
my %dbsamples;

######################################################################################
# GET THE VARIANTS ALREADY IN THE DATABASE FOR THIS REGION
######################################################################################

# my ( $chromosome, $positions ) = split( /=/, $REGION );
# my ( $regionstart, $regionend );
# ( $regionstart, $regionend ) = split( /-/, $positions ) if ($positions);
# my %query = (
# 	b => $GENOMEBUILD,
# 	c => $chromosome
# );
# $query{s}{'$gte'} = $regionstart if ($regionstart);
# $query{s}{'$lte'} = $regionend   if ($regionend);

# my $variants = $BitQC->{DatabaseAdapter}->findResult(
# 	collection => $VARIANTSCOLL,
# 	query      => \%query,
# 	columns    => { '_id' => 1, c => 1, s => 1, v => 1 },
# );
# $variants->slave_okay(1);
# my %knownvariants;
# while ( my $variant = $variants->next ) {
# 	$knownvariants{ $variant->{'c'} }{ $variant->{'s'} }{ $variant->{'v'} } =
# 	  $variant->{'_id'};
# }

######################################################################################
# OPEN THE INPUT VCF FILE
######################################################################################

# create local file object
# TODO: cannot use the bitqc file object as it does not support region queries...
#my $vcffile = $BitQC->{fileadapter}->createFile(\%INPUTVCF);
#my $vcf = $file->getWritePointer();	


# get the file name , path and extesion
# open a file pointer to the vcf file
my $command;

# we get the value's for the name and location of the file from the hash
my $host = $INPUTVCF{'host'} ? $INPUTVCF{'host'} : "";
my $user = $INPUTVCF{'user'} ? $INPUTVCF{'user'} : "";
my $pass = $INPUTVCF{'pass'} ? $INPUTVCF{'pass'} : "";
my $file = $INPUTVCF{'file'} ? $INPUTVCF{'file'} : "";
my $name = $INPUTVCF{'name'} ? $INPUTVCF{'name'} : "";

if ( $INPUTVCF{'type'} eq "local" ) {
	$command = "$TABIX_COMMAND -p vcf $file $REGION ";
}
elsif ( $INPUTVCF{'type'} eq "ftp" ) {
	$command = "$TABIX_COMMAND -p vcf ftp://$user:$pass\@$host/$file $REGION ";
}
elsif ( $INPUTVCF{'type'} eq "http" ) {
	$command = "$TABIX_COMMAND -p vcf http://$host/$file $REGION ";
}
elsif ( $INPUTVCF{'type'} eq "https" ) {
	$command =
	  "$TABIX_COMMAND -p vcf https://$user:$pass\@$host/$file $REGION ";
}
elsif ( $INPUTVCF{'type'} eq "mongodb" ) {

	# connot work directly form mongo database
	# TODO: handle this!
}
open( my $vcf, "-|", $command ) or $BitQC->log_error( message => "$!" );

# open the ensembl createDatabaseConnection	#Make ensembl registry
$ENSEMBL_REGISTRY->load_registry_from_db(
	-host    => $ENSEMBL_HOST,
	-user    => $ENSEMBL_USER,
	-pass    => $ENSEMBL_PASS,
	-port    => $ENSEMBL_PORT
);

# for variants not known to the database
my @unknown;

# open a database collection to insert the variants
my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
my $variants_collection = $mongodb->$VARIANTSCOLL;

while (<$vcf>) {    #Loop through lines
	next if (/^#/);    # skip header
	chomp;

	my $line = $_;

	my %variants;
	##---
	## Get values from line
	##---
	chomp;
	my @fields = split( /\t/, $_ );

	my $chr    = $fields[0];												# the cromosome
	my $vcfpos += $fields[1];												# 1 based position
	my @id;
	@id     = split( /;/, $fields[2] ) unless ( $fields[2] eq '.' );		# names for the variant
	my $vcfrfba = uc( $fields[3] );											# the reference base
	next if ($fields[4] eq '.');											# position is non variant
	my @all = split( /,/, uc( $fields[4] ) );								# the alterantive alleles
	my $qual;
	$qual += $fields[5] unless ( $fields[5] eq '.' );						# the quality score of the allele calls
	my @filter;
	@filter = split( /;/, $fields[6] ) unless ( $fields[6] eq '.' ); 		# the filters, if applied

	# check if quality limit is reached
	next if ( $qual && $qual < $MINALLELEQUAL );

	# we only enter variants that have passed filtering if required
	next if ( $PASSFILTER && @filter && $filter[0] ne "PASS" );

	# turn info fields into hash
	my @info;
	@info = split( /;/, $fields[7] ) unless ($fields[7] eq '.');
	my %info;
	for (@info) {
		my @infofield = split( /=/, $_ );
		$info{ $infofield[0] } = $infofield[1];
	}

	# check if minimal total coverage across all samples is reached
	# if coverage data is specified
	next if ( $info{DP} && $info{DP} < $MINCOV );

	my @format;
	@format = split( /:/, $fields[8] ) if ( $fields[8] );

	my $ensembl_vf = @{Bio::EnsEMBL::Variation::Utils::VEP::parse_vcf({
		vfa 	=> $ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'variation', 'variationfeature' ),
		svfa 	=> $ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'variation', 'structuralvariationfeature'),
		},
		$line
	)}[0];
    my $ensemblstart += $ensembl_vf->{'start'} ? $ensembl_vf->{'start'} : 0;
    my $ensemblmax_start += $ensembl_vf->{'inner_start'} ? $ensembl_vf->{'inner_start'} : 0;
    my $ensemblmin_start += $ensembl_vf->{'outer_start'} ? $ensembl_vf->{'outer_start'} : 0;
    my $ensemblend += $ensembl_vf->{'end'} ? $ensembl_vf->{'end'} : 0;
    my $ensemblmin_end += $ensembl_vf->{'inner_end'} ? $ensembl_vf->{'inner_end'} : 0;
    my $ensemblmax_end += $ensembl_vf->{'outer_end'} ? $ensembl_vf->{'outer_end'} : 0;
    my $ensemblstrand = $ensembl_vf->{'strand'} ? $ensembl_vf->{'strand'} : "";
    my $ensembl_so_term = $ensembl_vf->{'class_SO_term'} ? $ensembl_vf->{'class_SO_term'} : "";
    my $ensemblallelestring = $ensembl_vf->{'allele_string'} ? $ensembl_vf->{'allele_string'} : "";

    $ensemblallelestring =~ /(^[-ACTG]+)\/(.+)/;
    my $ensemblref = $1;
    my $ensemblalleles = $2;
    my @ensemblalleles = split(/\//, $ensemblalleles);

	my %alleles;

	my $allelecounter = 1;
	foreach my $allele (@ensemblalleles) {
		my $vcfallele = $all[$allelecounter-1];
	# 	my $length = length($allele);
	# 	$length = length($rfba)
	# 	  if ( length($rfba) > $length );
	# 	my @allele = split( //, $allele );
	# 	my @rfba   = split( //, $rfba );
	# 	my $i      = 0;
	# 	my $start  = undef;
	# 	my $end    = undef;
	# 	my $allele_ref  = "-";
	# 	my $allele_var  = "-";
	# 	my $var_stretch = 0;

	# 	while ( $i < $length ) {

	# 		if ( $rfba[$i] ) {
	# 			if ( $allele[$i] ) {
	# 				if ( ( $allele[$i] ne $rfba[$i] )
	# 					|| $var_stretch )
	# 				{

	# 					# position is substitution
	# 					$start = $vcfpos + $i
	# 					  unless ($start)
	# 					  ;    # remains the same for each variable base
	# 					$end = $vcfpos + $i;  # increment for each variable base
	# 					if ( $allele_ref eq "-" ) {
	# 						$allele_ref = $rfba[$i];
	# 					}
	# 					else {
	# 						$allele_ref .= $rfba[$i];
	# 					}
	# 					if ( $allele_var eq "-" ) {
	# 						$allele_var = $allele[$i];
	# 					}
	# 					else {
	# 						$allele_var .= $allele[$i];
	# 					}

	# 				   # once this point is reached we are in a variable stretch
	# 					$var_stretch = 1;
	# 				}    # no else, we do not store non variable bases
	# 			}
	# 			else {

	# 				# position is deleted
	# 				if ( $allele_ref eq "-" )
	# 				{    # if no substitution has previously been described
	# 					$allele_ref = $rfba[$i];
	# 					$start      = $vcfpos + $i;
	# 				}
	# 				else {    # if a substitution has previously been descibed
	# 					$allele_ref .= $rfba[$i];
	# 				}
	# 				$end = $vcfpos + $i;    # increases for each deleted base
	# 			}
	# 		}
	# 		else {
	# 			if ( $allele_var eq "-" ) {

	# # no previous substitution seen: we set start and stop where start = stop -1
	# 				$allele_var = $allele[$i];
	# 				$start      = $vcfpos + $i;
	# 				$end        = $start - 1;
	# 			}
	# 			else {
	# 				$allele_var .= $allele[$i];

	# # 1 or more substitutions where already seen, we do not change start or stop
	# 			}
	# 		}
	# 		$i++;
	# 	}
	# 	my $variant = $allele_ref . "/" . $allele_var;

	# 	my $type = "sub";
	# 	if ( $allele_ref eq "-" ) {
	# 		$type = "ins";
	# 	}
	# 	elsif ( $allele_var eq "-" ) {
	# 		$type = "del";
	# 	}

		my $variant = $ensemblref . "/" . $allele;

		my $type = "sub";
		if ( $ensemblref eq "-" ) {
			$type = "ins";
		}
		elsif ( $allele eq "-" ) {
			$type = "del";
		}

		# detect complex indels in repeats
		# TODO: will the ensembl consequence type be correct with this type of variant?
		if ($ensemblref =~ /($allele)/){
			# the allele if fully enclosed in the reference string
			# example ref: GG alt: G (will occur for record 8	73288662	.	TGG	TG)
			# this point to a loss of one of the repeat (can be single or multi base repeat)
			# potential allignments are:
			# ref:  NNGGNN
			# aln1: NNG NN
			# aln2: NN GNN
			$type = "del";
		} elsif ($allele =~ /$ensemblref/){
			# the reference is fully enclosed in the allele
			# example ref: ACACACACACA alt: ACACACACACACA (will occur for record 19	59674507	.	GACACACACACA	GACACACACACACA)
			# this points to an expansion of the repeat by one (single or multiple base repeat)
			# potential allignments are:
			# ref:  NN  ACACACACACA  NN
			# aln1: NNACACACACACACA  NN
			# aln2: NN  ACACACACACACANN
			$type = "ins";
		}

		my $subtype;
		$subtype = 'transversion' if ( $type eq 'sub' );
		$subtype = 'transition'
		  if ( $variant eq 'A/G'
			|| $variant eq 'G/A'
			|| $variant eq 'C/T'
			|| $variant eq 'T/C' );

		my @genotypes = ();
	  SAMPLE: foreach my $samplecounter ( 0 .. $#VCFSAMPLES ) {
			my %genotype;
			#skip of no call was done for this sample 
			next SAMPLE if ( $fields[ 9 + $samplecounter ] eq './.' );
			if ( $fields[ 9 + $samplecounter ] ) {
				$genotype{id} = MongoDB::OID->new( value => $VCFSAMPLES[$samplecounter]{id});
				$genotype{sn} = $VCFSAMPLES[$samplecounter]{name};

				# get the values matching the format fields we got earlier
				my @values =
				  split( /:/, $fields[ 9 + $samplecounter ] );
				for my $f ( 0 .. $#format ) {
					$genotype{ $format[$f] } =
					  __datarestructure( $values[$f], $dbformat{ $format[$f] },
						$vcfrfba, \@all, $allelecounter ) unless ($values[$f] eq '.');
				}
				next SAMPLE
				  if ( $PASSFILTER
					&& $genotype{'FT'}[0]
					&& $genotype{'FT'}[0] ne "PASS" );
				next SAMPLE if ( exists $genotype{'DP'} && $genotype{'DP'} < $MINSAMPLECOVERAGE );
				next SAMPLE if ( exists $genotype{'GQ'} && $genotype{'GQ'} < $MINGENOTYPEQUALITY );

				my $GT = $genotype{'GT'};
				next SAMPLE unless $GT =~ /$allelecounter/;
				if ( $GT =~ /|/ ) {
					$genotype{'phased'} = boolean::true;
				}
				elsif ( $GT =~ /\// ) {
					$genotype{'phased'} = boolean::false;
				}
				$genotype{'GT'} = "het"
				  if $GT =~ s/$allelecounter//;    # matches once
				$genotype{'GT'} = "hom"
				  if $GT =~ s/$allelecounter//;    # 2 matches found
			}
			else {
				$genotype{id} = MongoDB::OID->new( value => $VCFSAMPLES[$samplecounter]{id});
				$genotype{sn} = $VCFSAMPLES[$samplecounter]{name};
			}

			# add the allele quality to the genotype since it is sample specific
			$genotype{'allelequal'} = $qual if ($qual);

			# update the info hash to contain genotype specific info
			my %genotypeinfo = %info;
			foreach my $infokey ( keys %genotypeinfo ) {
				$genotypeinfo{$infokey} =
				  __datarestructure( $genotypeinfo{$infokey}, $dbinfo{$infokey},
					$vcfrfba, \@all, $allelecounter ) unless ($infokey eq '.' || ($genotypeinfo{$infokey} && $genotypeinfo{$infokey} eq '.') );
			}

			# add the genotype specific info to the genotype hash
			$genotype{'info'} = \%genotypeinfo;

			# add the genotype to the array
			
			push( @genotypes, \%genotype );

		}
		if (@genotypes) {
			my %query = (
				b => $GENOMEBUILD,
				c => $chr,
				s => $ensemblstart,
				v => $variant
			);

			my $result = $variants_collection->find_one( \%query, { '_id' => 1 } );

			if ( $result->{'_id'} ) {
				foreach my $gt (@genotypes) {
					$variants_collection->update(
						{ _id => $result->{'_id'}, "c" => $chr },
						{ '$addToSet' => { 'sa' => $gt } }, {multiple => 1},
						{ safe        => 1 }
					);
				}
			}
			else {
				my %var = (
					c  	=> $chr,
					s 	=> $ensemblstart,
					vp 	=> $vcfpos,
					r 	=> $ensemblref,
					vr  => $vcfrfba,
					a 	=> $allele,
					va 	=> $vcfallele,
					e  	=> $ensemblend,
					v  	=> $variant,
					t  	=> $type,
					b  	=> $GENOMEBUILD,
					sa 	=> \@genotypes
				);
    			$var{mast} = $ensemblmax_start if ($ensemblmax_start);
    			$var{mist} = $ensemblmin_start if ($ensemblmin_start);
    			$var{mien} = $ensemblmin_end if ($ensemblmin_end);
    			$var{maen} = $ensemblmax_end if ($ensemblmax_end);
    			$var{str} = $ensemblstrand if ($ensemblstrand);
    			$var{so} = $ensembl_so_term if ($ensembl_so_term);
				$var{st} = $subtype if ($subtype);

				my $record =
				  $variants_collection->insert( \%var, { safe => 1 } );

				push( @unknown,
					"$GENOMEBUILD\t$chr\t$ensemblstart\t$ensemblend\t$variant\t"
					."$ensemblmax_start\t$ensemblmin_start\t$ensemblmin_end\t$ensemblmax_end\t$ensemblstrand\t$ensembl_so_term\t"
					.$record->value
					."\n" );
			}
		}
		$allelecounter++;
	}
}
close $vcf;

# create local file object
my $unknownfile = $BitQC->{fileadapter}->createFile( {
	'compression' => 'gzip',
	'filetype' => 'txt',
	'file' => $UNKNOWNFILE,
    'type' => 'local',
    'ext' => '.txt.gz'
});

# create file pointer for writing
my $unknownfilepointer = $unknownfile->getWritePointer();	

write_file( $unknownfilepointer, @unknown );
close $unknownfilepointer;

######################################################################################
# FINISH SCRIPT
######################################################################################

# finish logging
$BitQC->finish_log( message => "Header extracted from vcf files!" );

######################################################################################
# SUBROUTINES
######################################################################################

# change datatype of value depending on vcf header info
# use: $retyped_data = __datatype ($value,\%info);
sub __datatype {

	# get parameters
	my $value = shift;
	my $info  = shift;
	my %info  = %{$info};

	if ( $info{'type'} eq 'integer' ) {
		my $return += $value;
		return $return;
	}
	elsif ( $info{'type'} eq 'float' ) {
		my $return += $value;
		return $return;
	}
	elsif ( $info{'type'} eq 'string' ) {
		return $value;
	}
	elsif ( $info{'type'} eq 'bool' ) {
		return boolean::true;
	}
}

# change datastructure of value depending on vcf header info
# use: $restucured_data = __datatype ($value,\%info,$rfba,\@all,$allelecounter);
sub __datarestructure {

	# get parameters
	my $value         = shift;
	my $info          = shift;
	my %info          = %{$info};
	my $rfba          = shift;
	my $alleles       = shift;
	my @alleles       = @{$alleles};
	my $allelecounter = shift;

	if ( !$info{'number'} || $info{'number'} eq '1' ) {
		return __datatype( $value, \%info );
	}
	elsif ( $info{'number'} eq 'A' ) {

		# this means the info fields contains a value per allele
		# we only store the one matching the current allele
		my @values = split( /,/, $value );
		return __datatype( $values[ $allelecounter - 1 ], \%info );
	}
	elsif ( $info{'number'} eq 'AD' ) {
		my @values = split( /,/, $value );
		my %alinfo;
		my @gt = ( $rfba, @alleles );
		my $i  = 0; # values counter
		foreach (@values) {
			# store value with the genotype
			$alinfo{ $gt[$i] } =
			  __datatype( $values[$i], \%info );
			$i++;
		}
		return \%alinfo;
	}
	elsif ( $info{'number'} eq 'G' ) {

		# info contains a value per genotype
		my @values = split( /,/, $value );
		my %gtinfo;

		# get all the possible genotypes, including the reference base
		my @gt = ( $rfba, @alleles );
		my $i  = 0;                     # values counter
		my $i1 = 0;                     # first allele counter
		my $i2 = 0;                     # second allele counter
		     # we create all possible genotype combinations
		foreach (@values) {

			# store value with the genotype
			$gtinfo{ $gt[$i1] . '-' . $gt[$i2] } =
			  __datatype( $values[$i], \%info );
			if ( $i1 < $#gt ) {
				$i1++;
			}
			else {
				$i2++;
				$i1 = $i2;
			}
			$i++;
		}
		return \%gtinfo;
	}
	elsif ( (looks_like_number($info{'number'}) && $info{'number'} > 1) || $info{'number'} eq "."  ) {
		my @values = split( /,/, $value );

		# covert to correct datatype
		for my $f ( 0 .. $#values ) {
			$values[$f] = __datatype( $values[$f], \%info );
		}

		# replace by hash if requested
		if ( @{$info{'arraykeys'}} ) {
			my %values;
			my @arraykeys = @{ $info{'arraykeys'} };
			for my $f ( 0 .. $#values ) {
				$values{ $arraykeys[$f] } =
				  __datatype( $values[$f], \%info );
			}
			return \%values;
		}
		else {
			return \@values;
		}
	}
}
