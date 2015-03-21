#Author			: Wouter De Meester
#Created on		: 21/11/2011
#Last updated on: 25/11/2011
#Copyright		: University Ghent, Belgium

# DnaPositionConvertor:
#	Module that is used to convert cdna to gdna positions and gdna to cdna
#	positions.
#

#Package name
package DnaPositionConvertor;

#Used modules
use 5.010001;
use strict;
use warnings;

require Exporter;


###########################################################################
# Constructor:
#	Create a new convertor object
#
# Use:
# my $convertor	= new lib::DnaConvertor(
#	 registry	=> $registry,
#	 organism	=> $organism
# );
###########################################################################
sub new{
	my $self	= shift;
	my %args	= @_;
	my $registry;
	
	#Determine registry
	if($args{registry}){
		$registry = $args{registry};
	}else{
		require Bio::EnsEMBL::Registry;
		$registry = 'Bio::EnsEMBL::Registry';
		$registry->load_registry_from_db(
		  -host    => 'ensembldb.ensembl.org',
		  -user    => 'anonymous',
		  -verbose => '0'
		);
	}
	
	my $object->{registry} 	= $registry;
	
	
	#Determine organism
	my $organism = $args{organism};
	$object->{organism}	= $organism;

	#Determine supported organism
	my %organisms = ( 9606 => "homo_sapiens" );
	
	#Determine adaptors
	my $variant_adaptor = $registry->get_adaptor( $organisms{$organism}, 'Variation', 'VariationFeature' );
	my $slice_adaptor = $registry->get_adaptor( $organisms{$organism}, 'Core', 'Slice' );
	my $gene_adaptor = $registry->get_adaptor( $organisms{$organism}, 'Core', 'Gene' );
	my $transcript_adaptor = $registry->get_adaptor( $organisms{$organism}, 'Core', 'Transcript' );
	my $transcript_variation_adaptor = $registry->get_adaptor( $organisms{$organism}, 'variation', 'transcriptvariation');
	
	#Add adaptors to object
	$object->{adaptors}=();
	$object->{adaptors}->{variant_adaptor} 		= $variant_adaptor;
	$object->{adaptors}->{slice_adaptor} 		= $slice_adaptor;
	$object->{adaptors}->{gene_adaptor} 		= $gene_adaptor;
	$object->{adaptors}->{transcript_adaptor} 	= $transcript_adaptor;
	$object->{adaptors}->{transcript_variation_adaptor} = $transcript_variation_adaptor;
	
	#Bless object
	bless $object, $self;
	return $object;
}


###########################################################################
# HGV_parser:
#	this function parses a HGV nomenclature and split it up in different parts
#	in the right way to use for the cdna_to_gdna_convertor
# 
# example:
# 	my @input		= ("NM-014319.3:c.1323C>A", "NM-014319.3:c.77+1G");
# 	my @hgv_coords 	= $convertor->HGV_parser(\@input);
#
# return: reference to an array of hashes
###########################################################################
sub HGV_parser{
	my ($self, $input_ref)	= @_;
	my $reg_expr	="([^:]+):c\.([0-9]+)([+-]?)([0-9]*)(.*)";
	my @hgv_coords=();
	
	foreach my $input (@$input_ref){

		#Define variables
		my ($transcript, 	$cdna_position,
			$intron_sign,	$intron_position,
			$nucleotide,	$is_intron
		) = undef;
	
		#Check input and if correct split up
		if($input =~ m/$reg_expr/){
			my %hgv_coord=();
			$hgv_coord{cdna_change}		= $input;
			$hgv_coord{transcript_id}	= $1;
			$hgv_coord{cdna_pos} 		= $2;
			$hgv_coord{is_intron}		= 0;
			
			#Is intron position?
			if($3 && $4){
				$hgv_coord{is_intron}	= 1;
				$hgv_coord{intron_sign}= $3;
				$hgv_coord{intron_position}= $4;
			}
	
			$hgv_coord{organism}		= $self->{organism};
			$hgv_coord{nucleotide}		= $5;
			
			#Push hgv coordinate in result array
			push (@hgv_coords, \%hgv_coord);
		}
	}
	
	return \@hgv_coords;
}


###########################################################################
# cdna_to_gdna_convertor:
#	this function converts the given cDNA position to the corresponding
# 	gDNA position.
#
# Use:
# 	my @transcripts = (
# 		{
#			cdna_pos    	=> "1169",
#			transcript_id  	=> "NM_001142771.1",
# 		}
# 	);
#
# 	OR
# 
# 	my @transcripts	= ("NM-014319.3:c.1323C>A", "NM-014319.3:c.77+1G");
# 	@transcripts	 	= $convertor->HGV_parser( \@transcripts );
#
# 	my @result 		= $convertor->cdna_to_gdna_convertor( transcripts => \@hgv_coords );
#
# return: array with an result hash for every given hash in the transcript array
###########################################################################
sub cdna_to_gdna_convertor {
	my ($self, %input_array) = @_;
	my %transcripts;
	
	my $TYPE_INTRON	="intron";
	my $TYPE_EXON	="exon";

	# make a hash ref from the input array
	foreach my $var_ref ( @{ $input_array{transcripts} } ) {
		if($var_ref->{is_intron}){
			push (@{$transcripts{ $self->{organism} }{$TYPE_INTRON} }, $var_ref);
		}else{
			push (@{$transcripts{ $self->{organism} }{$TYPE_EXON} }, $var_ref);
		}
	}

	# set the variables to return
	my @results=();

	foreach my $organism ( keys %transcripts ) {	
		
		foreach my $type ( keys %{$transcripts{$organism}} ){
			
			foreach my $cdna_entry ( @{$transcripts{$organism}{$type}}){
				

				#Define variables
				my ( 	$cdna_pos,			$gene_id,
						$transcript_id, 	$transcript,
						$transcript_start,	$transcript_end,
						$transcript_strand, $gDNA_position,
						$gene,				$gene_name,
						$transcript_name, 	$transcript_stable_id,
						$transcript_cds_start, $transcript_cds_end,
						$intron_sign,		$intron_position,
						$transcript_cdna_start, $transcript_cdna_end,
						$chromosome,		$cdna_change
						
					) = undef;
				
				
						
				#Get rest of necessary information
				$cdna_change	= $cdna_entry->{cdna_change} 
					if($cdna_entry->{cdna_change});
				$cdna_pos		= $cdna_entry->{cdna_pos};
				$transcript_id	= $cdna_entry->{transcript_id};
				
				#Get transcript
				$transcript = $self->{adaptors}->{transcript_adaptor}->fetch_by_stable_id($transcript_id);
				
	#			my @transcripts = @{$transcript_adaptor->fetch_all_by_external_name($transcript_id)};
	#			if(scalar @transcripts == 1){
	#				$transcript = $transcripts[0];
	#			}else{
	#				my $aantal=scalar @transcripts;
	#				print "Zero or more than 1 transcript found ($aantal transcripts found)!!\n"
	#			}
				
				#If transcript exist, then retrieve all necessary information
				if ($transcript) {
					
					#Retrieve gene information of the transcript
					$transcript_stable_id=$transcript->stable_id();
					$gene 		= $self->{adaptors}->{gene_adaptor}->fetch_by_transcript_stable_id($transcript_stable_id);
					$gene_id 	= $gene->stable_id 		if ($gene);
					$gene_name 	= $gene->external_name 	if ($gene);
					
					#Get transcript positions
					$transcript_cds_start	= $transcript->coding_region_start;
					$transcript_cds_end 	= $transcript->coding_region_end;
					$transcript_cdna_start	= $transcript->cdna_coding_start;
					$transcript_cdna_end	= $transcript->cdna_coding_end;
					$transcript_start		= $transcript->{start};
					$transcript_end			= $transcript->{end};
					
					#Get extra transcript information
					$transcript_strand	= $transcript->{strand};
					$transcript_name	= $transcript->{external_name};
					
					#Retrieve chromosome
					$chromosome = $transcript->slice()->seq_region_name();
						
					#Make transcript mapper
					my $transcript_mapper = Bio::EnsEMBL::TranscriptMapper->new($transcript);
					my $ensembl_cdna_coordinate;
					
					
					#Determine the correct ensembl cDNA_position representation of the nucleotide 
					#keeping the strand in mind and knowing that count in ensembl start at 1
					$ensembl_cdna_coordinate=$transcript_cdna_start+$cdna_pos-1;
					my @coords = $transcript_mapper->cdna2genomic( $ensembl_cdna_coordinate, $ensembl_cdna_coordinate );
					$gDNA_position = $coords[0]{start};
					
					if($type eq $TYPE_INTRON){
						
						#Fetch extra intron information
						$intron_sign 		= $cdna_entry->{intron_sign};
						$intron_position	= $cdna_entry->{intron_position};
						
						#Based on transcript strand add or minus the
						#gdna position with the intron_position
						if($transcript_strand == 1){
							if($intron_sign eq "+"){
								$gDNA_position += $intron_position;
							}else{
								$gDNA_position -= $intron_position;
							}
						}else{
							if($intron_sign eq "+"){
								$gDNA_position -= $intron_position;
							}else{
								$gDNA_position += $intron_position;
							}
						}				
					}
				}
				
				#Push result into array
				push(
					@results,
					{
						cdna_change			=> $cdna_change,
						transcript_id 		=> $transcript_id,
						transcript_name		=> $transcript_name,
						transcript_start	=> $transcript_start,
						transcript_end		=> $transcript_end,
						transcript_cds_start=> $transcript_cds_start,
						transcript_cds_end 	=> $transcript_cds_end,
						gene_id				=> $gene_id,
						gene_name       	=> $gene_name,
						transcript_strand 	=> $transcript_strand,
						cdna_pos 			=> $cdna_pos,
						gdna_pos			=> $gDNA_position,
						chromosome			=> $chromosome
					}
				);
			}
			
		}#end type

	}#end transcripts
	
	return @results;
}




###########################################################################
# gdna_to_cdna_convertor:
# 	this function converts the given gDNA position to the corresponding
# 	cDNA position.
#
# Use:
# my @gdna_coord = (
# 	{
#		gdna			=> 465846545,
#		chromosome  	=> "15",
#		strand			=> 1,
#		variant			=> "G>T"
# 	}
# );
#
#
# my @result = $convertor->gdna_to_cdna_convertor( transcripts => \@gdna_coord );
#
# return: array that returns a hash with an array of transcripts for every 
# given hash in the gdna_coord array
###########################################################################
sub gdna_to_cdna_convertor{
	my ($self, %input_array) = @_;

	my %positions;

	# make a hash ref from the input array
	foreach my $var_ref ( @{ $input_array{positions} } ) {
		push (@{$positions{ $self->{organism}}{$var_ref->{chromosome}}}, 
				{ 
					gdna_pos 		=> $var_ref->{gdna},
					variant			=> $var_ref->{variant},
					strand			=> $var_ref->{strand}
				});
	}

	# set the variables to return
	my @results=();

	foreach my $organism ( keys %positions ) {
			
		#Loop over different chromosomes
		foreach my $chrom (keys %{$positions{$organism}}){
			
			#Loop over the different gDNA positions of chromosomes
			foreach my $position ( @{$positions{$organism}{$chrom}} ){
				
				#Define variables
				my ( 	$gdna_pos,		$variant,
						$strand,		@transcripts
						
					) = undef;
					
				#Get rest of necessary information
				$gdna_pos	= $position->{gdna_pos};
				$strand		= $position->{strand};
				$variant	= $position->{variant};
				@transcripts=();
				
				#Chromosome slice
				my $chrom_slice = $self->{adaptors}->{slice_adaptor}->fetch_by_region( 'chromosome', $chrom);
				my $chrom_end	= $chrom_slice->end();
					
				# get the slice with the max and min start positions
				my $slice = $self->{adaptors}->{slice_adaptor}->fetch_by_region( 'chromosome', $chrom, $gdna_pos, $gdna_pos, $strand );
				
				#Determine ensembl variant		
				my $ensembl_variant = $variant;
				$ensembl_variant =~ s/>/\//;

				#Get information about the variant
				my $variantfeature =
				  Bio::EnsEMBL::Variation::VariationFeature->new(
					-start         => 1,
					-end           => 1,
					-slice         => $slice,
					-allele_string => $ensembl_variant,
					-strand        => $strand,
					-adaptor       => $self->{adaptors}->{variant_adaptor}
				  );
				  
				  
				  #Get all transcripts for the variation
				  foreach my $transcriptvariation (@{$variantfeature->get_all_TranscriptVariations})
				  {
						#Define variables
						my (
							$transcript_id, $transcript,
							$translation,   $transcript_strand,
							$gene,          $gene_id,
							$gene_name,     $cdnasequence,
							$protsequence,  $mutcdnaseq,
							$mutprotseq,    $cdnaseqobj,
							$mutcdnaseqobj, $peptide_string,
							$sift,			$sift_score,
							$condel,		$condel_score,
							$polyphen,		$polyphen_score,
							$amino_acid_change, $cDNA_position,
							$cDNA_change,	$transcript_cds_start,
							$transcript_cds_end, $transcript_cdna_start,
							$transcript_cdna_end,$transcript_start,
							$transcript_end
						) = undef;
								
								
						#Fetch amino acid change
						$amino_acid_change=$transcriptvariation->pep_allele_string;
						
						#If transcript exists: retrieve that transcript
						if ( $transcriptvariation->transcript ) {
							$transcript_id 	= $transcriptvariation->transcript->stable_id;
							$transcript 	= $self->{adaptors}->{transcript_adaptor}->fetch_by_stable_id($transcript_id);

							#If transcript exists then fetch the corresponding gene
							if ($transcript) {
								$transcript_strand = $transcriptvariation->transcript->strand;
								$gene 		= $self->{adaptors}->{gene_adaptor}->fetch_by_transcript_stable_id($transcript_id);
								$gene_id 	= $gene->stable_id 		if ($gene);
								$gene_name 	= $gene->external_name	if ($gene);
								
								
								#Get transcript positions
								$transcript_cds_start	= $transcript->coding_region_start;
								$transcript_cds_end 	= $transcript->coding_region_end;
								$transcript_cdna_start	= $transcript->cdna_coding_start;
								$transcript_cdna_end	= $transcript->cdna_coding_end;
								$transcript_start		= $transcript->{start};
								$transcript_end			= $transcript->{end};
								
								if($transcriptvariation->cdna_start){
									if($transcript->cdna_coding_start < $transcriptvariation->cdna_start){
										$cDNA_position 	= $transcriptvariation->cdna_start -$transcript->cdna_coding_start +1;
										$cDNA_change	= "c.".$cDNA_position.$variant;
									}
									
								}else{
									
								}
								
								
								push (@transcripts, { 	
										gene_id			=> $gene_id,
										gene_name		=> $gene_name,
										consequence     => join(",", @{$transcriptvariation->consequence_type}),
										transcript_strand=>$transcript_strand,
										transcript_id	=> $transcript_id,
										cDNA_start		=> $transcriptvariation->cdna_start,
										cdna_end		=> $transcriptvariation->cdna_end,
										cdna_pos		=> $cDNA_position,
										transcript_cdna => $transcript->cdna_coding_start,
										cdna_change		=> $cDNA_change,
										transcript_start=> $transcript_start,
										transcript_end	=> $transcript_end,
										transcript_cds_start=> $transcript_cds_start,
										transcript_cds_end=> $transcript_cds_end
							
									}
								);
							}
								
						}
					}

					#Push result into array
					push(
						@results,
						{
							transcripts 		=> \@transcripts,
							gdna_pos 			=> $gdna_pos,
							chromosome			=> $chrom
						}
					);
			}
			
		}#end position

	}#end transcripts
	
	return @results;
}




###########################################################################
# get_database_version:
# 	this function will get the database version from the ensembl database
#
# Use:
# 	my $group = "core";
# 	my %version = $convertor->get_version( group => $group );
#
# return: version of database group
###########################################################################
sub get_database_version {
	my ($self, $group)=@_;

	#Determine organism
	my $organism = $self->{organism};

	# set the variables to return
	my %version;

	#Make adaptor
	my $db_adaptor 				= $self->{registry}->get_DBAdaptor( $organism, $group );
	$version{$group}{name} 	= $db_adaptor->dbc()->dbname();
	
	
	my $regexpr	= "(.*)_($group)_([0-9]+)_([0-9]+)";
	if($version{$group}{name} =~ m/$regexpr/){
		my $organism_name	= $1;
		my $group_name		= $2;
		my $ensembl_version	= $3;
		my $build			= $4;
		
		$version{$group}{organism}	= $organism;
		$version{$group}{build}		= $build;
		$version{$group}{ensembl_version}=$ensembl_version;
	}

	return \%version;
}

1;
