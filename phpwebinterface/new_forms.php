<?php
session_start();
require_once('jformer.php');
include_once 'functions.php';
$credentials = read_credentials($_SESSION['config']);
$db = connect_mongo();
$collections = get_collections($db);

////////////////////////////////////////////////////
// build the form depending on the type requested
////////////////////////////////////////////////////

$form = new JFormer(
    'form',
    array(
        'submitButtonText' => 'Set filter',
        'action' => 'new_forms.php',
        'onSubmitFunctionServerSide' => 'onnew_adv_filterSubmit',
        'title' => '<h4>Advanced filter</h4>'
    )
);
////////////////////////////////////////
// build the advanced filtering form
////////////////////////////////////////

///////////////////////////
// static variables
///////////////////////////
$options = array(
    array(
        'value'=>'het',
        'label'=>'Heterozygous'),
    array(
        'value' => 'hom',
        'label' => 'Homozygous variant'),
    array(
        'value' => '-',
        'label' => 'Homozygous reference')
);

$all_columns = $collections['variants_unique']->find(array());

$columns = array(
    'sa' => array(
        array(
            'value' => '',
            'label' => ''
        )
    ),
    'pop' => array(
        array(
            'value' => '',
            'label' => ''
        )
    ),
    'gene_tr' => array(
        array(
            'value' => '',
            'label' => ''
        )
    ),
    'other' => array(
        array(
            'value' => '',
            'label' => ''
        )
    )
);

$all_columns->sort(array('name'=>1));
foreach ($all_columns as $key => $column) {
	if ($column['querykeys'][0] == 'sa') {
		array_push($columns['sa'], 
            array(
                'value'=>str_replace("\"", "'",json_encode($column['querykeys'])),
                'label'=>$column['name']
            )
        );
	}
    if ($column['querykeys'][0] == 'popfreq') {
        array_push($columns['pop'], 
            array(
                'value'=>str_replace("\"", "'",json_encode($column['querykeys'])),
                'label'=>$column['name']
            )
        );
    }
	elseif ($column['querykeys'][0] == 'gene' || $column['querykeys'][0] == 'tr') {
        array_push($columns['gene_tr'], 
            array(
                'value'=>str_replace("\"", "'",json_encode($column['querykeys'])),
                'label'=>$column['name']
            )
        );
	}
	else {
        array_push($columns['other'], 
            array(
                'value'=>str_replace("\"", "'",json_encode($column['querykeys'])),
                'label'=>$column['name']
            )
        );
	}

}
// Create form structure
$general_samples_section = new JFormSection(
    'general_samples'
);
$population_section = new JFormSection(
    'population'
);
$gene_transcript_section = new JFormSection(
    'gene_transcript'
);
$other_section = new JFormSection(
    'other'
);
$form->addJFormComponentArray(
    array(
        new JFormComponentHtml(
                '   <ul>
                        <li><a href="#general_samples">Samples</a></li>
                        <li><a href="#population">Population</a></li>
                        <li><a href="#gene_transcript">Transcripts & genes</a></li>
                        <li><a href="#other">Other</a></li>
                    </ul>'
        )
    )
);
$form->addJFormSection($general_samples_section);
$form->addJFormSection($population_section);
$form->addJFormSection($gene_transcript_section);
$form->addJFormSection($other_section);
$loadedfilters = array();




// $adv_filter = $collections['adv_filter']->findOne(array('md5'=>'ae51f6171182267c372a5ddf1db0f9cd'));
// $filter = $adv_filter['filter'];
$filter = '';
// // Fill form
$i = 0;

$filter_id = isset($_POST['filter_id']) ? $_POST['filter_id']  : '';
$db_filter = array();
// curl get naar backend als filter ingeladen dus als id als attr aan knopt hangt
if(!empty($filter_id)){
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_PROXY, null);
	// curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['mongoquery'].'/filter/'.$filter_id);
	curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['mongoquery'].'/filter/'.$filter_id);
	//curl_setopt($ch, CURLOPT_URL, 'http://localhost:3939/filter/52974b7f7412df2165050000');
	$resp = curl_exec($ch);
	$response = json_decode($resp);
	$db_filter = $response->filter;
}
// 


// formValues als return --> adhv deze array form opbouwen
$projects_id = isset($_POST['projects_id']) ? json_decode(str_replace("'", "\"",$_POST['projects_id']))  : array();
$samples_ids = isset($_POST['samples_id']) ? json_decode(str_replace("'", "\"",$_POST['samples_id']))  : array();


if ($db_filter->general_samples){
    foreach ($db_filter->general_samples as $key => $value) {
        preg_match('/filter_(\w+)_sa_(\d+)/',$key,$matches);
        if ($matches[0]) {
            $general_samples[$matches[2]][$matches[1]] = $value;
        }
    }
}
$general_samples_filter = __createfilter($general_samples,'sa',$i,iterator_to_array($all_columns),$columns['sa']);
$general_samples_section->addJFormComponentArray(
    array(
        new JFormComponentHtml(
            "<div style='clear:both;'><img class='form_folder open' src='img/icon_tree_off.gif'>General<div id='form_folder'>"
        )
));
if (is_array($samples_ids)) {
$general_samples_section->addJFormComponentArray(
    array(
        new JFormComponentHidden(
            'all_samples_ids', implode(',',$samples_ids)
        )
    )
);
}
$general_samples_section->addJFormComponentArray(
    $general_samples_filter
);
$general_samples_section->addJFormComponentArray(
    array(
        new JFormComponentHtml(
            "</div></div><div style='clear:both;'><img class='form_folder' src='img/icon_tree_off.gif'>Per sample<div id='form_folder'>"
        )
    )
);

$samples = array(
    array(
        'label'=>'',
        'value'=>''
    )
);
if ($samples_ids != '') {
   foreach ($samples_ids as $sample_id) {
        $sample = $collections['samples']->findOne(array('_id'=>new MongoId($sample_id)));
        array_push(
            $samples,
            array(
                'label'=>$sample['name'],
                'value'=>$sample['_id'].''
            )
        );
    }
}
$j = 0;
if ($db_filter->general_samples){
    foreach ($db_filter->general_samples as $key => $value) {
        preg_match('/genotype_sa'.$j.'_(\d+)/',$key,$matches);
        if ($matches[0]) {
            $per_sample[$matches[1]]['genotype_sa'.$j] = $value;
        }
        preg_match('/filter_(\w+)_sa'.$j.'_(\d+)/',$key,$matches);
        if ($matches[0]) {
            $per_sample[$matches[2]][$j][$matches[1]] = $value;
        }      
    }
}
$per_sample_options = $options;
foreach ($per_sample_options as $key => $value) {
    if ($value['value'] == $per_sample[1]['genotype_sa0']) {
        $per_sample_options[$key]['checked'] = true;
    }
}
$per_sample_filter = __createfilter($per_sample,'sa'.$j,2,iterator_to_array($all_columns),$columns['sa']);
$general_samples_section->addJFormComponentArray( 
    array(
        new JFormComponentHtml(
            "<div class='per_sample_folder'>"
        ),
        new JFormComponentDropDown(
            'genotype_sa'.$j.'_0',
            'Select genotype for sample',
            $samples,
            array(
                'width' => 'long',
                'initialValue'=>$per_sample[0]['genotype_sa0']
            )
        ),
        new JFormComponentMultipleChoice('genotype_sa'.$j.'_1', '', 
            $per_sample_options,
            array(
                'multipleChoiceType'=>'radio',
                'style'=>'clear: none',
            )
        )
    )
);
$general_samples_section->addJFormComponentArray(
    $per_sample_filter
);
$general_samples_section->addJFormComponentArray( 
    array(
        new JFormComponentHtml(
            "<div class='clearer'></div></div>"
        )
    )
);
$j++;
while ($j <= 5) {   
    if ($db_filter->general_samples){
        foreach ($db_filter->general_samples as $key => $value) {
            preg_match('/genotype_sa'.$j.'_(\d+)/',$key,$matches);
            if ($matches[0]) {
                $per_sample[$matches[1]]['genotype_sa'.$j] = $value;
            }
            preg_match('/filter_(\w+)_sa'.$j.'_(\d+)/',$key,$matches);
            if ($matches[0]) {
                $per_sample[$matches[2]][$j][$matches[1]] = $value;
            }      
        }
    }
    $per_sample_options = $options;
    foreach ($per_sample_options as $key => $value) {
        if ($value['value'] == $per_sample[1]['genotype_sa'.$j]) {
            $per_sample_options[$key]['checked'] = true;
        }
    }
    $per_sample_filter = __createfilter($per_sample,'sa'.$j,2,iterator_to_array($all_columns),$columns['sa']);
    $style = '';
    if ($per_sample[0]['genotype_sa'.$j] == ''){
        $style = 'display:none;';
    }
    $general_samples_section->addJFormComponentArray( 
        array(
            new JFormComponentHtml(
                "<div class='per_sample_folder' style='".$style."'>"
            ),
            new JFormComponentDropDown(
                'genotype_sa'.$j.'_0',
                'Select genotype for sample',
                $samples,
                array(
                    'width' => 'long',
                    'initialValue'=>$per_sample[0]['genotype_sa'.$j]
                )
            ),
            new JFormComponentMultipleChoice('genotype_sa'.$j.'_1', '', 
                $per_sample_options,
                array(
                    'multipleChoiceType'=>'radio',
                    'style'=>'clear: none'
                )
            )
        )
    );
    $general_samples_section->addJFormComponentArray(
        $per_sample_filter
    );
    $general_samples_section->addJFormComponentArray( 
        array(
            new JFormComponentHtml(
                "<button class='remove_genotype_filter' style='float:right'>Remove genotype filter</button><div class='clearer'></div></div>"
            )
        )
    );
    $j++;
}
$general_samples_section->addJFormComponentArray(
    array(
        new JFormComponentHtml(
            "<button class='add_genotype_filter' style='float:right' counter='1'>Add genotype filter</button></div></div>"
        )
    )
);
if ($db_filter->population){
    foreach ($db_filter->population as $key => $value) {
        preg_match('/filter_(\w+)_popfreq_(\d+)/',$key,$matches);
        $population[$matches[2]][$matches[1]] = $value;
    }
}
$population_filter = __oldcreatefilter($population,'popfreq',$i,iterator_to_array($all_columns),$columns['pop']);
$population_section->addJFormComponentArray(
    $population_filter
);
if ($db_filter->gene_transcript){
    foreach ($db_filter->gene_transcript as $key => $value) {
        preg_match('/filter_(\w+)_genetr_(\d+)/',$key,$matches);
        $gene_transcript[$matches[2]][$matches[1]] = $value;
    }
}
$gene_transcript_filter = __oldcreatefilter($gene_transcript,'genetr',$i,iterator_to_array($all_columns),$columns['gene_tr']);
$gene_transcript_section->addJFormComponentArray(
    $gene_transcript_filter
);
if ($db_filter->other){
    foreach ($db_filter->other as $key => $value) {
        preg_match('/filter_(\w+)_other_(\d+)/',$key,$matches);
        $other[$matches[2]][$matches[1]] = $value;
    }
}
$other_filter = __createfilter($other,'other',$i,iterator_to_array($all_columns),$columns['other']);
$other_section->addJFormComponentArray(
    $other_filter
);
$other_section->addJFormComponentArray(
    array(
        new JFormComponentHtml(
            '<script>
            $("select[id^=\'filter_column\']").chosen({width:"143px;",placeholder_text_single:"Select a column...","search_contains":true});
            $("select[id^=\'filter_operator\']").chosen({width:"143px;",placeholder_text_single:"Select an operator..."});
            $("select[id^=\'genotype_sa\']").chosen({width:"143px;",placeholder_text_single:"Select a sample...","search_contains":true});
            $(".jFormWrapperContainer").css("overflow","visible");
            $(".jFormPageWrapper").css("overflow","visible");
            $(".jFormSection").css("overflow","visible");
            $(".add_genotype_filter, .add_filter_line").button({icons: {primary: "ui-icon-circle-plus"}});
            $(".remove_genotype_filter, .remove_filter_line").button({icons: {primary: "ui-icon-circle-minus"}});
            </script>'
        ),
        new JFormComponentHtml('
            <script> $(function() {
            $( "#form_page1" ).tabs();
            });</script>'
        )
    )
);
$form->addJFormComponentArray(
    array(
        new JFormComponentHidden(
            'save_filter',
            ''
        ),
        new JFormComponentHidden(
            'projects_id',
            str_replace("\"", "'", json_encode($projects_id))
        ),
        new JFormComponentHidden(
            'filter_id', $response->_id.''
        )
    )
);

// process the request
$form->processRequest();

function onnew_adv_filterSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $db = connect_mongo();
    $collections = get_collections($db);
    // Collect values
    $sampleValues = $formValues->general_samples;
    $populationValues = $formValues->population;
    $gene_transValues = $formValues->gene_transcript;
    $otherValues = $formValues->other;
	
	$allSampleIds = array_unique(explode(',',$sampleValues->all_samples_ids));
    // Set overal filter
    $all_filters = array();
    // Create sample filter
    $general_samples_filter = __extract_colopval($sampleValues,'sa','no');
    $per_sample_filter = __extract_colopval($sampleValues,'sa','yes');
    //$general_json = __filtertojson($general_samples_filter);
    $tmp_sample_json=array();
    foreach ($per_sample_filter as $key => $value) {
        $per_sample_json = __filtertojson($value);
        if ($per_sample_json['sa']) {
           $tmp_sample_json['sampleList'][] = $per_sample_json['sa'];
        }   
    }
    $tmp_general_samples_json= __filtertojson($general_samples_filter);
	$general_samples_json = array();
	if (isset($tmp_general_samples_json['sa'])){ $general_samples_json = $tmp_general_samples_json['sa']; }
	$leftoverSampleId=$allSampleIds;
	foreach ($tmp_sample_json['sampleList'] as $indexKey => $subSampleFilter) {
		if( isset($subSampleFilter['id']['$in']) && count(array_intersect($subSampleFilter['id']['$in'],$allSampleIds)) > 0 ){
			$tmp_sample_json['sampleList'][$indexKey]=array_merge_recursive($subSampleFilter,$general_samples_json);
			if(count($leftoverSampleId) > 0 ){
				$leftoverSampleId=array_values(array_diff($leftoverSampleId,$subSampleFilter['id']['$in']));
			}
		}elseif(isset($subSampleFilter['id']['$nin']) && count(array_intersect($subSampleFilter['id']['$nin'],$allSampleIds)) > 0 ){
			//no need to apply extra filters to negative selection
			if(count($leftoverSampleId) > 0 ){
				$leftoverSampleId=array_values(array_diff($leftoverSampleId,$subSampleFilter['id']['$nin']));
			}
		}
	}
	if(count($leftoverSampleId) < count($allSampleIds) ){
		if( count($leftoverSampleId) > 0 ){
			$tmpNewSampleFilter=$general_samples_json;
			$tmpNewSampleFilter['id']=array( '$in' => $leftoverSampleId );
			$tmp_sample_json['sampleList'][] = $tmpNewSampleFilter;
		}
	}else{
		$tmp_sample_json['sa']=array('id' => array( '$in' => $allSampleIds ));
	}
    //if (count($general_json) > 0 || count($tmp_sample_json) > 0){
    $all_filters=$tmp_sample_json;
    //}

    // Create population filter
    $population_filter = __extract_colopval($populationValues,'popfreq','no');
    $population_json = __filtertojson($population_filter);
    // add to overal filter
    $all_filters = array_merge_recursive($all_filters,$population_json);
    // Create gene_transcript filter and add to overal filter
    $gene_transcript_filter = __extract_colopval($gene_transValues,'genetr','no');
    $gene_transcript_json = __filtertojson($gene_transcript_filter);
    $all_filters = array_merge_recursive($all_filters,$gene_transcript_json);
    // Create other filter and add to overal filter
    $other_filter = __extract_colopval($otherValues,'other','no');
    $other_json = __filtertojson($other_filter);
    $all_filters = array_merge_recursive($all_filters,$other_json);

    # create a unique md5 hash of this filter
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    # get the total number of records matching the query
    # generate an md5 hash of the query
    
    $data = array(
            'where'=> $all_filters,
            'projects' => json_decode(str_replace("'", "\"", $formValues->projects_id)),
            'filter'=>$formValues,
        );
    if ($formValues->save_filter != '') {
        $data['name']=$formValues->save_filter;
    }
    // TODO: check if conversion to MongoId is needed or not
    if (!empty($formValues->filter_id)) {
         $data['_id']=$formValues->filter_id;
    }
    $data = json_encode($data);
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
    curl_setopt($ch, CURLOPT_PROXY, null);
    curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['mongoquery'].'/filter');
    // curl_setopt($ch, CURLOPT_URL,
    // $_SESSION['credentials']['site']['mongoquery'].'/filter/'.$sampleValues->filter_id);
    //curl_setopt($ch, CURLOPT_URL, 'http://localhost:3939/filter');
    $resp = curl_exec($ch);
    $response = json_decode($resp);
    $db_id = $response->_id;

    if (isset($sampleid) || isset($all_filters)){
        $response = array('successJs' => "newAdvancedFilter ( '".$response->name."', '$db_id', '".json_encode($all_filters)."' );");
    } 
    else {
        $response = array('failureNoticeHtml' => '<p>No filter set</p>','failureJs'=> "console.log('".$response->name."')");
    }
    return $response;
}

function __extract_colopval($values,$prefix,$special){
    $filter = array();
    foreach ($values as $key => $row) {
        // collect the name of the column, i.e. 'column', 'operator' or 'value'
        $temp_key = substr($key,7);
        if ($special == 'no'){
            if (preg_match('/([a-z]+)_('.$prefix.')_([0-9]+)$/', $temp_key,$matches)){
                if (!isset($filter[$matches[3]])) {
                    $filter[$matches[3]] = array();
                }
                if (!isset($filter[$matches[3]][$matches[1]])) {
                    $filter[$matches[3]][$matches[1]] = array();
                }
                $filter[$matches[3]][$matches[1]] = $row;
            }
        }
        elseif ($special == 'yes') {
            if (preg_match('/([a-z]+)_('.$prefix.')([0-9]+)_([0-9]+)$/', $temp_key,$matches)) {
                if ($matches[1] != 'e'){
                   if (!isset($filter[$matches[3]])) {
                        $filter[$matches[3]] = array();
                    }
                    if (!isset($filter[$matches[3]][$matches[4]])) {
                        $filter[$matches[3]][$matches[4]] = array();
                    }
                    if (!isset($filter[$matches[3]][$matches[4]][$matches[1]])) {
                        $filter[$matches[3]][$matches[4]][$matches[1]] = array();
                    }
                    $filter[$matches[3]][$matches[4]][$matches[1]] = $row;
                }
                else {
                    if ($matches[4] == 0) {
                       $filter[$matches[3]][$matches[4]]['column'] =  str_replace( "\"", "'", json_encode(array('sa','id'))); 
                    }
                    elseif ($matches[4] == 1) {
                        $filter[$matches[3]][$matches[4]]['column'] = str_replace( "\"", "'", json_encode(array('sa','GT'))); 
                    }
					
                    $filter[$matches[3]][$matches[4]]['operator'] = '$in';
                    $filter[$matches[3]][$matches[4]]['value'] = $row;
                    if ($row == ''){
                        $filter[$matches[3]][$matches[4]]['column'] = '';
                    }
                    if ($row == '-'){ //variant can't be present if Homozygous reference was selected
                        $filter[$matches[3]][$matches[4]]['column'] = '';
                        $filter[$matches[3]][0]['operator'] = '$nin';
                    }                      
                }
            }
        }  
    }
    return $filter;
}

function __filtertojson($filter){
    $credentials = read_credentials($_SESSION['config']);
    $db = connect_mongo();
    $collections = get_collections($db);
    $searchtypes = array();
    $all_columns = $collections['variants_unique']->find(array());
    foreach ($all_columns as $column){
        if (isset($column['type'])){
            // key is in json format with " replaced by '
           $searchtypes[str_replace( "\"", "'", json_encode($column['querykeys']))] = $column['type'];
        }
    }

    $json_filter = array();
    foreach ($filter as $key => $row) {
        if ($row['column'] !== '' && $row['operator'] ) {
            $temp2 = array();
            if ($row['value'] == '') {
                if( $row['operator'] == '$notexists' ){
                    $row['operator'] = '$exists';
                    $value = FALSE; # set value to false
                } 
                elseif ( $row['operator'] == '$exists'){
                    $value = TRUE;
                }
                $temp2[$row['operator']] = $value;
            }
            else {
                 # make numerical queries valid
                if ($searchtypes[$row['column']] == 'numerical' ){
                    $value = (float) $row['value']; # force value to be numeric
                } else {
                    $value = $row['value'];
                }
                if ($row['operator'] == '$in' || $row['operator'] == '$nin') {
                   $temp2[$row['operator']] = array();
                    if (gettype($value) == 'array'){
                        $temp2[$row['operator']] = $value;
                    }
                    else {
                        if (strpos($value, ',')){
                            $temp2[$row['operator']] = explode(",", $value);
                        }
                        else {
                            array_push($temp2[$row['operator']], $value );
                        }
                    }
                }
                else {
                     $temp2[$row['operator']] = $value;
                }
            }
            if ($row['column'] !== ''){
                $reverse = array_reverse(json_decode(str_replace("'", "\"",$row['column'])));
                foreach ($reverse as $key => $value) {
                    $temp = array();
                    $temp[$value] = $temp2;
                    $temp2 = $temp;
                }
            }
            
            $json_filter = array_merge_recursive($json_filter,$temp);
        }
    }
    return $json_filter;
}

function __oldcreatefilter($filter,$prefix,$i,$all_columns,$columns){
    // check if filter exists
    $loadedfilters = array();
    if ($filter) {
        foreach ($all_columns as $key => $column) {
            if (!isset($column['querykeys'])){
                continue(1);
            }
            $remaining = $filter;
            foreach ($column['querykeys'] as $query_key => $query_value) {
                if (isset($remaining[$query_value])) {
                    $remaining = $remaining[$query_value];
                }
                else {
                    continue(2); // goto the next $columns
                }
            }
            // we found a filter matching this column
            if (isset($column['type'])) {
                foreach ($remaining as $operator => $query) {
                    $newline = array();
                    if (($operator == '$in' || $operator == '$nin' || $operator == '$all') && $column['type'] != 'list') {
                        $value_string = implode(",", $query);
                        $newline = __createfilterline($prefix,$i,$columns,$column,$operator,$value_string,'');
                        array_splice($loadedfilters, count($loadedfilters), 0, $newline);
                        $i++;
                    } else {
                        $newline = __createfilterline($prefix,$i,$columns,$column,$operator,$query,'');
                        array_splice($loadedfilters, count($loadedfilters), 0, $newline);
                        $i++;
                    }
                }
            }
        }
    }
    
    $newline = __createfilterline($prefix,$i,$columns,'','','','');
    array_splice($loadedfilters, count($loadedfilters), 0, $newline);
    $i++;
    $add_button = array(
        new JFormComponentHtml(
            '<button counter="'.$i.'" prefix="'.$prefix.'" class="add_filter_line" style="clear:none;">Add Filter</button>'
        )
    );
    while($i<=5){
        $newline = __createfilterline($prefix,$i,$columns,'','','','display: none;');
        array_splice($loadedfilters, count($loadedfilters), 0, $newline);
        $i++;
    }
    array_splice($loadedfilters, count($loadedfilters), 0, $add_button);
    return $loadedfilters;
}
function rep_count($matches) {
    $count = $matches[2]+1;
    return $matches[1].$count;
}

function __createfilter($filter, $prefix, $i, $all_columns, $columns){
    // check if filter exists
    $loadedfilters = array();
    if ($filter) {
        ksort($filter);
        $j = 0;
        foreach ($filter as $key => $filterline) {
            $newline = array();
            if ($filterline['operator']){   
                $operator = $filterline['operator'];
                $value = $filterline['value'];
                if ($filterline['column'] && $value){
                    $filter_column = json_decode(str_replace("'", "\"",$filterline['column']));
                    $value_string = implode('.', $filter_column);
                    $newline = __createfilterline($prefix,$i,$columns,$all_columns[$value_string],$operator,$value,'');
                    array_splice($loadedfilters, count($loadedfilters), 0, $newline);
                    $i++;
                    $j++;    
                }
                else {
                    $newline = __createfilterline($prefix,$i,$columns,'',$operator,$value,'display: none;');
                    array_splice($loadedfilters, count($loadedfilters), 0, $newline);
                    $i++;
                }
            }
            else {
                $j=3;
                foreach ($filterline as $key => $val) {
                    if (gettype($val) == 'array') {
                        $operator = $val['operator'];
                        $value = $val['value'];
                        if ($val['column'] && $value){
                            $filter_column = json_decode(str_replace("'", "\"",$val['column']));
                            $value_string = implode('.', $filter_column);
                            $newline = __createfilterline($prefix,$i,$columns,$all_columns[$value_string],$operator,$value,'');
                            array_splice($loadedfilters, count($loadedfilters), 0, $newline);
                            $i++;
                            $j++;    
                        }
                        else {
                            $newline = __createfilterline($prefix,$i,$columns,'',$operator,$value,'display: none;');
                            array_splice($loadedfilters, count($loadedfilters), 0, $newline);
                            $i++;
                        }
                    }
                }
            }            
        }
        $add_button = array(
            new JFormComponentHtml(
                '<button counter="'.$j.'" prefix="'.$prefix.'" class="add_filter_line" >Add Filter</button>'
            )
        );
        array_splice($loadedfilters, count($loadedfilters), 0, $add_button); 
    }
    else {
        $newline = __createfilterline($prefix,$i,$columns,'','','','');
        array_splice($loadedfilters, count($loadedfilters), 0, $newline);
        $i++;
        $add_button = array(
            new JFormComponentHtml(
                '<button counter="'.$i.'" prefix="'.$prefix.'" class="add_filter_line" style="clear:none;">Add Filter</button>'
            )
        );
        while($i<=5){
            $newline = __createfilterline($prefix,$i,$columns,'','','','display: none;');
            array_splice($loadedfilters, count($loadedfilters), 0, $newline);
            $i++;
        }
        array_splice($loadedfilters, count($loadedfilters), 0, $add_button);  
    }
    
    return $loadedfilters;
}

function __createfilterline($prefix,$i,$columns,$column,$operator,$value,$display){
    // set some variables
    $operatorhash = array(
        'numerical' => array(
            array(
                'label'=>'equals',
                'value'=>'$in'),
            array(
                'label'=>'not equals',
                'value'=>'$nin'),
            array(
                'label'=>'greater than',
                'value'=>'$gt'),
            array(
                'label'=>'less than',
                'value'=>'$lt'),
            array(
                'label'=>'greater than or equals to',
                'value'=>'$gte'),
            array(
                'label'=>'less than or equals to',
                'value'=>'$lte'),
            array(
                'label'=>'exists',
                'value'=>'$exists'),
            array(
                'label'=>'does not exist',
                'value'=>'$notexists')
        ),
        'text' => array(
            array(
                'label'=>'equals',
                'value'=>'$in'),
            array(
                'label'=>'not equals',
                'value'=>'$nin'),
            array(
                'label'=>'exists',
                'value'=>'$exists'),
            array(
                'label'=>'does not exist',
                'value'=>'$notexists')
        ),
        'list' => array(
            array(
                'label'=>'equals',
                'value'=>'$in'),
            array(
                'label'=>'not equals',
                'value'=>'$nin'),
            array(
                'label'=>'exists',
                'value'=>'$exists'),
            array(
                'label'=>'does not exist',
                'value'=>'$notexists')
        )
    );

    // return variable
    $line = array();

    // check value exists --> set initial column
    // add the column dropdown to the form
    array_push($line, 
        new JFormComponentDropDown(
            'filter_column_'.$prefix.'_'.$i,
            '',
            $columns,
            array(
                'width' => 'long',
                'initialValue'=>str_replace(
                    "\"",
                    "'",
                    json_encode($column['querykeys'])
                ),
                'style'=>$display
            )
        )
    );

    $style = 'clear: none; ';
    if ($display == 'display: none;'){
        $style .= $display;
    }
    // add the operator and value fields
    if ($operator == '$exists'){
        $style .= ' display: none;';
        // add only the operator fields
        $initialvalue;
        if ($value){
            $initialvalue = '$exists';
        } else {
            $initialvalue = '$notexists';
        }
        $operator = $initialvalue;
    }

    // ad operator
    if ($column == '') {
        $type = 'numerical';
    }
    else {
        $type = $column['type'];
    }
    array_push($line, 
        new JFormComponentDropDown(
            'filter_operator_'.$prefix.'_'.$i,
            '', 
            $operatorhash[$type],
            array(
                'style'=>$style,
                'initialValue'=>$operator,
            )
        )
    );
    // add values
    if (is_array($value)){
        $values = array();
        foreach ($value as $val){
            array_push($values, array('value' => $val, 'label' => $val));
        }
        array_push(
            $line,
            new JFormComponentDropDown(
                'filter_value_'.$prefix.'_'.$i,
                '',
                $values,
                array(
                    'width' => 'long',
                    'style'=>$style,
                    'initialValue'=>$value,
                    'multiple'=>true
                )
            ),
            new JFormComponentHtml(
                '<script>
                    $("select[id^=\'filter_value\']").chosen({placeholder_text_multiple:"Select one or more values...",width:"143px;",search_contains:true});
                </script>'
            )
        );
    } else {
        array_push(
            $line, 
               new JFormComponentSingleLineText(
                'filter_value_'.$prefix.'_'.$i,
                '',
                array(
                    'style'=>$style,
                    'initialValue'=>$value,
                )
            )
        );
    }
    if ($i > 0){
        array_push(
            $line, 
            new JFormComponentHtml(
                '<button id="filter_remove_'.$prefix.'_'.$i.'" prefix="'.$prefix.'" counter="'.$i.'" class="remove_filter_line" style="'.$display.';clear:none;">Remove</button>'
            )
        );
    }
    
    return $line;
}
?>