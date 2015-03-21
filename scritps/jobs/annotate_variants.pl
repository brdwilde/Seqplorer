#!/usr/bin/perl -w
use strict;
use warnings;
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
		'unknownvcf'			=> { type => 'string' }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $UNKNOWNVCF 		= $BitQC->getRunConfig('unknownvcf');
my $REMOVE      	= $BitQC->getRunConfig('remove');
my $BUILD        	= $BitQC->getRunConfig('genomebuild');
my $VARIANTSCOLL 	= $BitQC->getRunConfig('variantscol');

#Get command
my $ENSEMBL_REGISTRY = $BitQC->getCommand('ensemblAPI');

my $ENSEMBL_HOST = $BitQC->{node_config}->{executables}->{ensemblAPI}->{host};
my $ENSEMBL_USER = $BitQC->{node_config}->{executables}->{ensemblAPI}->{user};
my $ENSEMBL_PASS = $BitQC->{node_config}->{executables}->{ensemblAPI}->{pass};
my $ENSEMBL_PORT = $BitQC->{node_config}->{executables}->{ensemblAPI}->{port};

#Get databaseadaptor
my $DATABASE_ADAPTOR = $BitQC->{DatabaseAdapter};

#Genomeinformation
my $ENSEMBL_ORGANISM = $BitQC->{genome}->{organism}->{ensemblname};

######################################################################################
# READ VARIANTS FROM VCF FILE
######################################################################################

#Determine the variants from the VCF file
my %vcf_variants;

# create local file object
my $variantsfile = $BitQC->{fileadapter}->createFile( {
	'compression' => 'gzip',
    'filetype' => 'txt',
	'file' => $UNKNOWNVCF,
    'type' => 'local'
});
my $variantsfilepointer = $variantsfile->getReadPointer();	

# remember the max and min position to get the genome slice
my $maxposition = 0;
my $minposition = 999999999999999;
my $chr;

my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
my $variants_collection = $mongodb->$VARIANTSCOLL;

#Loop over the lines in the VCF file
while (<$variantsfilepointer>) {
	chomp;

	#Get the different fields
	my @variant_line_fields = split( /\t/, $_ );

	my $chromosome 			= $variant_line_fields[1];
	my $start_pos  			= $variant_line_fields[2];
	my $end_pos    			= $variant_line_fields[3];
	my $variant    			= $variant_line_fields[4];
	my $ensemblmax_start	= $variant_line_fields[5];
	my $ensemblmin_star		= $variant_line_fields[6];
	my $ensemblmin_end		= $variant_line_fields[7];
	my $ensemblmax_end		= $variant_line_fields[8];
	my $ensemblstrand		= $variant_line_fields[9];
	my $ensembl_so_term		= $variant_line_fields[10];
	my $variant_id 			= $variant_line_fields[11];

	# remember the max and min position to get the genome slice
	$maxposition = $end_pos   if ( $end_pos > $maxposition );
	$minposition = $start_pos if ( $start_pos < $minposition );
	
	$BitQC->log_error( message =>
		"Multiple chromosomes in one input file not supported by variant annotate job!"
	) unless ( !$chr || $chr eq $chromosome );
	
	$chr = $chromosome;

	#Add variant to variant list
	$vcf_variants{$variant_id} = {
		start   			=> $start_pos,
		end     			=> $end_pos,
		variant 			=> $variant,
		strand 				=> $ensemblstrand,
	};
	$vcf_variants{$variant_id}{inner_start} = $ensemblmax_start if ($ensemblmax_start);
	$vcf_variants{$variant_id}{outer_start} = $ensemblmin_star if ($ensemblmin_star);
	$vcf_variants{$variant_id}{inner_end} = $ensemblmin_end if ($ensemblmin_end);
	$vcf_variants{$variant_id}{outer_end} = $ensemblmax_end if ($ensemblmax_end);
	$vcf_variants{$variant_id}{class_SO_term} = $ensembl_so_term if ($ensembl_so_term);

}
close($variantsfilepointer);

######################################################################################
# START ANNOTATION
######################################################################################
use Data::Dumper::Simple;

if (%vcf_variants) {

	#Make ensembl registry
	$ENSEMBL_REGISTRY->load_registry_from_db(
		-host    => $ENSEMBL_HOST,
		-user    => $ENSEMBL_USER,
		-pass    => $ENSEMBL_PASS,
		-port    => $ENSEMBL_PORT,
		#-verbose => '1'
	);

	# get all the ensembl adapters for this organism
	my $slice_adaptor =
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'Slice' );
	my $gene_adaptor =
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'Gene' );
	my $transcript_adaptor =
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'Transcript' );
	my $translation_adaptor =
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, "core", "translation" );
	my $prot_feat_adaptor =
	 	$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core','proteinfeature' );
	my $db_entry_adaptor =
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'DBEntry' );
	my $karyo_adaptor = 
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'Core', 'KaryotypeBand' );
	my $variant_adaptor =
	  	$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'variation', 'VariationFeature' );
	my $structural_variation_adaptor = 
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'variation', 'structuralvariationfeature');
	my $transcript_variation_adaptor =
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'variation', 'transcriptvariation' );
	#my $var_an_adaptor =
	# 	$ENSEMBL_REGISTRY->get_adaptor($ENSEMBL_ORGANISM, 'variation', 'variationannotation');
	my $phenotypefeature_adaptor = 
		$ENSEMBL_REGISTRY->get_adaptor($ENSEMBL_ORGANISM, 'variation', 'phenotypefeature');
	my $variationset_adaptor = 
		$ENSEMBL_REGISTRY->get_adaptor($ENSEMBL_ORGANISM,'variation','variationset');
	my $regfeat_adaptor = 
		$ENSEMBL_REGISTRY->get_adaptor( $ENSEMBL_ORGANISM, 'funcgen', 'regulatoryfeature');
	my $method_link_adaptor =
		$ENSEMBL_REGISTRY->get_adaptor( 'Multi', 'compara', 'MethodLinkSpeciesSet' );
    my $constrained_element_adaptor =
     	$ENSEMBL_REGISTRY->get_adaptor('Multi','compara','ConstrainedElement');
    my $conservation_score_adaptor = 
    	$ENSEMBL_REGISTRY->get_adaptor('Multi', 'compara', 'ConservationScore');

	# get the genomic slice at this region
	my $slice =
		$slice_adaptor->fetch_by_region( 'chromosome', $chr, $minposition, $maxposition, 1 );

	if ($slice){

		foreach my $mongoid ( keys %vcf_variants ) {
			my $start   = $vcf_variants{$mongoid}{'start'};
			my $end     = $vcf_variants{$mongoid}{'end'};
			my $variant = $vcf_variants{$mongoid}{'variant'};
			my $strand  = $vcf_variants{$mongoid}{'strand'};
			my $inner_start = $vcf_variants{$mongoid}{inner_start};
			my $outer_start = $vcf_variants{$mongoid}{outer_start};
			my $inner_end = $vcf_variants{$mongoid}{inner_end};
			my $outer_end = $vcf_variants{$mongoid}{outer_end};
			my $class_SO_term = $vcf_variants{$mongoid}{class_SO_term};

			#VariationFeature= This is a class representing the genomic position of a nucleotide variation
			#from the ensembl-variation database
			my $variantfeature;
			if (defined ($class_SO_term)) {
		        $variantfeature = Bio::EnsEMBL::Variation::StructuralVariationFeature->new_fast({
		            start          => $start,
	    	        inner_start    => $inner_start,
	        	    outer_start    => $outer_start,
	            	end            => $end,
	            	inner_end      => $inner_end,
	            	outer_end      => $outer_end,
		            strand         => $strand,
	    	        adaptor        => $structural_variation_adaptor,
		            chr            => $chr,
	    	        class_SO_term  => $class_SO_term,
	        	});
			} else {
				$variantfeature = Bio::EnsEMBL::Variation::VariationFeature->new(
					-start         => $start - $minposition + 1, # position is relative to the slice
					-end           => $end - $minposition + 1, # position is relative to the slice
					-slice         => $slice,
					-allele_string => $variant,
					-strand        => $strand,
					-adaptor       => $variant_adaptor,
				);
			}
		    
			#feature_Slice= This is a convenience method to return a slice that covers the
			#Area of this feature. The feature start will be at 1 on it, and
			#it will have the length of this feature.
			my $feature_slice = $variantfeature->feature_Slice();

			# get the alternate allele from the variatn string
			$variant =~ /^[-ACTG]+\/(.+)/;
		    my $altallele = $1;

			my $ref_base = $feature_slice->seq();
			# TODO: check if ref base matches?

			# store alle the annotation information we retreive in this hash
			my %annotation;

			# get overlapping genomic repeats:
			my @repeats = @{ $feature_slice->get_all_RepeatFeatures() };

			foreach my $repeat (@repeats) {
				my %repeats;
	        	$repeats{id} = $repeat->display_id();
	        	$repeats{start} = $repeat->seq_region_start();
	        	$repeats{end} = $repeat->seq_region_end();
	        	# check if strand is given for repeat! $repeats{seq} = $repeat->seq() if $repeat->seq();
	        	push (@{$annotation{repeat}}, \%repeats) if (%repeats);
			}

			# get the chormosome bands here:
			my @karyobands = @{ $karyo_adaptor->fetch_all_by_Slice($feature_slice) };
			foreach my $karyoband (@karyobands){
	  			push (@{$annotation{karyo}}, $karyoband->name()) if ($karyoband->name());
			}

			# get overlapping regulatory features
			my @reg_feats = @{$regfeat_adaptor->fetch_all_by_Slice($feature_slice)};

			foreach my $rf (@reg_feats){

				my @motif_features = @{$rf->regulatory_attributes('motif')};

				#get al sequenc motif regluatory features
				foreach my $motif_feature (@motif_features) {
					my %motif;
					$motif{display_label} = $motif_feature->display_label;
				  	$motif{start} = $motif_feature->seq_region_start; 
					$motif{end} = $motif_feature->seq_region_end;
					$motif{name} = $motif_feature->binding_matrix->name;
					$motif{seq} = $motif_feature->seq;
					$motif{score} = $motif_feature->score;
					# get cell types for this motif
					# my $afs = $motif_feature->associated_annotated_features();	
					# foreach my $feat (@$afs){
					# 	#Each feature is an annotated feature
					# 	print_feature($feat); 
					# }
					push (@{$annotation{regulation}}, \%motif) if (%motif && ($motif{start} <= $end && $motif{end} >= $start));
				}
			}

			# get conservation and cross species information
	        my $method_link_species_set = $method_link_adaptor->fetch_by_method_link_type_species_set_name("GERP_CONSTRAINED_ELEMENT","mammals");

	        my $slice_size = abs($feature_slice->end-$feature_slice->start)+1;

	        my $conservation_scores = $conservation_score_adaptor->fetch_all_by_MethodLinkSpeciesSet_Slice($method_link_species_set, $feature_slice, $slice_size);

	        foreach my $score (@$conservation_scores) {
	        	my %conservation;
				$conservation{ob} = $score->observed_score; 
				$conservation{ex} = $score->expected_score; 
				$conservation{diff} = $score->diff_score;
				#$score->position, 
				#$score->genomic_align_block;
				push (@{$annotation{conservation}}, \%conservation) if (%conservation);
	   		}

			if ( defined( $variantfeature->adaptor->db ) ) {
				if ( $feature_slice->start > $feature_slice->end ) {
					# swap start and end
					( $feature_slice->{'start'}, $feature_slice->{'end'} ) =
					  ( $feature_slice->{'end'}, $feature_slice->{'start'} );
				}

				# create arrays to hold population disease annotation for alleles
				my @synonyms;
				my @alleles;
				my @annotations;
				# get all variants with the same position
				while (	my $existing_obj = shift @{	$variantfeature->adaptor->fetch_all_by_Slice($feature_slice)}){
					my $existing_obj_strand = $existing_obj->strand;

					# check if our variant is the same as the known variant in the database
					if ( $existing_obj->seq_region_start == $variantfeature->seq_region_start
						&& $existing_obj->seq_region_end ==	$variantfeature->seq_region_end
						&& $existing_obj->allele_string eq $variant ) {
						# create the variant object
						my $var_object = $existing_obj->variation;

						# get the name and source of the name for this variant
						$annotation{name} = $var_object->name if ($var_object->name);
						#$annotation{name_source} = $var_object->source if ($var_object->source);
						#$annotation{name_version} += $var_object->version if ($var_object->version);

						# get all alternate names
						my $sources = $var_object->get_all_synonym_sources();
						foreach my $src (@$sources) {
							my %synonyms;
							$synonyms{source} = $src;
							$synonyms{synonyms} = $var_object->get_all_synonyms($src);
							push( @synonyms, \%synonyms );
						}

						# get some dbSNP information for this variant if available
						$annotation{dbsnp}{anc_allele} = $var_object-> ancestral_allele	if ($var_object-> ancestral_allele)	;
						$annotation{dbsnp}{min_allele} = $var_object-> minor_allele	if ($var_object-> minor_allele);
						$annotation{dbsnp}{mac}	+= 	$var_object-> minor_allele_count if ($var_object-> minor_allele_count);
						$annotation{dbsnp}{maf}	+= 	$var_object-> minor_allele_frequency if ($var_object-> minor_allele_frequency);
						#$annotation{dbsnp}{clinical} = $var_object->get_all_clinical_significance_statuses if ($var_object->get_all_clinical_significance_statuses);

						# get all alternate alleles for this variatn position
						my @allele =
						  @{ $var_object->get_all_Alleles() };

						#Retrieve alleles and frequencies and add them to the annotation
						foreach my $allele (@allele) {
							my %alleles;
							if ( $allele->frequency ) {
								$alleles{all} = $allele->allele;
								$alleles{pop} = $allele->population->name;
								$alleles{freq} += $allele->frequency;
								# store the population frequency of this variants alterante allele
								if ($alleles{all} eq $altallele){
									$annotation{popfreq}{$alleles{pop}} = $alleles{freq};
								}
							}
							# store all alternate alleles as an array
							push( @alleles, \%alleles ) if (%alleles);
						}

						# # get alle clinical annotations for this variant
						# my @variation_annotation;
						# @variation_annotation =
						# 	@{$var_an_adaptor->fetch_all_by_Variation($var_object)} if ($var_an_adaptor->fetch_all_by_Variation ($var_object));
											
						# foreach my $an (@variation_annotation) {
						# 	my %annotations;
						# 	$annotations{study_descr} = $an->study_description	if ($an->study_description);
						# 	$annotations{phen_descr} = $an->phenotype_description 			if($an->phenotype_description);
						# 	$annotations{ass_var_risk_all}	= $an->associated_variant_risk_allele 	if($an->associated_variant_risk_allele);
						# 	$annotations{var_risk_all_freq}	+= $an->risk_allele_freq_in_controls 	if($an->risk_allele_freq_in_controls);
						# 	#$annotations{source} = $an->source if ($an->source);
						# 	#$annotations{pval} = $an->p_value if ($an->p_value);
						# 	#$annotations{riskallele} = $an->risk_allele if ($an->risk_allele);

						# 	# if annotations are found, store them in the variant annotation as well as an array
						# 	if (%annotations){
						# 		push( @annotations, \%annotations );

						# 		if ($annotations{study_descr}){
						# 			$annotation{ann}{$annotations{study_descr}}{phen_descr} = $annotations{phen_descr} if ($annotations{phen_descr});
						# 			$annotation{ann}{$annotations{study_descr}}{ass_var_risk_all} = $annotations{ass_var_risk_all} if ($annotations{ass_var_risk_all});
						# 			$annotation{ann}{$annotations{study_descr}}{var_risk_all_freq} = $annotations{var_risk_all_freq} if ($annotations{var_risk_all_freq});
						# 		}
						# 	}
						# }
									# get all the phenotypes associated with this feature
						foreach my $pf (@{$phenotypefeature_adaptor->fetch_all_by_Variation($var_object)}) {

							my %phenotype;
							$phenotype{name} = $pf->variation_names;
							$phenotype{description} = $pf->phenotype->description,
							$phenotype{source} = $pf->source;
									
							$phenotype{'p-value'} = $pf->p_value if (defined($pf->p_value));				
							$phenotype{risk_allele} = (split /\-/, $pf->risk_allele)[1] if (defined $pf->risk_allele);

							push (@{$annotation{phenotype}}, \%phenotype) if (%phenotype);

							# if ($annotations{study_descr}){
							# 	$annotation{ann}{$annotations{study_descr}}{phen_descr} = $annotations{phen_descr} if ($annotations{phen_descr});
							# 	$annotation{ann}{$annotations{study_descr}}{ass_var_risk_all} = $annotations{ass_var_risk_all} if ($annotations{ass_var_risk_all});
							# 	$annotation{ann}{$annotations{study_descr}}{var_risk_all_freq} = $annotations{var_risk_all_freq} if ($annotations{var_risk_all_freq});
							# }
						}
					}
				}
				$annotation{syn} = \@synonyms if (@synonyms);    #alternative names for this vairant
				$annotation{alt} = \@alleles if (@alleles); #alternative alleles and their frequency
				#$annotation{allann} = \@annotations if (@annotations); #disease annotations and their frequency


			}

			# get the transcripts and annotate!
			my @transcripts;
			my @genes;
			my %gene;

			# Get the consequence types
			foreach my $transcriptvariation (@{ $variantfeature->get_all_TranscriptVariations } ){

				my %transcript;
				#get the consequence types if they are defined
				# we get the transcriptvariation consequences for the specific allele, not the entire transcript variation!
				#$transcript{con} = $transcriptvariation->consequence_type if ( defined( $transcriptvariation->consequence_type ) );

				# correct positions for - strand genes/transcripts
				if (   $transcriptvariation->cdna_start	&& $transcriptvariation->cdna_end
					&& $transcriptvariation->cdna_start > $transcriptvariation->cdna_end ){
					( $transcriptvariation->{'cdna_start'},	$transcriptvariation->{'cdna_end'} )
					  = ( $transcriptvariation->{'cdna_end'}, $transcriptvariation->{'cdna_start'} );
				}

				if (   $transcriptvariation->translation_start && $transcriptvariation->translation_end
					&& $transcriptvariation->translation_start > $transcriptvariation->translation_end ){
					( $transcriptvariation->{'translation_start'}, $transcriptvariation->{'translation_end'})
					  = ($transcriptvariation->{'translation_end'},	$transcriptvariation->{'translation_start'});
				}

				my ( $transcript_id, $transcript, $transcript_strand, $gene, $cdnasequence, $protsequence,
					$mutcdnaseq,    $mutprotseq,   $cdnaseqobj, $mutcdnaseqobj ) = undef;

				#If transcript exists: retrieve that transcript
				if ( $transcriptvariation->transcript ) {
					$transcript_id = $transcriptvariation->transcript->stable_id;
					$transcript{tr} = $transcript_id;
					$transcript = $transcript_adaptor->fetch_by_stable_id($transcript_id);

					#If transcript exists then fetch the corresponding gene
					if ($transcript) {

						if ($transcript->get_all_xrefs()) {
							my @xrefs;
							foreach my $trans_xref (@{$transcript->get_all_xrefs()}) {
								my %xrefs;

								$xrefs{database} = $trans_xref->database  if ($trans_xref->database);
								$xrefs{description} = $trans_xref->description if ($trans_xref->description);
								$xrefs{display_id} = $trans_xref->display_id if ($trans_xref-> display_id);
								$xrefs{release} = $trans_xref->release if ($trans_xref-> release);

								if (%xrefs){
									foreach my $xdbkey (keys %xrefs){
										push(@{$transcript{xrefs}{$xrefs{database}}{$xdbkey}},$xrefs{$xdbkey}) unless ($xdbkey eq 'database');
									}
									push (@xrefs,\%xrefs);
								}
							}
							$transcript{allxrefs} = \@xrefs;
						}
						# set flag if transcript is cannonical
						$transcript{canonical} = 1 if ($transcript->is_canonical());

						# set the transcript strand
						$transcript_strand = (
							$transcriptvariation->transcript->strand == -1
							? '-'
							: '+'
						);
						$transcript{str} = $transcript_strand;

						$gene = $gene_adaptor->fetch_by_transcript_stable_id( $transcript_id );
						
						if ($gene) {
							my $stableid = $gene->stable_id;
							$transcript{gene}   = $gene->external_name;
							$transcript{geneid} = $stableid;
							if (!$gene{$stableid}){
								$gene{$stableid}{gene}   = $gene->external_name;
								$gene{$stableid}{geneid} = $gene->stable_id;

								# we get the gene specific xrefs (already have the transcritp ones!)
								if ($gene->get_all_object_xrefs()) {
									my @xrefs;
									foreach my $gene_xref (@{$gene->get_all_object_xrefs()}) {
										my %xrefs;

										$xrefs{database} = $gene_xref->database  if ($gene_xref->database);
										$xrefs{description} = $gene_xref->description if ($gene_xref->description);
										$xrefs{display_id} = $gene_xref->display_id if ($gene_xref-> display_id);
										$xrefs{release} = $gene_xref->release if ($gene_xref-> release);

										if (%xrefs){
											foreach my $xdbkey (keys %xrefs){
												push(@{$gene{$stableid}{xrefs}{$xrefs{database}}{$xdbkey}},$xrefs{$xdbkey}) unless ($xdbkey eq 'database');
											}
											push (@xrefs,\%xrefs);
										}
									}
									$gene{$stableid}{allxrefs} = \@xrefs;
								}							
							}
						}

						my $tvas =
						  $transcriptvariation
						  ->get_all_alternate_TranscriptVariationAlleles();

						my @ensembl_consequences;
						my @so_consequences;
						if (scalar (@{$tvas}) > 1){
							print "Found more than one Transcript variation allele for $mongoid\n";
						}
						foreach my $tva ( @{$tvas} ) {

						  	# TODO: check if no more than one element is in this array?

							my $ocs = $tva->get_all_OverlapConsequences();


							foreach my $oc(@{$ocs}) {
								push @ensembl_consequences, $oc->display_term;
								push @so_consequences, $oc->SO_term;
							}

					 		#Fetch SIFT, PolyPhen and Condel predictions for the transcript
							$transcript{sift} = $tva->sift_prediction
							  if ( defined( $tva->sift_prediction ) );
							$transcript{sifts} = $tva->sift_score
							  if ( defined( $tva->sift_score ) );
							$transcript{pphe} = $tva->polyphen_prediction
							  if ( defined( $tva->polyphen_prediction ) );
							$transcript{pphes} = $tva->polyphen_score
							  if ( defined( $tva->polyphen_score ) );
							# TODO: install condel plugin
							#$transcript{cond} = $tva->condel_prediction
							#  if ( defined( $tva->condel_prediction ) );
							#$transcript{conds} = $tva->condel_score
							#  if ( defined( $tva->condel_score ) );
						}
						$transcript{con} = \@ensembl_consequences;
						$transcript{con_so} = \@so_consequences;

						#WDMEESTE
						#cdna_start= Get the start position of this variation on the transcript in cDNA coordinates.
						if ( $transcriptvariation->cdna_start ) {
							$transcript{cdnapos} = $transcriptvariation->cdna_start;
							$transcript{cdspos}  = $transcriptvariation->cds_start
							  if ( $transcriptvariation->cds_start );
							$transcript{cods} = $transcriptvariation->codons
							  if ( $transcriptvariation->codons );
							$transcript{ppos} =
							  $transcriptvariation->translation_start
							  if ( $transcriptvariation->translation_start );

							#WDMEESTE
							#spliced_seq= Retrieves all Exon sequences and concats them together
							$cdnasequence = $transcript->spliced_seq();

							$cdnaseqobj = Bio::Seq->new(
								-seq      => $transcript->spliced_seq(),
								-alphabet => 'dna',
							);

							if ($cdnasequence) {

					   			#WDMEESTE
					   			#translate= Return the peptide (plus eventual stop codon) for
					   			#this transcript.  Does N-padding of non-phase
					   			#matching exons.
					   			if ($transcript->translate()){

									$protsequence = $transcript->translate();

									my $transcriptslice = $transcript->feature_Slice();

									my $translation = $transcript->translation();

									my @domainfeatures;
									@domainfeatures = @{$translation->get_all_DomainFeatures ()} if ($translation->get_all_DomainFeatures ());

									foreach my $domain (@domainfeatures) {
										$domain->slice($transcriptslice);
										#$domain->project_to_slice($feature_slice);
										if ($domain->overlaps($variantfeature)){
											my %domain;
											if ($domain->idesc()){
												$domain{name} = $domain->idesc();
												$domain{accession} = $domain->interpro_ac() if ($domain->interpro_ac());
												$domain{start} = $domain->start();
												$domain{end} = $domain->end();

												$domain{gstart} = $domain->seq_region_start();
												$domain{gend} =  $domain->seq_region_end();
												push (@{$transcript{domain}}, \%domain);											
											}
										}
									}
					   			}
							

								$variant =~ /([A-Z]+|-)\/([A-Z]+|-)/;

								$transcript{cdnas} = "c."
								  . $transcriptvariation->cdna_start
								  . $1 . ">"
								  . $2;
								my $to = $2;
								$to = '' if ( $2 eq '-' );
								if (   $transcript_strand eq '-'
									&& $to ne '' )
								{
									my $toobject = Bio::Seq->new(
										-seq      => $to,
										-alphabet => 'dna',
									);
									$to = $toobject->revcom->seq();
								}

								if ($transcriptvariation->cdna_end){
									# TODO: some transcriptvariatins do not get an cdna_end: why? Bug in ensembl?
									my $mut = Bio::EnsEMBL::SeqEdit->new(
										-START   => $transcriptvariation->cdna_start,
										-END     => $transcriptvariation->cdna_end,
										-ALT_SEQ => $to,
										-NAME    => 'variant',
										-DESCRIPTION => 'cDNA variant',
										-CODE        => '_rna_edit'
									);
		
									my $attribute = $mut->get_Attribute();
									$transcript->add_Attributes($attribute);
									$mutcdnaseq = $cdnasequence;
									$mut->apply_edit( \$mutcdnaseq );
		
									$mutcdnaseqobj = Bio::Seq->new(
										-seq      => $mutcdnaseq,
										-alphabet => 'dna',
									);
								}

								#Fetch amino acid change
								$transcript{peps} =
								  $transcriptvariation->pep_allele_string
								  if (
									defined(
										$transcriptvariation->pep_allele_string
									)
								  );

								if ( $transcript{peps} =~ /[A-Z]+\/[A-Z]+/ ) {
									my $seqobj = Bio::Seq->new(
										-seq => $transcript->translateable_seq(),
										-alphabet => 'dna',
									);

									$mutprotseq = $seqobj->translate();
								}
							}
						}

				   # TODO: rewrite genesplices section
				   #			if ( $annotation->{mut_cdna_seq} ) {
				   #				my $cdna_out;
				   #				( my $fh5, $cdna_out ) = tempfile( DIR => $SCRATCHDIR );
				   #				my $cdna_fasta = Bio::SeqIO->new(
				   #					-file   => "> $cdna_out",
				   #					-format => 'fasta'
				   #				);
				   #				$annotation->{cdna_seq}
				   #				  ->display_id( $variant_ids{$pos}{$variant}->value );
				   #				$cdna_fasta->write_seq( $annotation->{cdna_seq} );
				   #				my @genesplicer =
				   #				  `genesplicer $cdna_out /opt/GeneSplicer/human/`;
				   #				my %known = map { $_, 1 } @genesplicer;
				   #
				   #				my $mut_cdna_out;
				   #				( my $fh6, $mut_cdna_out ) = tempfile( DIR => $SCRATCHDIR );
				   #				my $mut_cdna_fasta = Bio::SeqIO->new(
				   #					-file   => " > $mut_cdna_out",
				   #					-format => 'fasta'
				   #				);
				   #
				   #				$annotation->{mut_cdna_seq}
				   #				  ->display_id( $variant_ids{$pos}{$variant}->value );
				   #				$mut_cdna_fasta->write_seq( $annotation->{mut_cdna_seq} );
				   #
				   #				my @mut_genesplicer =
				   #				  `genesplicer $mut_cdna_out /opt/GeneSplicer/human/`;
				   #				my %mutants = map { $_, 1 } @mut_genesplicer;
				   #
				   #				unlink( $mut_cdna_out, $cdna_out );
				   #
				   #				for my $knownsite ( keys %known ) {
				   #					if ( $mutants{$knownsite} ) {
				   #						delete $known{$knownsite};
				   #						delete $mutants{$knownsite};
				   #					}
				   #				}
				   #
				   #				# only changes remain!
				   #				for my $knownsite ( keys %known ) {
				   #					my @known = split( /\s/, $knownsite );
				   #					for my $changedsite ( keys %mutants ) {
				   #						my @changed = split( /\s/, $changedsite );
				   #						if (   $known[0] == $changed[0]
				   #							&& $known[1] == $changed[1] )
				   #						{
				   #							my $scoredif = $changed[2] - $known[2];
				   #							if ( abs($scoredif) > 1 ) {
				   #								my %splice;
				   #								$splice{c} = 'alt';
				   #								$splice{t} =
				   #								  join( " ", @known[ 3 .. $#known ] );
				   #								$splice{s} += $known[2];
				   #								$splice{vt} =
				   #								  join( " ", @changed[ 3 .. $#changed ] );
				   #								$splice{vs} = $scoredif;
				   #								$splice{p} += $known[0];
				   #
				   #								# same position = score changed!
				   #								push( @{ $annotations{gsp} }, \%splice );
				   #							}
				   #							delete $known{$knownsite};
				   #							delete $mutants{$changedsite};
				   #						}
				   #					}
				   #				}
				   #
				   #				# only new or deleted splice sites remain
				   #				for my $knownsite ( keys %known ) {
				   #					my @known = split( /\s/, $knownsite );
				   #					my %splice;
				   #					$splice{c} = 'del';
				   #					$splice{t} = join( " ", @known[ 3 .. $#known ] );
				   #					$splice{s} += $known[2];
				   #					$splice{p} += $known[0];
				   #					push( @{ $annotations{gsp} }, \%splice );
				   #
				   #				}
				   #				for my $changedsite ( keys %mutants ) {
				   #					my @changed = split( /\s/, $changedsite );
				   #					my %splice;
				   #					$splice{c} = 'new';
				   #					$splice{vt} = join( " ", @changed[ 3 .. $#changed ] );
				   #					$splice{s} += $changed[2];
				   #					$splice{p} += $changed[0];
				   #					push( @{ $annotations{gsp} }, \%splice );
				   #
				   #				}
				   #			}

					}
				}
				push( @transcripts, \%transcript );
			} #end while (line 257 while(my $transcriptvariation = shift @{$variantfeature->get_all_TranscriptVariations))
			# foreach my $transcriptan (@transcripts) {
			# 	$variants_collection->update(
			# 		{ _id         => MongoDB::OID->new( value => $mongoid ), "c" => $chr },
			# 		{ '$addToSet' => { 'tr'                   => $transcriptan } }, {multiple => 1},
			# 		{ safe        => 1 }
			# 	);
			# }
			for my $stableid (keys %gene){
				push (@genes,$gene{$stableid});
			}

			$annotation{tr} = \@transcripts;
			$annotation{gene} = \@genes;
			while ( my ( $argument, $value ) = each(%annotation) ) {
				$variants_collection->update(
					{ _id    => MongoDB::OID->new( value => $mongoid ), "c" => $chr },
					{ '$set' => { $argument              => $value } }, {multiple => 1} );
			}

		}
	} else {
		# no valid slice found, chr noame is invalid
		print "Chromosome $chr not known to database, skipping annotation.\n";
		$BitQC->log_message( message => "Chromosome $chr not known to database, skipping annotation." );

	}

}

unlink($UNKNOWNVCF) if ($REMOVE);

# TODO: rewrite polyphen bits if no polyphen score is found in the database
#my $polyphen_fasta;
#( my $fh, $polyphen_fasta ) = tempfile( DIR => $SCRATCHDIR );
#my $polyphen_variants;
#( my $fh2, $polyphen_variants ) = tempfile( DIR => $SCRATCHDIR );
#
#my $protein_fasta =
#  Bio::SeqIO->new( -file => "> $polyphen_fasta", -format => 'fasta' );
#
#open( POLYPHEN, "> $polyphen_variants" );
#
##Loop over the variant list
#foreach my $var (@variants) {
#
#	#Get general information about the variant
#	my $organism = $var->{organism};
#	my $chr      = $var->{chr};
#	my $pos      = $var->{start};
#	my $variant  = $var->{variant};
#
#	my @annotations;
#
#	#Check if transcript was found
#	if ( $consequences{$organism}{$chr}{$pos}{$variant} ) {
#
#		#Loop over all the transcripts of the variant
#		foreach
#		  my $annotation ( @{ $consequences{$organism}{$chr}{$pos}{$variant} } )
#		{
#
#			#Save annotation information
#			my %annotations;
#			$annotations{en} = $annotation->{snpdb}
#			  if ( $annotation->{snpdb} );
#			$annotations{rb} = $annotation->{ref_base}
#			  if ( $annotation->{ref_base} );
#			$annotations{eg} = $annotation->{gene}
#			  if ( $annotation->{gene} );
#			$annotations{egi} = $annotation->{gene_id}
#			  if ( $annotation->{gene_id} );
#			$annotations{et} = $annotation->{transcript_id}
#			  if ( $annotation->{transcript_id} );
#			$annotations{pos} += $pos;
#			$annotations{var} = $variant;
#			$annotations{seq} = $annotation->{transcript_seq}
#			  if ( $annotation->{transcript_seq} );
#			$annotations{ets} = $annotation->{transcript_strand}
#			  if ( $annotation->{transcript_strand} );
#			$annotations{ecp} += $annotation->{cdna_pos}
#			  if ( $annotation->{cdna_pos} );
#
#			#?
#			$annotations{epp} += $annotation->{prot_pos}
#			  if ( $annotation->{prot_pos} );
#			if ( $annotation->{prot_seq} ) {
#				$annotation->{prot_seq}
#				  ->display_id( $annotation->{transcript_id} );
#				$protein_fasta->write_seq( $annotation->{prot_seq} );
#			}
#
#			if ( $annotation->{mut_prot_seq} ) {
#				$annotation->{pep_string} =~ /([A-Z]+)>([A-Z]+)/;
#				print POLYPHEN $variant_ids{$pos}{$variant}->value,
#				  "\t", $annotation->{transcript_id}, "\t",
#				  $annotation->{prot_pos}, "\t", $1, "\t", $2, "\n";
#			}
#
#			$annotations{eps} = $annotation->{pep_string}
#			  if ( $annotation->{pep_string} );
#			$annotations{ec} = $annotation->{consequence}
#			  if ( $annotation->{consequence} );
#			push( @annotations, \%annotations );
#
#		}
#	}
#	else {
#		my %annotations;
#
#		#		$annotations{ev} = $version{'variation'}{'name'}
#		#		  if ( $version{'variation'}{'name'} );
#		push( @annotations, \%annotations );
#	}
#
#	$DATABASE_ADAPTOR->updateConfigurationEntry(
#		$VARIANTS_COLL,
#		$variant_ids{$pos}{$variant},
#		{ 'a' => \@annotations }
#	);
#
#}
#
#close(POLYPHEN);
#
#my $polyphen_output;
#( my $fh3, $polyphen_output ) = tempfile( DIR => $SCRATCHDIR );
#
#my $polyphen_err;
#( my $fh4, $polyphen_err ) = tempfile( DIR => $SCRATCHDIR );
#
#`run_pph.pl -b /store/polyphen/nrdb/uniref100 -d $SCRATCHDIR -s $polyphen_fasta $polyphen_variants 1>$polyphen_output 2>$polyphen_err`;
#
#my @pph = `run_weka.pl $polyphen_output`;
#
#my %polyphen;
#my @pph_keys;
#
#my $i = 0;
#for (@pph) {
#	if ( $i == 0 ) {
#
#		#skip first line
#		#@pph_keys = split( /\t/, $line );
#		$i++;
#	}
#	else {
#		chomp;
#		my $line = $_;
#		my @line = split( /\t/, $line );
#		s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/ for (@line);
#		$polyphen{ $line[0] }{ $line[1] }{pre} = $line[12] if $line[12];
#		$polyphen{ $line[0] }{ $line[1] }{pro} += $line[16] if $line[16];
#		$polyphen{ $line[0] }{ $line[1] }{fpr} += $line[17] if $line[17];
#		$polyphen{ $line[0] }{ $line[1] }{tpr} += $line[18] if $line[18];
#	}
#}
#
##Save annotation information/transcript into database
#for my $id ( keys %polyphen ) {
#	for my $trans ( keys %{ $polyphen{$id} } ) {
#		$DATABASE_ADAPTOR->insertEntry(
#			collection => $VARIANTS_COLL,
#			fields     => {
#				'a.$.pph' => \%{ $polyphen{$id}{$trans} },
#				'a.et'    => $trans
#			},
#			save_mode => 1
#		);
#	}
#}
#
#unlink( $polyphen_err, $polyphen_fasta, $polyphen_output, $polyphen_variants );

######################################################################################
# FINISH SCRIPT
######################################################################################

# finish logging
$BitQC->finish_log(
	message => "End job: annotation of variants in $UNKNOWNVCF done." );


