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
		'annotationfile'	=> { type => 'string' },
		'annotationcollection'	=> { type => 'string', default => "variants_unique" },
		'annotation'   	=> { default => boolean::false, type => 'bool' }
	}
);

######################################################################################
# COMMANDS AND VARIABLES
######################################################################################

my $ANNOTATIONFILE	= $BitQC->getRunConfig('annotationfile');
my $ANNOTATION = $BitQC->getRunConfig('annotation');
my $VARIANTUNIQUESCOLL = $BitQC->getRunConfig('annotationcollection');

my $mongodb             = $BitQC->{DatabaseAdapter}->createDatabaseConnection();
my $variants_unique_collection = $mongodb->get_collection($VARIANTUNIQUESCOLL);

if ($ANNOTATION) {
	# read the annotation file

	open(ANN,$ANNOTATIONFILE) || die "Could not open the annotation file";
	my @line;
	my %annotation;

	while(<ANN>){
    	@line = split(/\t/,$_);
    	$annotation{$line[0]}{"name"} = $line[1];
    	$annotation{$line[0]}{"type"} = $line[2];
    	$annotation{$line[0]}{"description"} = $line[3];
    	$annotation{$line[0]}{"values"} = $line[4] if $line[4];
	}

	my $all_annotations = $variants_unique_collection->find;

	my $updates = 0;
	my $popfrequpdate = 0;
	my $genetranscriptxrefupdate = 0;

	DOC: while (my $doc = $all_annotations->next) {
		if (exists($annotation{$doc->{"_id"}})) {
			# record is specified in annotation input file
			$updates++;
			# update the name
			$variants_unique_collection->update_one({"_id" => $doc->{"_id"}}, { '$set' => {'name' => $annotation{$doc->{"_id"}}{'name'}}}) if (exists($annotation{$doc->{"_id"}}{'name'}) && $annotation{$doc->{"_id"}}{'name'} ne '');
			# update the description
			$variants_unique_collection->update_one({"_id" => $doc->{"_id"}}, { '$set' => {'description' => $annotation{$doc->{"_id"}}{'description'}}}) if (exists($annotation{$doc->{"_id"}}{'description'}) && $annotation{$doc->{"_id"}}{'description'} ne '');
			# update the record
		} elsif (exists($doc->{"description"})) {
			next DOC;
		} elsif ($doc->{"_id"} =~ m/^popfreq\./) {
			my $name = "";
			my $description = "Allele frequency for population ";
			if ($doc->{"_id"} =~ m/^popfreq\.(.+):(.+)$/) {
				$description .=$1.", subpopulation ".$2;
				$name .= $1." ".$2;
			} else {
				$doc->{"_id"} =~ m/^popfreq\.(.+)/;
				$description .= $1;
				$name .= $1;
			}
			$name .= " population frequency";
			#print "Updating ".$doc->{"_id"}." with name ".$name." and description ".$description."\n";

			# update the record
			$variants_unique_collection->update_one({"_id" => $doc->{"_id"}}, { '$set' => {'name' => $name, 'description' => $description}});
			$popfrequpdate++;

		} elsif ($doc->{"_id"} =~ m/^(gene|tr)\.xrefs\.(.+)\.(.+)$/) {
			my $name = "";
			my $description = "";
			my $object = $1;
			if ($3 eq "display_id") {
				$name = $2." name";
				$object = "Transcript" if ($1 eq 'tr');
				$description .= $object." name in ".$2." database";
			} else {
				$name = $2." ".$3;
				$description .= $2." database ".$3;
			}
			# update the record
			$variants_unique_collection->update_one({"_id" => $doc->{"_id"}}, { '$set' => {'name' => $name, 'description' => $description}});
			$genetranscriptxrefupdate++;

		} else {
			print "New record:\t".$doc->{'_id'}."\t".$doc->{'name'}."\t".$doc->{'type'}."\n";
		}
	    
	}

	print $updates." records updated\n";
	print $popfrequpdate." popfreq records updated\n";
	print $genetranscriptxrefupdate." external gene or transcript reference records updated\n";
	#my $result = $variants_collection->find_one( \%query, { '_id' => 1 } );
}


