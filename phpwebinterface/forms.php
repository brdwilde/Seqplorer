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

// variables
$buttons = array(
    'login'                 =>'Login',
    'igv'                   =>'Launch IGV',
    'shiny'                 =>'Show plot',
    'load_filter'           =>'Apply filter',
    'save_filter'           =>'Save filter',
    'load_view'             =>'Apply view', 
    'create_view'           =>'Apply view',
    'save_view'             =>'Save view',
    'manage_project'        =>'Update',
    'add_project'           =>'Add project',
    'manage_sample'         =>'Update',
    'add_sample'            =>'Add sample',
    'coverage'              =>'Calculate coverage',
    'rename'                =>'Edit sample info',
    'remove'                =>'Remove sample',
    'map_reads'             =>'Start mapping',
    'call_variants'         =>'Call variants',
    'jobs'                  =>'Run job',
    'register'              =>'Register',
    'user'                  =>'Update',
    'contact'               =>'Send',
    'join_group'            =>'Send request',
    'approve_group'         =>'Send reply',
    'unsubscribe_group'     =>'Leave group',
    'manage_group'          =>'Update',
    'new_group'             =>'Create group',
    'forgot'                =>'Request new password',
    'logs'                  =>'Show logs',
    'compare_variants'      =>'Compare variants',
    'export'                =>'Export',
    'create_plot'           =>'Create plot'
);

$job_scripts = array(
    'export'                => 'export',
    'create_plot'           => 'export',
    'rename'                => 'rename_remove_sample',
    'remove'                => 'rename_remove_sample',
    'manage_sample'         => 'rename_remove_sample',
    'map_reads'             => 'map_reads',
    'call_variants'         => 'call_variants',
    'coverage'              => 'bitqc_gene_coverage_generator',
    'compare_variants'      => 'bitqc_compare_variants'
);

// get type from post if set, else get from URL
$type = isset($_POST['type'])   ? $_POST['type']  : $_GET['type'];

// create the form element
$form = new JFormer(
    'form',
    array(
        'submitButtonText' => $buttons[$type],
        'action' => 'forms.php?type='.$type,
        'onSubmitFunctionServerSide' => 'on'.$type.'Submit'
    )
);
if ($type == 'logs'){
    $all_jobs_query = $collections['log']->find(
        array(
            'type'=>'job',
            'config.email_to'=> 'gbramdewilde@gmail.com',
            'masterprocess'=>array('$exists'=>false),
        )
    );
    $completed_dd = array();
    $running_dd = array();
    $error_dd = array();
    array_push($completed_dd,
        array (
            'value' => '',
            'label' => ' - Completed jobs - ',
            'disabled' => true,
            'selected' => true
        )
    );
    array_push($running_dd,
        array (
            'value' => '',
            'label' => ' - Running jobs - ',
            'disabled' => true,
            'selected' => true
        )
    );
    array_push($error_dd,
        array (
            'value' => '',
            'label' => ' - Jobs with error(s) - ',
            'disabled' => true,
            'selected' => true
        )
    );
    foreach ($all_jobs_query as $index => $job){
        if (isset($job['error'])){
            array_push($error_dd, array('value'=>$job['_id']."", 'label'=>$job['config']['config_id']));
        }
        else {
            $subjobs = $collections['log']->findOne(
                array(
                    'type'=>'job',
                    'masterprocess'=>$job['_id'],
                    'error'=>array('$exists'=>true)
                )
            );
            if (isset($subjobs)){
                array_push($error_dd, array('value'=>$job['_id']."", 'label'=>$job['config']['config_id']));
            }
            else {
                if (isset($job['end'])) {
                    $subjobs = $collections['log']->findOne(
                        array(
                            'type'=>'job',
                            'masterprocess'=>$job['_id'],
                            'end'=>array('$exists'=>false)
                        )
                    );
                    if (isset($subjobs)) {
                        array_push($running_dd, array('value'=>$job['_id']."", 'label'=>$job['config']['config_id']));
                    } 
                    else {
                        array_push($completed_dd, array('value'=>$job['_id']."", 'label'=>$job['config']['config_id']));
                    }       
                } 
                else {
                    array_push($running_dd, array('value'=>$job['_id']."", 'label'=>$job['config']['config_id']));
                }
            }               
        }
    }
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Show logs</h4>',
    ));
    $sectionComponents = array();
    if (count($completed_dd) > 1){
        array_push($sectionComponents, 
            new JFormComponentDropDown(
                'complete_job',
                '',
                $completed_dd,
                array(
                    'width' => 'long'
                )
            )
        ); 
    }
    else {
        array_push($sectionComponents, 
            new JFormComponentHtml(
                "<div>No completed jobs.</div>"
            )
        );
    }
    if (count($running_dd) > 1){
        array_push($sectionComponents,
            new JFormComponentDropDown(
                'running_job',
                '',
                $running_dd,
                array(
                    'width' => 'long'
                )
            )
        );
    }
    else {
        array_push($sectionComponents, 
            new JFormComponentHtml(
                "<div>No running jobs.</div>"
            )
        );
    }
    if (count($error_dd) > 1){
        array_push($sectionComponents, 
            new JFormComponentDropDown(
                'error_job',
                '',
                $error_dd,
                array(
                    'width' => 'long'
                )
            )
        );
    }
    else {
        array_push($sectionComponents, 
            new JFormComponentHtml(
                "<div>No jobs with errors.</div>"
            )
        );
    }
    $section->addJFormComponentArray(
        $sectionComponents
    );
}
elseif ($type == 'login') {
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Login</h4>',
    ));
    $section->addJFormComponentArray(
        array(
            // No public registrations at the moment
            // new JFormComponentHtml(
            //     "<div>Not a member? Please <a class='popup' keep_visible='1' action='register' href=''>register</a></div>"
            // ),
            new JFormComponentHtml(
                "<div><p>We're not allowing registrations at the moment.<br>Active members can login however.</p></div>"
            ),
            new JFormComponentSingleLineText(
                'email',
                'E-mail address:',
                array(
                    'width' => 'long',
                    'validationOptions' => array(
                        'required', 
                        'email'
                    ),
                    'tip' => '<p>Provide your login email adress</p>',
                )
            ),
            new JFormComponentSingleLineText(
                'password',
                'Password:', 
                array(
                    'width' => 'long',
                    'type' => 'password',
                    'validationOptions' => array(
                        'required',
                        'password'
                    ),
                    'enterSubmits' => true,
                    'tip' => '<p>Enter your password</p>',
                )
            ),
            new JFormComponentHtml(
                "<div><a class='popup' keep_visible='1' action='forgot' href=''>Forgot your password?</a></div>"
            ),
        )
    );  
}
elseif ($type == 'igv') {
    // Get sample ids
    $samples_ids     = isset($_POST['samples_id']) ? json_decode(str_replace("'", "\"",$_POST['samples_id']))  : array();
    // Initialize dropdown for selectable files
    $available_files = array(
        array(
            'value' => '',
            'label' => '',
            'disabled' => true,
        )
    );
    foreach ($samples_ids as $key => $sample_id) {
        // Get files per sample
        $files_array = $collections['samples']->findOne(array('_id'=>new MongoId($sample_id)));    
        foreach ($files_array['files'] as $key => $file) {
            if ($file['filetype'] == 'bam' || $file['filetype'] == 'vcf' || $file['filetype'] == 'wig' || $file['filetype'] == 'bed'){
                if ($file['type'] == 'local') {
                    // make dirname and create directory if not exists (dir per sample)
                    $dirname = "links/" . $sample_id;
                    if (!file_exists($file['name']) && !file_exists($dirname)) {
                        mkdir("links/" . "$sample_id", 0777);
                    }
                    // Create link to file
                    $extension = $file['filetype'];
                    if ($file['compression']) {
                        if ($file['compression'] == 'gzip'){
                            $extension .= '.gz';
                        } elseif ($file['compression'] == 'bzip') {
                            $extension .= '.bz2';
                        }
                    }
                    // create a display name for IGV (human readable)
                    if ($file['filetype'] == 'bam'){
                        $display_name =  substr($file['file'], strrpos($file['file'], '/', -3), -4);
                    }
                    else {
                        $display_name =  substr($file['file'], strrpos($file['file'], '/', -3), -7);
                    }
                    
                    $link = $dirname.$display_name."_".$key.".".$extension;

                    # create link for the index file for certain file types
                    $index = '';
                    $indexlink = '';
                    if ($file['filetype'] == 'bam') {
                        $index = substr($file['file'], 0, -3)."bai";
                        // $display_name =  substr($file[$key], strrpos($file[$key], '/', -3), -3);
                        $indexlink = $dirname.$display_name."_".$key.".bai";
                        // $indexlink = 'links/'.$samples_id."_".$key.".bai";
                    } elseif ($file['filetype'] == 'vcf') {
                        $index = $file['file'].".tbi";
                        $indexlink = $dirname.$display_name."_".$key.".vcf.gz.tbi";
                    }
                    // TODO: create link for BAI
                    if (!is_link($link)) {       
                        if (!symlink($file['file'], $link)){
                            echo "Could not create link to ".$file['file'].". Make sure the web werver user can read the local file!!";
                        }
                    }

                    if ($indexlink != '') {
                        if (!is_link($indexlink)){
                            if (!symlink($index, $indexlink)){
                                echo "Could not create link to ".$index.". Make sure the web werver user can read the local file!!";
                            }
                        }
                    }
                    array_push($available_files, array('value'=>$credentials->site->url.$link, 'label'=>$file['file']));
                } 
                elseif ($file['type'] == 'ftp' || $file['type'] == 'http') {
                    array_push($available_files, array('value'=>$file['file'], 'label'=>$file['file']));
                }
            }
        }
    }
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>IGV</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentDropDown(
            'files',
            '',
            $available_files,
            array(
                'width' => 'long',
                'multiple'=> true
            )
        ),
        new JFormComponentHtml(
            '<script>
            $("#files").chosen({placeholder_text_multiple:"Select one or more files..."});
            $(".jFormWrapperContainer").css("overflow","visible");
            $(".jFormPageWrapper").css("overflow","visible");
            $(".jFormSection").css("overflow","visible");
            </script>'
        )
    ));
}
elseif ($type == 'shiny') {
    // Get sample ids
    $samples_ids     = isset($_POST['samples_id']) ? json_decode(str_replace("'", "\"",$_POST['samples_id']))  : array();
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Shiny</h4>',
    ));
    // Initialize dropdown for selectable files
    $available_plots = array(
        array(
            'value' => '',
            'label' => '',
        )
    );
    if (!empty($samples_ids)){
        $plots_array = $collections['plots']->find(array('sampleids'=>array('$in'=>$samples_ids)),array('_id'=>1,'name'=>1,'sampleids'=>1));
        $all_plots = array();
        foreach ($plots_array as $plot) {
            $samples_ids = array_merge($samples_ids,$plot['sampleids']);
            $all_plots[] = $plot;

        }
        array_unique($samples_ids);
        foreach ($samples_ids as $sample_id) {
            $sample = $collections['samples']->findOne(array('_id'=>new MongoId($sample_id)),array('name'=>1));
            $all_samples[$sample_id] = $sample['name'];
        }
        foreach ($all_plots as $plot) {
            $label = '';
            foreach ($plot['sampleids'] as $plot_sample) {
                $label .= $all_samples[$plot_sample]." - ";
            }
            array_push($available_plots, array('value'=>$plot['_id'], 'label'=>$label.$plot['name']));
        }
    }
     

    if (count($available_plots) >= 1){
        $section->addJFormComponentArray(array(
            new JFormComponentDropDown(
                'plot',
                '',
                $available_plots,
                array(
                    'width' => 'long',
                )
            ),
            new JFormComponentHtml(
                '<script>
                $("#plot").chosen({placeholder_text_single:"Select a plot..."});
                $(".jFormWrapperContainer").css("overflow","visible");
                $(".jFormPageWrapper").css("overflow","visible");
                $(".jFormSection").css("overflow","visible");
                </script>'
            )
        )); 
    }
    else {
        $section->addJFormComponentArray(array(
            new JFormComponentHtml('There are no plots attached to this sample.<b>Select another sample to view plots.'),
        )); 
    }
    
}
elseif ($type == 'load_filter') {   
    $projects_id = isset($_POST['projects_id']) ? $_POST['projects_id'] : '';
    $filter_id = isset($_POST['filter_id']) ? $_POST['filter_id']  : '';

    $dbfilters = array(
        array (
            'value' => '',
            'label' => ' - Load filter - ',
            'disabled' => true,
            'selected'=>true
        )
    );
    if ($projects_id){
        // get the filters stored in the database
        $ids = array();
        foreach ($projects_id as $key=>$value){
            $ids['$in'][$key] = $value;
        }
        $filters = $collections['adv_filter']->find(array('projects'=>$ids));
        // build the list
        foreach($filters as $key =>$filter){
            array_push($dbfilters,
                array(
                    'value'=>$filter['_id'].'',
                    'label'=>$filter['name']
                )
            );
        }
    }

    ///////////////////////////
    // Build the form itself
    ///////////////////////////
    $section = new JFormSection(
        $form->id.'loadFilter',
        array(
            'title' => '<h4>Load Filter</h4>',
        )
    );
    $section->addJFormComponentArray(
        array(
            // the database filters dropdown
            new JFormComponentDropDown(
                'load_filter',
                '',
                $dbfilters,
                array(
                    'width' => 'long',
                    'initialValue'=>$filter_id,
                    'style' => 'clear:none'
                )
            ),
            new JFormComponentHidden(
                'filter_name',
                '',
                array(
                    'dependencyOptions' => array(
                            'dependentOn' => 'load_filter',
                            'display' => 'hide',
                            'jsFunction' => '$("#filter_name").val($("#load_filter option:selected").text());',
                    )
                )
            ),
            new JFormComponentHtml(
                '<script>
                    $("#load_filter").chosen({width:"143px;",placeholder_text_single:"Select a filter...","search_contains":true});
                    $(".jFormWrapperContainer").css("overflow","visible");
                    $(".jFormPageWrapper").css("overflow","visible");
                    $(".jFormSection").css("overflow","visible");                  
                </script>'
            )
        )
    );
}
elseif ($type == 'save_filter') {
    $filter_id = isset($_POST['filter_id']) ? $_POST['filter_id']  : '';
    if ($filter_id != ''){
        $default_filter = $collections['adv_filter']->findOne(array( "_id" => new MongoId($filter_id)));
    }
    else {
        $default_filter['name'] = '';
    }
    $name = $default_filter['name'];
    $section = new JFormSection(
        $form->id.'saveFilter',
        array(
            'title' => '<h4>Save filter</h4>',
        )
    );
    $section->addJFormComponentArray(
        array(
            new JFormComponentSingleLineText(
                'save_filter',
                'Save as:',
                array(
                    'style'=>'clear:none',
                    'initialValue'=>$name
                )
            ),
            new JFormComponentHidden(
                'filter_id',
                $filter_id
            )
        )
    );
}
elseif ($type == 'load_view') {   
    $projects_id = isset($_POST['projects_id']) ? $_POST['projects_id'] : '';
    $view_id = isset($_POST['view_id']) ? $_POST['view_id']  : '';

    $dbviews = array(
        array (
            'value' => '',
            'label' => ' - Load view - ',
            'disabled' => true,
            'selected'=>true
        )
    );
    if ($projects_id){
        // get the filters stored in the database
        $ids = array();
        foreach ($projects_id as $key=>$value){
            $ids['$in'][$key] = $value;
        }
        $views = $collections['views']->find(array( '$or'=>array(array('projects'=>$ids), array('projects'=>array('$exists'=>false))),'collection'=>'variants'));
        // build the list
        foreach($views as $key =>$view){
            array_push($dbviews,
                array(
                    'value'=>$view['_id'].'',
                    'label'=>$view['name']
                )
            );
        }
    }

    ///////////////////////////
    // Build the form itself
    ///////////////////////////
    $section = new JFormSection(
        $form->id.'loadView',
        array(
            'title' => '<h4>Load View</h4>',
        )
    );
    $section->addJFormComponentArray(
        array(
            // the database filters dropdown
            new JFormComponentDropDown(
                'load_view',
                '',
                $dbviews,
                array(
                    'width' => 'long',
                    'initialValue'=>$view_id,
                    'style' => 'clear:none'
                )
            ),
            new JFormComponentHidden(
                'view_name',
                '',
                array(
                    'dependencyOptions' => array(
                            'dependentOn' => 'load_view',
                            'display' => 'hide',
                            'jsFunction' => '$("#view_name").val($("#load_view option:selected").text());',
                    )
                )
            ),
            new JFormComponentHtml(
                '<script>
                    $("#load_view").chosen({width:"143px;",placeholder_text_single:"Select a view...","search_contains":true});
                    $(".jFormWrapperContainer").css("overflow","visible");
                    $(".jFormPageWrapper").css("overflow","visible");
                    $(".jFormSection").css("overflow","visible");                  
                </script>'
            )
        )
    );
}
elseif ($type == 'create_view') {
    $projects_id = isset($_POST['projects_id']) ? $_POST['projects_id'] : '';
    $view_id = isset($_POST['view_id']) ? $_POST['view_id']  : '';
    $hidden = '';
    $visible = '';
    $total = "<ul id='hidden_columns' class='droptrue'>Hidden";
    if ($view_id != ''){
        $default_view = $collections['views']->findOne(array( "_id" => new MongoId($view_id)));
    }
    else {
        $default_view = $collections['views']->findOne(array( "_id" => new MongoId('50d1def9721c5a2c32000000')));
    }
    foreach ($default_view as $key => $value) {
        if ($key == 'columns') {
            foreach ($value as $index => $column) {
                if ($column['bVisible'] === false) {
                    if ($column['showable'] === false) {
                        $hidden .= "<li id='".json_encode($value[$index])."' class='def_hidden' title='".$column['description']."'>".$column['sName']."</li>";
                    } 
                    else {
                       $hidden .= "<li id='".json_encode($value[$index])."' title='".$column['description']."'>".$column['sName']."</li>";
                    }  
                } 
                else {
                    if ($column['showable'] === false) {
                        $visible .= "<li id='".json_encode($value[$index])."' class='def_hidden' title='".$column['description']."'>".$column['sName']."</li>";
                    } 
                    else {
                       $visible .= "<li id='".json_encode($value[$index])."' title='".$column['description']."'>".$column['sName']."</li>";
                    }
                }
            }
        }
        elseif ($key != '_id') {
            $collection = $default_view['collection'];
            $restrict = $default_view['restrict'];
            $dom = $default_view['dom'];
            $elementmatch = $default_view['elementmatch'];
            $mongoid = $default_view['mongoid'];
        }
    }
    $total .= $hidden;
    $total .= "</ul>";
    $total .= "<ul id='visible_columns' class='droptrue'>Visible";
    $total .= $visible;
    $total .= "</ul>";
    $total .= "<button class='clear_view' >Reset</button>";

    $section = new JFormSection(
        $form->id.'saveView',
        array(
            'title' => '<h4>Create & edit view</h4>',
        )
    );
    $section->addJFormComponentArray(
        array(
            new JFormComponentHtml(
                $total
            ),
            new JFormComponentHidden(
                'save_view',
                'NO NAME'
            ),
            new JFormComponentHidden(
                'col_string',
                ''
            ),
            new JFormComponentHidden(
                'collection',
                $collection
            ),
            new JFormComponentHidden(
                'restrict',
                str_replace("\"", "'",json_encode($restrict))
            ),
            new JFormComponentHidden(
                'dom',
                $dom
            ),
            new JFormComponentHidden(
                'elementmatch',
                str_replace("\"", "'",json_encode($elementmatch))
            ),
            new JFormComponentHidden(
                'mongoid',
                $mongoid
            ),
            new JFormComponentHidden(
                'view_id',
                ''
            ),
            new JFormComponentHidden(
                'projects_id',
                str_replace("\"", "'", json_encode($projects_id))
            ),
            new JFormComponentHtml(
                '<script>
                    $(".clear_view").button({icons: {primary: "ui-icon-arrowrefresh-1-w"}});
                    $( "ul.droptrue" ).sortable({
                        connectWith: ".droptrue",
                        placeholder: "ui-state-highlight",
                        update: function( event, ui ) {
                            var vis_col = $( "#visible_columns" ).sortable( "toArray" );
                            $.each(vis_col, function (index, value){
                                vis_col[index] = eval("(" + value + ")");
                                vis_col[index].bVisible = true;
                            });
                            var hid_col = $( "#hidden_columns" ).sortable( "toArray" );
                            $.each(hid_col, function (index, value){
                                hid_col[index] = eval("(" + value + ")");
                                hid_col[index].bVisible = false;
                            });
                            var merged = $.merge(hid_col, vis_col);
                                $("#col_string").val(JSON.stringify(merged));
                        }
                    });
                    var vis_col = $( "#visible_columns" ).sortable( "toArray" );
                    $.each(vis_col, function (index, value){
                        vis_col[index] = eval("(" + value + ")");
                        vis_col[index].bVisible = true;
                    });
                    var hid_col = $( "#hidden_columns" ).sortable( "toArray" );
                    $.each(hid_col, function (index, value){
                        hid_col[index] = eval("(" + value + ")");
                        hid_col[index].bVisible = false;
                    });
                    var merged = $.merge(hid_col, vis_col);
                    $("#col_string").val(JSON.stringify(merged));
                    $("#hidden_columns, #visible_columns").disableSelection();
                    $("#visible_columns").data("visible_columns", $("#visible_columns").html());
                    $("#hidden_columns").data("hidden_columns", $("#hidden_columns").html());

                </script>'
            )
        )
    );
}
elseif ($type == 'save_view') {
    $projects_id = isset($_POST['projects_id']) ? $_POST['projects_id'] : '';
    $view_id = isset($_POST['view_id']) ? $_POST['view_id']  : '';
    if ($view_id != ''){
        $default_view = $collections['views']->findOne(array( "_id" => new MongoId($view_id)));
    }
    else {
        $default_view['name'] = '';
    }
    $name = $default_view['name'];
    $section = new JFormSection(
        $form->id.'saveView',
        array(
            'title' => '<h4>Save view</h4>',
        )
    );
    $section->addJFormComponentArray(
        array(
            new JFormComponentSingleLineText(
                'save_view',
                'Save as:',
                array(
                    'style'=>'clear:none',
                    'initialValue'=>$name
                )
            ),
            new JFormComponentHidden(
                'view_id',
                $view_id            )
        )
    );
}
elseif ($type == 'manage_project') {
    $groups = array();
    $user_id = isset($_POST['user_id']) ? $_POST['user_id']  : '';
    $groups_id = isset($_POST['groups_id']) ? $_POST['groups_id']  : '';
    $projects_id = isset($_POST['projects_id']) ? $_POST['projects_id']  : '';
    $project = $collections['projects']->findOne(array('_id'=>new MongoId($projects_id)));
    $groups_query = $collections['groups']->find(array('admin'=>new MongoId($user_id)));
    // $groups_query = $collections['groups']->find(array('admin'=>new MongoId('50d1e3b8721c5a0142000001')));
    foreach($groups_query as $key=>$group){
        foreach ($project['groups'] as $pr_gr_key => $pr_group) {
            if ($pr_group['id'].'' == $group['_id'].''){
                  $initial =  $group['_id'].'';         
            }
            array_push($groups, array('value'=>$group['_id'].'','label'=>$group['name']));  
        }
    }  
    if (count($groups) == 0) {
        array_push($groups, array ('value' => '','label' => 'You are not the admin of any (other) group(s)','disabled' => true,'selected' => true,));
    }

    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Project info</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentSingleLineText('projectname', 'Project name:', array(
            'width' => 'longest',
            'initialValue' => $project['name'], 
            'validationOptions' => array('required'),
        )),
        new JFormComponentTextArea('description', 'Description:', array(
            'width' => 'longest',
            'height' => 'medium',
            'initialValue' => $project['description'], 
        )),
        new JFormComponentDropDown('group', 'Group:', 
            $groups,
            array(
                'width' => 'long',
                'tip' => '<p>Select one of your groups.</p>',
                'initialValue' => $initial,
        )),
        new JFormComponentHidden('projects_id',$projects_id),
    ));
}
elseif ($type == 'add_project') {

    /////////////////////////////
    // Get projects from database
    /////////////////////////////

    // buil the dropdown
    $dropdown = array();
    array_push($dropdown,
        array (
            'value' => '',
            'label' => ' - Select group - ',
            'disabled' => true,
            'selected' => true
        )
    );

    // Get all groups the user is member of
   foreach ($_SESSION['groups'] as $id => $name){
        if ($name != 'Public'){
            array_push(
                $dropdown,
                array(
                    'value'=>$id,
                    'label'=>$name
                )
            );
        }
    }

    /////////////////////////////
    // BUILD THE FORM
    /////////////////////////////

    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Add project</h4>',
    ));

    $section->addJFormComponentArray(
        array(
            new JFormComponentDropDown(
                'groupid',
                'Group:',
                $dropdown,
                array('width' => 'long')
            ),
            new JFormComponentSingleLineText(
                'projectname',
                'Project Name:',
                array(
                    'width' => 'long',
                    'validationOptions' => array('required'),
                )
            ),
            new JFormComponentTextArea(
                'description',
                'Description:',
                array(  
                    'width' => 'longest',
                    'height' => 'medium',
                    'height' => 'short'
                )
            )
        )
    );
}
elseif ($type == 'manage_sample') {
    $projects = array();
    $genomelist = array();
    $genomes = $collections['genome']->find();
    foreach ($genomes as $doc) {
        array_push(
            $genomelist,
            array(
                'value'=>$doc['_id'],
                'label'=>$doc['_id'],
            )
        );
    }
    $user_id = isset($_POST['user_id']) ? $_POST['user_id']  : '';
    $projects_id = isset($_POST['projects_id']) ? $_POST['projects_id']  : '';
    $sel_project = $collections['projects']->findOne(array('_id'=>new MongoId($projects_id)));
    $samples_id = isset($_POST['samples_id']) ? $_POST['samples_id']  : '';
    $sample = $collections['samples']->findOne(array('_id'=>new MongoId($samples_id)));
    $groups_query = $collections['groups']->find(array('admin'=>new MongoId($user_id)));
    // $groups_query = $collections['groups']->find(array('admin'=>new MongoId('50d1e3b8721c5a0142000001')));

    $db_projects = $sample['project'];
    $db_names = array();
    $db_ids = array();
    foreach ($db_projects as $key => $db_proj) {
        array_push($db_names, $db_proj['name']);
        array_push($db_ids, $db_proj['id'].'');
        $db_projects[$key]['id'] = $db_proj['id'].'';
    }
    array_push($projects, array('value'=>str_replace( "\"", "'",json_encode($db_projects)),'label'=>implode(" --- ", $db_names))); 

    foreach($groups_query as $key=>$group){
        $projects_query = $collections['projects']->find(array('groups.id'=>new MongoId($group['_id'])));
        foreach ($projects_query as $proj_key => $project) {
                if ($sel_project['_id'].'' == $project['_id'].''){
                    $initial = $project['_id'].'';
                }
                if (in_array($project['name'], $db_names)) {
                $x = array_search($project['name'], $db_names);
                unset($db_names[$x]);
                unset($db_ids[$x]);
                unset($db_projects[$x]);
                array_push($projects, array('value'=>str_replace( "\"", "'",json_encode($db_projects)),'label'=>implode(" --- ", $db_names)));
            }          
        }     
    }
    // if (count($projects) == 0) {
    //     array_push($projects, array ('value' => '','label' => 'You are not the admin of any (other) group(s)','disabled' => true,'selected' => true,));
    // }

    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Sample info</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentSingleLineText('samplename', 'Sample name:', array(
            'width' => 'longest',
            'initialValue' => $sample['name'], 
            'validationOptions' => array('required'),
        )),
        new JFormComponentTextArea('description', 'Description:', array(
            'width' => 'longest',
            'height' => 'medium',
            'initialValue' => $sample['description'], 
        )),
        new JFormComponentDropDown('project', 'Project:', 
            $projects,
            array(
                'width' => 'long',
                'tip' => '<p>Select one of your projects.</p>',
                'initialValue' => $initial,
        )),
        new JFormComponentDropDown('genome', 'Genome:', 
            $genomelist,
            array(
                'width' => 'long',
                'initialValue' => $sample['genome'],
        )),
        new JFormComponentHidden('sampleid',$samples_id),
        new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),
        new JFormComponentHidden('config_id',  date("Y-m-d_H-i-s")."_".str_replace(".", "_",substr($_SESSION['email'], 0,strpos($_SESSION['email'], '@')))."_".$job_scripts[$type])
    ));
}
elseif ($type == 'add_sample') {
    $dropdown = array();
    $genomelist = array();
    $projects_id = isset($_POST['projects_id']) ? $_POST['projects_id']  : '';

    $genomes = $collections['genome']->find();
    foreach ($genomes as $doc) {
        array_push(
            $genomelist,
            array(
                'value'=>$doc['_id'],
                'label'=>$doc['_id'],
                'selected'=>true
            )
        );
    }

    foreach ($_SESSION[projects] as $key => $project){
        if ($key == $projects_id) {
            array_push(
                $dropdown,
                array(
                    'value'=>$key, // the mongo id
                    'label'=>$project['name'],
                    'selected'=>true
                )
            );
        }
        else {
            array_push(
                $dropdown,
                array(
                    'value'=>$key, // the mongo id
                    'label'=>$project['name']
                )
            );
        }
    }

    $sampleinfo = new JFormSection($form->id.'Sampleinfo', array(
        'title' => '<h4>Add sample</h4>',
    ));
    
    $sampleinfo->addJFormComponentArray(
        array(
            new JFormComponentSingleLineText(
                'samplename',
                'Sample Name:',
                array(
                    'width' => 'long',
                    'validationOptions' => array('required')
                )
            ),
            new JFormComponentDropDown(
                'projectid',
                'Project:',
                $dropdown,
                array(
                    'width' => 'long',
                    'validationOptions' => array('required')
                )
            ),
            new JFormComponentDropDown(
                'genomebuild',
                'Genome build:',
                $genomelist,
                array(
                    'width' => 'long',
                    'validationOptions' => array('required')
                )
            ),
            new JFormComponentTextArea(
                'description',
                'Description:',
                array(
                    'width' => 'longest',
                    'height' => 'medium',
                    'height' => 'short',
                )
            )
        )
    );
    // add sample section to form
    $form->addJFormSection($sampleinfo);

    // Create the form section
    $section = new JFormSection(
        $form->id.'Section',
        array(
            'title' => '<h4>Associate files</h4>',
        )
    );

    $allfiles = array();

    $samplefiletype = array(
        array(
            'value' => '',
            'label' => ' - Select type - ',
            'disabled' => true,
            'selected'=>true
        ),
        array(
            'value'=>'local',
            'label'=>'Local server'
        ),
        array(
            'value'=>'http',
            'label'=>'http'
        ),
        array(
            'value'=>'ftp',
            'label'=>'ftp'
        ),
        array(
            'value'=>'https',
            'label'=>'https'
        )
    );


    $compression = array(
        array(
            'value' => '',
            'label' => ' - Select compression - ',
            'disabled' => true,
            'selected'=>true
        ),
        array(
            'value'=>'',
            'label'=>'none'
        ),
        array(
            'value'=>'gzip',
            'label'=>'gzip'
        ),
        array(
            'value'=>'bzip',
            'label'=>'bzip'
        ),
        array(
            'value'=>'zip',
            'label'=>'zip'
        )
    );

    $filetypes = array(
        array(
            'value' => '',
            'label' => ' - Select type - ',
            'disabled' => true,
            'selected'=>true
        ),
        array(
            'value'=>'fastq',
            'label'=>'fastq'
        ),
        array(
            'value'=>'bam',
            'label'=>'bam'
        ),
        array(
            'value'=>'vcf',
            'label'=>'vcf'
        ),
        array(
            'value'=>'wig',
            'label'=>'wiggle'
        )
    );

    $i = 0;
    $j = $i+1;

    // add first file
    $newfile = array(
        new JFormComponentDropDown(
            'samplefiletype'.$i,
            'File '.$j.' type:',
            $samplefiletype,
            array(
                'width' => 'long',
            )
        ),
        new JFormComponentSingleLineText(
            'file'.$i,
            'Full path:',
            array(
                'width' => 'long',
                'style'=>'clear:none; display: none;'
            )
        ),
        // new JFormComponentSingleLineText(
        //     'path'.$i,
        //     'Full path:',
        //     array(
        //         'width' => 'long',
        //         'style'=>'clear:none; display: none;'
        //     )
        // ),
        new JFormComponentSingleLineText(
            'host'.$i,
            'Host:',
            array(
                'width' => 'long',
                'style'=>'clear:none; display: none;'
            )
        ),
        new JFormComponentSingleLineText(
            'user'.$i,
            'User:',
            array(
                'width' => 'long',
                'style'=>'clear:none; display: none;'
            )
        ),
        new JFormComponentSingleLineText(
            'https'.$i,
            'Password:',
            array(
                'width' => 'long',
                'style'=>'clear:none; display: none;',
                'validationOptions' => array(),
            )
        ),
        new JFormComponentDropDown(
            'compression'.$i,
            'Compression:',
            $compression,
            array(
                'style'=>'clear:none; display: none;'
            )
        ),
        new JFormComponentDropDown(
            'filetype'.$i,
            'Filetype:',
            $filetypes,
            array(
                'style'=>'clear:none; display: none;'
            )
        ),
        new JFormComponentHtml(
            '<button id="fileremove" counter="'.$i.'" class="removefileline" style="clear:none;">Remove</button>'
        )
    );
    array_splice($allfiles, count($allfiles), 0, $newfile);
    $i++;
    $j = $i+1;

    while($i<=10){
        $newfile = array(
            new JFormComponentDropDown(
                'samplefiletype'.$i,
                'File '.$j.' type:',
                $samplefiletype,
                array(
                    'width' => 'long',
                    'style'=>'clear:none; display: none;'
                )
            ),
            new JFormComponentSingleLineText(
                'file'.$i,
                'Full path:',
                array(
                    'width' => 'long',
                    'style'=>'clear:none; display: none;'
                )
            ),
            // new JFormComponentSingleLineText(
            //     'path'.$i,
            //     'Full path:',
            //     array(
            //         'width' => 'long',
            //         'style'=>'clear:none; display: none;'
            //     )
            // ),
            new JFormComponentSingleLineText(
                'host'.$i,
                'Host:',
                array(
                    'width' => 'long',
                    'style'=>'clear:none; display: none;'
                )
            ),
            new JFormComponentSingleLineText(
                'user'.$i,
                'User:',
                array(
                    'width' => 'long',
                    'style'=>'clear:none; display: none;'
                )
            ),
            new JFormComponentSingleLineText(
                'https'.$i,
                'Password:',
                array(
                    'width' => 'long',
                    'style'=>'clear:none; display: none;',
                    'type'=>'text',
                    'validationOptions' => array(),
                )
            ),
            new JFormComponentDropDown(
                'compression'.$i,
                'Compression:',
                $compression,
                array(
                    'style'=>'clear:none; display: none;'
                )
            ),
            new JFormComponentDropDown(
                'filetype'.$i,
                'Filetype:',
                $filetypes,
                array(
                    'style'=>'clear:none; display: none;'
                )
            )
        );

        array_splice($allfiles, count($allfiles), 0, $newfile);
        $i++;
        $j = $i+1;
    };

    $section->addJFormComponentArray(
        $allfiles
    );
}
elseif ($type == 'compare_variants') {
    // use the onjobsubmit function to process the data
    $form->onSubmitFunctionServerSide = 'onjobsSubmit';

    // Get file parameters
    $samples_ids    = isset($_POST['samples_id']) ? json_decode(str_replace("'", "\"",$_POST['samples_id']))  : array();

    // Initialize dropdown for selectable files
    $ref_files = array(
        array(
            'value' => '',
            'label' => '',
        )
    );

    $comp_files = array(
        array(
            'value' => '',
            'label' => '',
        )
    );

    $ref_genome = '';
    $genome_err = 0;
    foreach ($samples_ids as $key => $sample) {
        $samples = $collections['samples']->findOne(array('_id'=>create_mongo_id($sample)));
        if ($ref_genome != '' && $ref_genome != $samples['genome']) {
            $genome_err = 1;
        }
        $ref_genome = $samples['genome'];
        // build the list
        if (isset($samples['files'])){
            foreach($samples['files'] as $file){
                $file['sampleid'] = $samples['_id']."";
                if ($file['filetype'] == 'bam') {
                    array_push($ref_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$samples['name'].' - '.$file['name']
                        )
                    );
                    array_push($comp_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$samples['name'].' - '.$file['name']
                        )
                    );
                } 
            }
        }
    }
    $section = new JFormSection(
        $form->id.'Section',
        array(
            'title' => '<h4>Compare variants</h4>',
        )
    );
    if ($genome_err == 0) {
        $formcomponents = array(
            new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),
            new JFormComponentHidden(
                '_id',
                date("Y-m-d_H-i-s")."_".str_replace(".", "_",substr($_SESSION['email'], 0,strpos($_SESSION['email'], '@')))."_".$type
            ),
            new JFormComponentHidden('genomebuild', $ref_genome)
        );
        $reffiledropdown = new JFormComponentDropDown(
            'refbam',
            'Select a reference BAM-file',
            $ref_files,
            array(
                'width' => '350px',
                'style' => 'clear:both;',
                'validationOptions' => array(
                    'required'
                )
            )       
        );
        $compfiledropdown = new JFormComponentDropDown(
            'compbam',
            'Select a BAM-file',
            $comp_files,
            array(
                'width' => '350px',
                'style' => 'clear:both;',
                'validationOptions' => array(
                    'required'
                )
            )       
        );
        if (!isset($ref_files[2])){
            $reffiledropdown->style = 'display: none;';
            $compfiledropdown->style = 'display: none;';

            array_push($formcomponents,
                new JFormComponentHtml(
                    "<div style='clear: both;'>Not enough BAM-files to compare variants</div>"
                )
            );
        }
        array_push(
            $formcomponents,
            $reffiledropdown,
            new JFormComponentHtml(
                '<script>
                $("#refbam").chosen({placeholder_text_single:"Select a file...",allow_single_deselect: true});
                $(".jFormWrapperContainer").css("overflow","visible");
                $(".jFormPageWrapper").css("overflow","visible");
                $(".jFormSection").css("overflow","visible");
                </script>'
            ),
            $compfiledropdown,
            new JFormComponentHtml(
                '<script>
                $("#compbam").chosen({placeholder_text_single:"Select a file...",allow_single_deselect: true});
                $(".jFormWrapperContainer").css("overflow","visible");
                $(".jFormPageWrapper").css("overflow","visible");
                $(".jFormSection").css("overflow","visible");
                </script>'
            )
        );
    }
    else {
        $formcomponents = array(
            new JFormComponentHtml(
                "<div>Please select samples with the same reference genome!</div>"
            )
        );
    }
    $section->addJFormComponentArray($formcomponents);
}
elseif ($type == 'coverage') {
    // use the onjobsubmit function to process the data
    $form->onSubmitFunctionServerSide = 'onjobsSubmit';
    
    // Get file parameters
    $samples_ids    = isset($_POST['samples_id']) ? json_decode(str_replace("'", "\"",$_POST['samples_id']))  : array();

    // Initialize dropdown for selectable files
    $available_files = array(
        array(
            'value' => '',
            'label' => '',
        )
    );

    $region_files = array(
        array(
            'value' => '',
            'label' => '',
        )
    );
    $ref_genome = '';
    $genome_err = 0;
    foreach ($samples_ids as $key => $sample) {
        $samples = $collections['samples']->findOne(array('_id'=>create_mongo_id($sample)));
        if ($ref_genome != '' && $ref_genome != $samples['genome']) {
            $genome_err = 1;
        }
        $ref_genome = $samples['genome'];
        // build the list
        if (isset($samples['files'])){
            foreach($samples['files'] as $file){
                $file['sampleid'] = $samples['_id']."";
                if ($file['filetype'] == 'bam') {
                    array_push($available_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['name']
                        )
                    );
                } elseif ($file['filetype'] == 'bed') {
                    array_push($region_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['name']
                        )
                    );
                }
            }
        }
    }

    $section = new JFormSection(
        $form->id.'Section',
        array(
            'title' => '<h4>Coverage</h4>',
        )
    );
    if ($genome_err == 0) {
        $formcomponents = array(
            new JFormComponentHtml(
                "<div>Generate coverage statistics by selecting a bam file and a gene or region of interest</div>"
            )
        );

        $bamfiledropdown = new JFormComponentDropDown(
            'bam',
            'Select a BAM-file',
            $available_files,
            array(
                'width' => '350px;',
                'multiple'=> true,
                'style' => 'clear:both;',
                'validationOptions' => array(
                    'required'
                )
            )       
        );

        if (!isset($available_files[1])){
            $bamfiledropdown->style = 'display: none;';
            array_push($formcomponents,
                new JFormComponentHtml(
                    "<div style='clear: both;'>Please associate a bam file with your sample for coverage calculations</div>"
                )
            );
        }

        array_push(
            $formcomponents,
            $bamfiledropdown,
            new JFormComponentHtml(
                '<script>$("#bam").chosen({placeholder_text_multiple:"Select one or more BAM-files..."});</script>'
            ),
            new JFormComponentSingleLineText(
                'gene',
                'Gene or region',
                array(
                    'width' => 'longest',
                    'style' => 'clear:both;'
                )
            ),
            new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),
            new JFormComponentHidden(
                '_id',
                date("Y-m-d_H-i-s")."_".str_replace(".", "_",substr($_SESSION['email'], 0,strpos($_SESSION['email'], '@')))."_".$type
            ),
            new JFormComponentHidden('export', 'mongodb'),
            new JFormComponentHidden('genomebuild', $ref_genome)
        );

        $regionfiledropdown =  new JFormComponentDropDown(
            'region',
            'Select region file',
            $region_files,
            array(
                'width' => 'long',
                'multiple'=> true,
                'style' => 'clear:both;'
            )
        );

        if (!isset($region_files[1])){
            $regionfiledropdown->style = 'display: none;';
            array_push(
                $formcomponents,
                new JFormComponentHtml(
                    "<div style='clear: both;'>Associate bed files with genomic regions to calculate coverage in more complex regions</div>"
                )
            );
        }

        array_push(
            $formcomponents,
            $regionfiledropdown,
            new JFormComponentHtml(
                '<script>$("#region").chosen({placeholder_text_multiple:"Select one or more BED-files..."});</script>'
            )
        );

        array_push(
                $formcomponents,
                new JFormComponentHtml(
                    "<img class='form_folder' src='img/icon_tree_on.gif'>Parameters<div id='form_folder' style='display:none'>"
                )
            );
        $reftypes = array(
            array(
                'value' => '',
                'label' => '',
            )
        );
        $all_xrefs = array("2DBase_Ecoli","AedesGenBank","Aedes_ManualAnnotation","AFFY_ATH1","AFFY_Poplar","AFFY_RICE","AFFY_Vitis_Vinifera","AGD","AGD_GENE","AGD_TRANSCRIPT","Anopheles_symbol","ArrayExpress","ArrayExpressExperiment","ASPGD","ASPGD_GENE","ASPGD_TRANSCRIPT","BDGP_cDNA","BDGP_cDNA_Gold_Collection","BDGP_insitu_expr","BGI Shenzhen","BGI_duck_transcriptome","BGI_EST_Cluster","BGI_Gene","BioCyc","BioGRID","BRAD_GENE","BRAD_TRANSCRIPT","BRENDA","BRIGGSAE_HYBRID","BroadInstitute","BROAD_coelacanth_transcriptome","BROAD_F_oxysporum","BROAD_F_oxysporum_GENE","BROAD_F_oxysporum_TRANSCRIPT","BROAD_G_moniliformis","BROAD_G_moniliformis_GENE","BROAD_G_moniliformis_TRANSCRIPT","BROAD_G_zeae","BROAD_G_zeae_GENE","BROAD_G_zeae_TRANSCRIPT","BROAD_Magnaporthe_DB","BROAD_Magnaporthe_DB_GENE","BROAD_Magnaporthe_DB_TRANSCRIPT","BROAD_M_oryzae","BROAD_M_oryzae_GENE","BROAD_M_oryzae_TRANSCRIPT","BROAD_N_crassa","BROAD_N_crassa_GENE","BROAD_N_crassa_TRANSCRIPT","BROAD_PUCCINIA","BROAD_PUCCINIA_GENE","BROAD_PUCCINIA_TRANSCRIPT","BROAD_P_infestans","BROAD_P_infestans_GENE","BROAD_P_infestans_TRANSCRIPT","BROAD_P_NODORUM","BROAD_P_NODORUM_GENE","BROAD_P_NODORUM_TRANSCRIPT","BROAD_P_triticina","BROAD_P_triticina_GENE","BROAD_P_triticina_TRANSCRIPT","BROAD_U_maydis","BROAD_U_maydis_GENE","BROAD_U_maydis_TRANSCRIPT","BudgerigarGenomeProject","BuruList","CADRE","CADRE_Afum_A1163","CADRE_GENE","CADRE_TRANSCRIPT","CaeEle_est","CBS","CCDS","Celera_Gene","Celera_Pep","Celera_Trans","CGD","cint_aniseed_v1","cint_aniseed_v2","cint_jgi_v1","cint_jgi_v2","CioInt_cdna","CioInt_est","CioSav_est","Clone_based_ensembl_gene","Clone_based_ensembl_transcript","Clone_based_vega_gene","Clone_based_vega_transcript","COG","CSAC","Culex_ncRNA","DBASS3","DBASS5","DEDb","Diatom_EST_Cluster","dictyBase","dictyBase_gene","dictyBase_transcript","DIP","DisProt","DROS_ORTH","DrugBank","Duck_consortium","EBACTERIA_GENE","EBACTERIA_TRANSCRIPT","EchoBASE","EcoGene","EC_NUMBER","EFUNGI_GENE","EFUNGI_TRANSCRIPT","EMBL","EMBLBANK_GENE","EMBLBANK_TRANSCRIPT","EMBL_predicted","ENSG","ENST","ENST_CDS","ENST_ident","Ens_Aa_translation","Ens_Ac_gene","Ens_Ac_transcript","Ens_Ac_translation","Ens_Ag_gene","Ens_Am_gene","Ens_Ce_gene","Ens_Cf_gene","Ens_Cf_transcript","Ens_Cf_translation","Ens_Dm_gene","Ens_Dr_gene","Ens_Dr_transcript","Ens_Dr_translation","Ens_Fc_transcript","Ens_Fc_translation","Ens_Fr_gene","Ens_Ga_gene","Ens_Ga_transcript","Ens_Ga_translation","Ens_Gg_gene","Ens_Gg_transcript","Ens_Gg_translation","Ens_Hs_gene","Ens_Hs_transcript","Ens_Hs_translation","Ens_Lc_gene","Ens_Lc_transcript","Ens_Lc_translation","ENS_LRG_gene","ENS_LRG_transcript","Ens_Md_gene","Ens_Md_transcript","Ens_Mg_transcript","Ens_Mm_gene","Ens_Mm_transcript","Ens_Mm_translation","Ens_Ol_gene","Ens_Pt_gene","Ens_Rn_gene","Ens_Rn_transcript","Ens_Rn_translation","Ens_Ss_translation","Ens_St_transcript","Ens_Tg_transcript","Ens_Tg_translation","Ens_Tn_gene","Ens_Tr_transcript","EntrezGene","EO","EPD","EPROTIST_GENE","EPROTIST_TRANSCRIPT","Fantom","FlyBaseCGID_gene","FlyBaseCGID_transcript","FlyBaseCGID_translation","FlyBaseName_gene","FlyBaseName_transcript","FlyBaseName_translation","flybase_annotation_id","flybase_gene_id","flybase_gff","flybase_name","flybase_polypeptide_id","flybase_symbol","flybase_synonym","flybase_transcript_id","flybase_translation_id","FlyExpress","FlyGrid","FlyReactome","FSTs","FYPO","FYPO_GENE","FYPO_TRANSCRIPT","gadfly_gene_cgid","gadfly_transcript_cgid","gadfly_translation_cgid","GasAcu_cdna","GenBank","GeneDB","GeneDB_GENE","GeneDB_Spombe","GeneDB_SPombe_gene","GeneDB_SPombe_transcript","GeneDB_TRANSCRIPT","GeneDB_TRANSLATION","GeneIndex","gene_name","GenomeRNAi","Genoscope_annotated_gene","Genoscope_ann_transcript","Genoscope_ann_translation","Genoscope_pred_gene","Genoscope_pred_transcript","Genoscope_pred_translation","GermOnline","GGSC","GI","GKB","GlycoSuiteDB","GO","goslim_generic","goslim_goa","GO_REF","GO_to_gene","GPCR","Gramene_GenesDB","Gramene_MarkersDB","Gramene_MarkersDB_EST","Gramene_MarkersDB_mRNA","Gramene_Pathway","GRC_human_primary_assembly","GRO","HAMAP","Havana_gene","HGNC","HGNC_automatic_gene","HGNC_automatic_transcript","HGNC_curated_gene","HGNC_curated_transcript","HGNC_transcript_name","HOGENOM","HPA","HSSP","ICGSC","IGDBCAS-v.4_GENE","IGDBCAS-v.4_TRANSCRIPT","IKMCs_ES_cells_available","IKMCs_KOs","IKMCs_Mice_available","IKMCs_No_products_available_yet","IKMCs_Vector_available","Illumina_Bodymap_transcriptome","IMCB_Tr_gene","IMG/GENE_DB","IMG/LIGM_DB","IMGT_HLA","ImmunoDB","IntAct","IntEnz","InteractiveFly","Interpro","IPI","IRGSPv1_GENE","IRGSPv1_TRANSCRIPT","IRGSP_Gene","ITAG_GENE","ITAG_TRANSCRIPT","Ixodes_ManualAnnotation","JGI_GENE","JGI_TRANSCRIPT","KEGG","KOG","KOME","kyotograil_2004","kyotograil_2005","Kyoto_University","LampreyGenomeProject","Leproma","LRG","MaizeGDB_GenBank","Medaka","MEDLINE","MEROPS","MGI","MGI_automatic_gene","MGI_automatic_transcript","MGI_curated_gene","MGI_curated_transcript","MGI_transcript_name","MIM","MIM_GENE","MIM_MORBID","miRBase","miRBase_gene_name","miRBase_predicted","miRBase_transcript_name","miRNA_Accession","miRNA_Registry","MitoDrome","MOD","modCB_gene","modCE_gene","modDD_gene","Mycgr3_jgi_v2.0","Mycgr3_jgi_v2.0_gene","Mycgr3_jgi_v2.0_transcript","NASC_GENE_ID","NASC_TRANSCRIPT_ID","necha_jgi_v2.0","necha_jgi_v2.0_gene","necha_jgi_v2.0_transcript","OrnAna_454_cdna","Orphanet","OryLat_est","OTTG","OTTP","OTTT","Oxford_FGU_Md_gene","Oxford_FGU_Md_tscript","Oxford_FGU_Oa_gene","Oxford_FGU_Oa_tscript","Painted_Turtle_Consortium","PBO","PDB","PDBsum","PeroxiBase","PFAM","PGD","PGD_GENE","PGD_TRANSCRIPT","phatr_jgi_v2","phatr_jgi_v2_bd","phatr_jgi_v2_bd_gene","phatr_jgi_v2_bd_transcript","phatr_jgi_v2_gene","phatr_jgi_v2_transcript","PHIbase","PhosSite","phyra_jgi_v1.1","phyra_jgi_v1.1_gene","phyra_jgi_v1.1_transcript","physo1_jgi_v1.1","physo1_jgi_v1.1_gene","physo1_jgi_v1.1_transcript","PIR","PlantGDB_PUT","Platypus_olfactory_receptor","PO","PomBase","PomBase_GENE","PomBase_Gene_Name","PomBase_Interaction_GENETIC","PomBase_Interaction_PHYSICAL","PomBase_Ortholog","PomBase_Systematic_ID","PomBase_TRANSCRIPT","PomBase_TRANSLATION","PO_to_gene","PptaseDB","prediction_SPTREMBL","PRF","ProSite","protein_id","protein_id_predicted","Psinensis_sequencing_consortium","PUBMED","Quick_Go","Quick_Go_Evidence","RAP_Gene","Reactome","REBASE","RefSeq_dna","RefSeq_dna_predicted","RefSeq_gene_name","RefSeq_genomic","RefSeq_mRNA","RefSeq_mRNA_predicted","RefSeq_ncRNA","RefSeq_ncRNA_predicted","RefSeq_peptide","RefSeq_peptide_predicted","RefSeq_rna","RefSeq_rna_predicted","RegulonDb_Gene","RegulonDb_Operon","RegulonDb_Transcript","RFAM","RFAM_gene_name","RFAM_transcript_name","RGD","RGSC","Ribosomal_Protein_Gene_Database","RIKEN","RNAMMER","SagaList","Sanger_Hver1_2_1","Sanger_Hver1_3_1","Sanger_Mver1_1_1","SCHISTODB","SCHISTODB_GENE","SCHISTODB_TRANSCRIPT","SGD","SGD_GENE","SGD_TRANSCRIPT","SGD_TRANSLATION","SGN","SGSC","shares_CDS_and_UTR_with_OTTT","shares_CDS_with","shares_CDS_with_ENST","shares_CDS_with_OTTT","SHSC","siRNA_Sunkar","SMART","SNGR_Hver","SO","SpBase","SPD","SPO","SubtiList","Superfamily","SWISS_2DPAGE","TAIR_LOCUS","TAIR_LOCUS_MODEL","TakRub_annotation","TakRub_cdna","TakRub_est","TakRub_seleno_annotation","TCAG","TetNig_cdna","TetNig_chick_econtig","TetNig_fugu_econtig","TetNig_human_econtig","TetNig_human_IPI_econtig","TetNig_mouse_econtig","TetNig_mouse_IPI_econtig","TetNig_rat_econtig","Tgut_symbol","thaps_jgi_v2","thaps_jgi_v2_bd","thaps_jgi_v2_bd_gene","thaps_jgi_v2_bd_transcript","thaps_jgi_v2_gene","thaps_jgi_v2_transcript","Tiffin","TIGR","TIGR_GeneIndex","TIGR_LOCUS","TIGR_LOCUS_MODEL","TO","ToxoDB","Trace_archive","TransFac","triad_jgi_v1.0","triad_jgi_v1.0_gene","triad_jgi_v1.0_transcript","TRNASCAN_SE","TubercuList","tuber_genoscope","tuber_genoscope_gene","tuber_genoscope_transcript","UCSC","UniGene","UniParc","Uniprot/SPTREMBL","Uniprot/SPTREMBL_predicted","Uniprot/SWISSPROT","Uniprot/SWISSPROT_predicted","Uniprot/Varsplic","UniProtKB_all","Uniprot_genename","Uppsala University","VB_Community_Annotation","VB_Community_Symbol","VB_External_Description","VB_RNA_Description","Vega_gene","Vega_gene_like","Vega_mouse_transcript","Vega_transcript","Vega_transcript_like","Vega_translation","WashingtonUniversity","WikiGene","wormbase_gene","wormbase_id","wormbase_locus","wormbase_pseudogene","wormbase_transcript","wormpep_id","WTSI_gorilla_transcriptome","WTSI_zebrafish_transcriptome","XenLae_cdna","Xenopus_Jamboree","XenTro_cdna","XenTro_Gurdon_EST","ZFIN_ID","ZFIN_ID_transcript_name","ZFIN_xpat");
        foreach ($all_xrefs as $key => $xref) {
            array_push($reftypes,array('value'=>$xref,'label'=>$xref));
        }
        $params = array(
            new JFormComponentSingleLineText('treshold', 'Treshold:', array(
                'width' => 'short',
                'initialValue' => '20', 
            )),
            new JFormComponentSingleLineText('bininterval', 'Bininterval:', array(
                'width' => 'short',
                'initialValue' => '10', 
                'validationOptions' => array(
                    'integer'
                )
            )),
             new JFormComponentSingleLineText('normalizeto', 'Normalize to:', array(
                'width' => 'short',
            )),
            new JFormComponentMultipleChoice('codingonly', '', 
                array(
                    array(
                        'value' => 'boolean_true',
                        'label' => 'Coding parts of exons only'
                    )
                )
            ),
            new JFormComponentMultipleChoice('meannormalize', '', 
                array(
                    array(
                        'value' => 'boolean_true',
                        'label' => 'Use mean value as normalisation parameter'
                    )
                )
            ),
            new JFormComponentMultipleChoice('allgenes', '', 
                array(
                    array(
                        'value' => 'boolean_true',
                        'label' => 'All genes'
                    )
                )
            ),
            new JFormComponentDropDown('xreftype', '', 
                $reftypes,
                array(
                    'width' => '350px;',
                    'dependencyOptions' => array(
                            'dependentOn' => 'allgenes',
                            'display' => 'hide',
                            'jsFunction' => '$("#allgenes-choice1").is(":checked")',
                    )
                )
            ), 
            new JFormComponentHtml(
                '<script>
                $("#xreftype").chosen({placeholder_text_single:"Select an xref-table...",width:"350px",allow_single_deselect: true });
                    </script>'
            ),
            new JFormComponentMultipleChoice('readstats', '', 
                array(
                    array(
                        'value' => 'boolean_true',
                        'label' => 'Generate global read statistics on BAM-file'
                    )
                )
            ),
            new JFormComponentMultipleChoice('cannonical', '', 
                array(
                    array(
                        'value' => 'boolean_true',
                        'label' => 'Use cannonical names'
                    )
                )
            )
        );

        foreach ($params as $key => $param){
            array_push(
                $formcomponents,
                $param
            );
        }

        array_push(
                $formcomponents,
                new JFormComponentHtml(
                    "</div>"
                )
            );
    }
    else {
        $formcomponents = array(
            new JFormComponentHtml(
                "<div>Please select samples with the same reference genome!</div>"
            )
        );
    }
    $section->addJFormComponentArray($formcomponents);
}
elseif ($type == 'export') {
    $form->onSubmitFunctionServerSide = 'onjobsSubmit';
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Export results</h4>',
    ));
    $formcomponents = array(
        new JFormComponentHidden('where', str_replace( "\"", "'",json_encode($_POST['where']))),
        new JFormComponentHidden('filter', str_replace( "\"", "'",json_encode($_POST['filter']))),
        new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),
        new JFormComponentHidden('config_id',  date("Y-m-d_H-i-s")."_".str_replace(".", "_",substr($_SESSION['email'], 0,strpos($_SESSION['email'], '@')))."_".$job_scripts[$type])
    );
    $all_columns = $collections['variants_unique']->find(array(),array('_id'=>1, 'name'=>1));
    $columns = 
        array(
            array(
                'value' => '',
                'label' => '',
            )
        );
    foreach ($all_columns as $key => $column) {
        $label = $column['name'] ? $column['name'] : $column['_id'];
        array_push($columns, 
            array(
                'value' => $column['_id'],
                'label' => $label
            )
        );
    }
    array_push($formcomponents, 
            new JFormComponentDropDown('columns', 'Select the columns you want to export', 
                $columns,
                array(
                    'width' => '350px',
                    'multiple'=> true,
                    'style' => 'clear:both;'
                )
            ),
            new JFormComponentHtml(
                '<script>
                $("#columns").chosen({placeholder_text_multiple:"Select one or more column(s) ..."});
                    </script>'
            ),
            new JFormComponentSingleLineText('filename', 'Filename (optional):', array(
                'width' => 'longest',
            )),
            new JFormComponentDropDown('delimiter', 'Delimiter:',
                array(
                    array(
                        'value' => 'tab',
                        'label' => 'tab',
                        'selected' => true
                    ),
                    array(
                        'value' => 'comma',
                        'label' => 'comma'
                    ),
                    array(
                        'value' => 'semicolon',
                        'label' => 'semicolon'
                    ),
                    array(
                        'value' => 'space',
                        'label' => 'space'
                    )
                ),
                array(
                    'width'=>'250px'
                )
            ),
            new JFormComponentHtml(
                '<script>
                $("#delimiter").chosen({placeholder_text_single:"Select a delimiter ...",disable_search_threshold: 5});
                    </script>'
            )
        );

    $section->addJFormComponentArray($formcomponents);
}
elseif ($type == 'create_plot') {
    $form->onSubmitFunctionServerSide = 'onjobsSubmit';
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Create plot</h4>',
    ));
    $formcomponents = array(
        new JFormComponentHidden('where', str_replace( "\"", "'",json_encode($_POST['where']))),
        new JFormComponentHidden('filter', str_replace( "\"", "'",json_encode($_POST['filter']))),
        new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),
        new JFormComponentHidden('config_id',  date("Y-m-d_H-i-s")."_".str_replace(".", "_",substr($_SESSION['email'], 0,strpos($_SESSION['email'], '@')))."_".$job_scripts[$type]),
        new JFormComponentHidden('export','mongodb')
    );
    $all_columns = $collections['variants_unique']->find(array(),array('_id'=>1, 'name'=>1));
    $columns = 
        array(
            array(
                'value' => '',
                'label' => '',
            )
        );
    foreach ($all_columns as $key => $column) {
        $label = $column['name'] ? $column['name'] : $column['_id'];
        array_push($columns, 
            array(
                'value' => $column['_id'],
                'label' => $label
            )
        );
    }
    array_push($formcomponents, 
        new JFormComponentDropDown('columns', 'Select the columns you want to export', 
            $columns,
            array(
                'width' => '350px',
                'multiple'=> true,
                'style' => 'clear:both;'
            )
        ),
        new JFormComponentHtml(
            '<script>
            $("#columns").chosen({placeholder_text_multiple:"Select one or more column(s) ..."});
                </script>'
        ),
        new JFormComponentSingleLineText(
            'plot', 
            'Plotname (optional):', 
            array(
                'width' => 'longest',
            )
        )
    );

    $section->addJFormComponentArray($formcomponents);
}
elseif ($type == 'rename') {
    $project_ids = isset($_POST['projects_id']) ? json_decode(str_replace("'", "\"",$_POST['projects_id']))  : array();
    $sampleid = isset($_POST['samples_id']) ? $_POST['samples_id']  : '';
    $sample = $collections['samples']->findOne(array('_id'=>new MongoId($sampleid)));
    $projects = array();
    $genomelist = array();
    $genomes = $collections['genome']->find();
    foreach ($genomes as $doc) {
        array_push(
            $genomelist,
            array(
                'value'=>$doc['_id'],
                'label'=>$doc['_id'],
            )
        );
    }

    $email=$_SESSION['email'];
    $user = $collections['users']->findOne(array('email'=>$email,'active'=>1), array('_id'=>true));
    $groups_query = $collections['groups']->find(array('admin'=>$user['_id']));
    $db_projects = $sample['project'];
    $db_names = array();
    $db_ids = array();
    foreach ($db_projects as $key => $db_proj) {
        array_push($db_names, $db_proj['name']);
        array_push($db_ids, $db_proj['id'].'');
        $db_projects[$key]['id'] = $db_proj['id'].'';
    }
    array_push($projects, array('value'=>str_replace( "\"", "'",json_encode($db_projects)),'label'=>implode(" --- ", $db_names))); 
    foreach($groups_query as $key=>$group){
        $projects_query = $collections['projects']->find(array('groups.id'=>new MongoId($group['_id'])));
        foreach ($projects_query as $proj_key => $project) {
            if (in_array($project['name'], $db_names)) {
                $x = array_search($project['name'], $db_names);
                unset($db_names[$x]);
                unset($db_ids[$x]);
                unset($db_projects[$x]);
                array_push($projects, array('value'=>str_replace( "\"", "'",json_encode($db_projects)),'label'=>implode(" --- ", $db_names)));
            }            
        }
    }

    $form->onSubmitFunctionServerSide = 'onmanage_sampleSubmit';
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Edit sample info</h4>',
    ));
    $section->addJFormComponentArray(array(
        // new JFormComponentHtml('Under construction'),
        new JFormComponentHidden('sampleid', $sampleid),
        new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),
        new JFormComponentHidden('config_id',  date("Y-m-d_H-i-s")."_".str_replace(".", "_",substr($_SESSION['email'], 0,strpos($_SESSION['email'], '@')))."_".$job_scripts[$type]),
        new JFormComponentSingleLineText('samplename', 'Sample name:', array(
            'width' => 'longest',
            'initialValue' => $sample['name'], 
            'validationOptions' => array('required'),
        )),
        new JFormComponentTextArea('description', 'Description:', array(
            'width' => 'longest',
            'height' => 'medium',
            'initialValue' => $sample['description'], 
        )),
        new JFormComponentDropDown('project', 'Project(s):', 
            $projects,
            array(
                'width' => 'long',
                'tip' => '<p>Select one of your projects.</p>',
        )),
        new JFormComponentDropDown('genome', 'Genome:', 
            $genomelist,
            array(
                'width' => 'long',
                'initialValue' => $sample['genome'],
        ))
    ));
}
elseif ($type == 'remove') {
    $form->onSubmitFunctionServerSide = 'onjobsSubmit';
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Remove sample</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentHtml(
            "<div>Are you sure you want to remove this sample?</div>"
        ),
        new JFormComponentHidden('del', true),
        new JFormComponentHidden('sampleid', $_POST['samples_id']),
        new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),
        new JFormComponentHidden('config_id',  date("Y-m-d_H-i-s")."_".str_replace(".", "_",substr($_SESSION['email'], 0,strpos($_SESSION['email'], '@')))."_".$job_scripts[$type])
    ));
}
elseif ($type == 'map_reads') {
    $form->onSubmitFunctionServerSide = 'onjobsSubmit';
    // Get sample ids
    $project_ids     = isset($_POST['projects_id']) ? json_decode(str_replace("'", "\"",$_POST['projects_id']))  : array();
    $samples_ids     = isset($_POST['samples_id']) ? json_decode(str_replace("'", "\"",$_POST['samples_id']))  : array();
    // Initialize dropdown for selectable files
    $available_files = array(
        array('value' => '','label' => '','disabled' => true)
    );
    $available_pairs = array(
        array('value' => '','label' => '','disabled' => true)
    );
    $available_mappers = array(
        array('value' => '', 'label' => ''),
        array('value'=>'bwa','label'=>'bwa'),
        array('value'=>'bwasw','label'=>'bwasw'),
        array('value'=>'bowtie','label'=>'bowtie')
    );
    $available_platforms = array(
        array('value' => '', 'label' => ''),
        array('value'=>'ILLUMINA','label'=>'ILLUMINA'),
        array('value'=>'SOLID','label'=>'SOLID'),
        array('value'=>'LS454','label'=>'LS454'),
        array('value'=>'HELICOS','label'=>'HELICOS'),
        array('value'=>'PACBIO','label'=>'PACBIO')
    );
    $ref_genome = '';
    $genome_err = 0;
    foreach ($samples_ids as $key => $sample) {
        $samples = $collections['samples']->findOne(array('_id'=>new MongoId($sample)));
        if ($ref_genome != '' && $ref_genome != $samples['genome']) {
            $genome_err = 1;
        }
        $ref_genome = $samples['genome'];    
        if (isset($samples['files'])){
            foreach($samples['files'] as $file){
                $file['sampleid'] = $samples['_id']."";
                $file["samplename"] = $samples['name'];
                if ($file['filetype'] == 'bam') {
                    array_push($available_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['file']
                        )
                    );
                } 
                elseif ($file['filetype'] == 'fastq') {
                    array_push($available_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['file']
                        )
                    );
                    array_push($available_pairs,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['file']
                        )
                    );
                }
            }
        }
    }
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Map reads</h4>',
    ));
    if ($genome_err == 0) {
        $formcomponents = array();       

        $filesdropdown = new JFormComponentDropDown(
            'files',
            '',
            $available_files,
            array(
                'width' => 'long',
                'multiple'=> true,
                'style' => 'word-wrap:break-word;'
            )
        );
        if (!isset($available_files[1])){
            $filesdropdown->style = 'display: none;';
            array_push($formcomponents,
                new JFormComponentHtml(
                    "<div style='clear: both;'>Please associate one or more BAM or FASTQ files with your sample to map reads</div>"
                )
            );
        }
        $i=0;
        array_push(
            $formcomponents,
            $filesdropdown,
            new JFormComponentDropDown(
                'pair',
                '',
                $available_pairs,
                array(
                    'width' => 'long',
                    'multiple'=> true,
                    'style' => 'word-wrap:break-word;',
                    'dependencyOptions' => array(
                        'dependentOn' => 'files',
                        'display' => 'hide',
                        'jsFunction' => '$("#files").find("option:selected").is(":contains(\'fastq\')");'
                    )
                )
            ),
            new JFormComponentDropDown(
                'mapper',
                '',
                $available_mappers,
                array(
                    'width' => 'long',
                    'dependencyOptions' => array(
                        'dependentOn' => 'files',
                        'display' => 'hide',
                        'jsFunction' => '$("#files").find("option:selected").is(":contains(\'fastq\')");'
                    )
                )
            ),
            new JFormComponentHtml(
                "<div style='clear:both;'>Map options</div>"
            ),
            new JFormComponentSingleLineText(
                'mo_key_'.$i,
                '',
                array('emptyValue' => 'Option name')
            ), 
            new JFormComponentSingleLineText(
                'mo_value_'.$i,
                '',
                array(
                    'style'=>'clear:none',
                    'emptyValue' => 'Option value'
                )
            ),
            new JFormComponentHtml(
                '<button counter="'.($i+1).'" class="add_mo_line" style="clear:none;">Add option</button>'
            )
        );
        $i++;
        while($i<=10){
            array_push(
                $formcomponents,
                new JFormComponentHtml(
                    "<div style='clear:both;'></div>"
                ),
                new JFormComponentSingleLineText(
                    'mo_key_'.$i,
                    '',
                    array(
                        'style'=>'display:none',
                        'emptyValue' => 'Option name'
                    )
                ), 
                new JFormComponentSingleLineText(
                    'mo_value_'.$i,
                    '',
                    array(
                        'style'=>'display:none;clear:none',
                        'emptyValue' => 'Option value'
                    )
                ),
                new JFormComponentHtml(
                    '<button id="mo_remove_'.$i.'" counter="'.$i.'" class="remove_mo_line" style="display:none;clear:none;"">Remove</button>'
                ),
                new JFormComponentHtml(
                    '<button counter="'.$i.'" class="add_mo_line" style="display:none;clear:none;">Add option</button>'
                )
            );
            $i++;
        }
        array_push(
            $formcomponents,
            new JFormComponentMultipleChoice('sort', '', array(
                array('value' => 'boolean_true', 'label' => 'Sort', 'checked'=>true))      
            ),
            new JFormComponentMultipleChoice('index', '', array(
                array('value' => 'boolean_true', 'label' => 'Index', 'checked'=>true)),array('style'=>'clear:none')      
            ),
            new JFormComponentMultipleChoice('remove', '', array(
                array('value' => 'boolean_true', 'label' => 'Remove', 'checked'=>true)),array('style'=>'clear:none')      
            ),
            new JFormComponentDropDown(
                'platform',
                '',
                $available_platforms,
                array(
                    'width' => 'long',
                    'dependencyOptions' => array(
                        'dependentOn' => 'mapper',
                        'display' => 'hide',
                        'jsFunction' => '$("#mapper").find("option:selected").is("[value!=\'\']");'
                    )
                )
            ),
            new JFormComponentMultipleChoice('rmdup', '', array(
                array('value' => 'boolean_true', 'label' => 'Remove duplicates', 'checked'=>true))      
            ),
            new JFormComponentMultipleChoice('recal', '', array(
                array('value' => 'boolean_true', 'label' => 'Recalibration', 'checked'=>true)),array('style'=>'clear:none')      
            ),
            new JFormComponentMultipleChoice('local_realignment', '', array(
                array('value' => 'boolean_true', 'label' => 'Local realignment', 'checked'=>true)),array('style'=>'clear:none')      
            ),
            // Add hidden configuration parameters
            new JFormComponentHidden('output','default_output_directory/'),
            new JFormComponentHidden('genomebuild',$ref_genome),
            new JFormComponentHidden('chuncksize',2000000),
            new JFormComponentHidden('projectid',$project_ids[0]),
            new JFormComponentHidden('projectcol','projects'),
            new JFormComponentHidden('samples',''),
            new JFormComponentHidden('samplescol','samples'),
            new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),

            // Add jquery functions for styling
            new JFormComponentHtml(
                '<script>
                $("#files").chosen({placeholder_text_multiple:"Select one or more files...",width: "350px"});
                $("#pair").chosen({placeholder_text_multiple:"Select as many pairs as you did fastq-files...",width: "350px"}); 
                $("#mapper").chosen({placeholder_text_single:"Select a mapper...",width: "350px"});
                $("#platform").chosen({placeholder_text_single:"Select a platform...",width: "350px"});
                $(".jFormWrapperContainer").css("overflow","visible");
                $(".jFormPageWrapper").css("overflow","visible");
                $(".jFormSection").css("overflow","visible");
                $(".add_mo_line").button({icons: {primary: "ui-icon-circle-plus"}});
                $(".remove_mo_line").button({icons: {primary: "ui-icon-circle-minus"}});
                </script>'
            )
        );
    }
    else {
        $formcomponents = array(
            new JFormComponentHtml(
                "<div>Please select samples with the same reference genome!</div>"
            )
        );
    }
    $section->addJFormComponentArray($formcomponents);
}
elseif ($type == 'call_variants') {
    $form->onSubmitFunctionServerSide = 'onjobsSubmit';
    // Get sample ids
    $project_ids     = isset($_POST['projects_id']) ? json_decode(str_replace("'", "\"",$_POST['projects_id']))  : array();
    $samples_ids     = isset($_POST['samples_id']) ? json_decode(str_replace("'", "\"",$_POST['samples_id']))  : array();
    // Initialize dropdown for selectable files
    $available_files = array(
        array('value' => '','label' => '','disabled' => true)
    );
    $available_pairs = array(
        array('value' => '','label' => '','disabled' => true)
    );
    $available_callers = array(
        array('value' => 'unspecified', 'label' => 'No caller selected', 'selected' => true ),
        array('value'=>'GATK v1','label'=>'gatk'),
        array('value'=>'GATK v2 HaplotypeCaller','label'=>'gatk2_haplo'),
        array('value'=>'Samtools','label'=>'samtools'),
        array('value'=>'Somaticsniper','label'=>'somaticsniper')
    );
    $available_platforms = array(
        array('value' => '', 'label' => ''),
        array('value'=>'ILLUMINA','label'=>'ILLUMINA'),
        array('value'=>'SOLID','label'=>'SOLID'),
        array('value'=>'LS454','label'=>'LS454'),
        array('value'=>'HELICOS','label'=>'HELICOS'),
        array('value'=>'PACBIO','label'=>'PACBIO')
    );
    $ref_genome = '';
    $genome_err = 0;
    foreach ($samples_ids as $key => $sample) {
        $samples = $collections['samples']->findOne(array('_id'=>new MongoId($sample)));
        if ($ref_genome != '' && $ref_genome != $samples['genome']) {
            $genome_err = 1;
        }
        $ref_genome = $samples['genome'];    
        if (isset($samples['files'])){
            foreach($samples['files'] as $file){
                $file['sampleid'] = $samples['_id']."";
                if ($file['filetype'] == 'bam') {
                    array_push($available_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['file']
                        )
                    );
                } 
                elseif ($file['filetype'] == 'vcf') {
                    array_push($available_files,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['file']
                        )
                    );
                    array_push($available_pairs,
                        array(
                            'value'=>str_replace( "\"", "'",json_encode($file)),
                            'label'=>$file['file']
                        )
                    );
                }
            }
        }
    }
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Variant calling</h4>',
    ));
    if ($genome_err == 0) {
        $formcomponents = array();       

        $filesdropdown = new JFormComponentDropDown(
            'files',
            '',
            $available_files,
            array(
                'width' => 'long',
                'style' => 'word-wrap:break-word;',
                'multiple'=> true
            )
        );
        if (!isset($available_files[1])){
            $filesdropdown->style = 'display: none;';
            array_push($formcomponents,
                new JFormComponentHtml(
                    "<div style='clear: both;'>Please associate one or more BAM or VCF files with your sample(s)</div>"
                )
            );
        }
        $i=0;
        array_push(
            $formcomponents,
            $filesdropdown,
            new JFormComponentDropDown(
                'bampair',
                '',
                $available_pairs,
                array(
                    'width' => 'long',
                    'style' => 'word-wrap:break-word;',
                    'multiple'=> true,
                    'dependencyOptions' => array(
                        'dependentOn' => 'files',
                        'display' => 'hide',
                        'jsFunction' => '$("#files").find("option:selected").is(":contains(\'bam\')");'
                    )
                )
            ),
            new JFormComponentDropDown(
                'bamtrio',
                '',
                $available_pairs,
                array(
                    'width' => 'long',
                    'style' => 'word-wrap:break-word;',
                    'multiple'=> true,
                    'dependencyOptions' => array(
                        'dependentOn' => 'files',
                        'display' => 'hide',
                        'jsFunction' => '$("#files").find("option:selected").is(":contains(\'bam\')");'
                    )
                )
            ),
            new JFormComponentDropDown(
                'algorithm',
                '',
                $available_callers,
                array(
                    'width' => 'long'
                )
            ),
            new JFormComponentHtml(
                "<div style='clear:both;'>Calling options</div>"
            ),
            new JFormComponentSingleLineText(
                'mo_key_'.$i,
                '',
                array('emptyValue' => 'Option name')
            ), 
            new JFormComponentSingleLineText(
                'mo_value_'.$i,
                '',
                array(
                    'style'=>'clear:none',
                    'emptyValue' => 'Option value'
                )
            ),
            new JFormComponentHtml(
                '<button counter="'.($i+1).'" class="add_mo_line" style="clear:none;">Add option</button>'
            )
        );
        $i++;
        while($i<=10){
            array_push(
                $formcomponents,
                new JFormComponentHtml(
                    "<div style='clear:both;'></div>"
                ),
                new JFormComponentSingleLineText(
                    'mo_key_'.$i,
                    '',
                    array(
                        'style'=>'display:none',
                        'emptyValue' => 'Option name'
                    )
                ), 
                new JFormComponentSingleLineText(
                    'mo_value_'.$i,
                    '',
                    array(
                        'style'=>'display:none;clear:none',
                        'emptyValue' => 'Option value'
                    )
                ),
                new JFormComponentHtml(
                    '<button id="mo_remove_'.$i.'" counter="'.$i.'" class="remove_mo_line" style="display:none;clear:none;"">Remove</button>'
                ),
                new JFormComponentHtml(
                    '<button counter="'.$i.'" class="add_mo_line" style="display:none;clear:none;">Add option</button>'
                )
            );
            $i++;
        }
        array_push(
            $formcomponents,
            new JFormComponentSingleLineText(
                'mincov',
                'Minimal coverage',
                array(
                    // 'emptyValue' => '0.0',
                    'initialValue' => '0'
                )
            ),
            new JFormComponentSingleLineText(
                'mingenotypequal',
                'Minimal genotype quality needed (set to 0 for CLCbio VCF)',
                array(
                    // 'emptyValue' => '0.0',
                    'initialValue' => '0.0'
                )
            ),
            new JFormComponentDropDown(
                'platform',
                '',
                $available_platforms,
                array(
                    'width' => 'long',
                    'dependencyOptions' => array(
                        'dependentOn' => 'files',
                        'display' => 'hide',
                        'jsFunction' => '$("#files").find("option:selected").is(":contains(\'bam\')");'
                    )
                )
            ),
            new JFormComponentMultipleChoice('multisample', '', array(
                array('value' => 'boolean_true', 'label' => 'Multisample', 'checked'=>true))      
            ),
            new JFormComponentMultipleChoice('varrecal', '', array(
                array('value' => 'boolean_true', 'label' => 'Recalibrate variants (only useful for multisample > 5 samples)', 'checked'=>true)),array('style'=>'clear:none')      
            ),
            new JFormComponentMultipleChoice('trimchr', '', array(
                 array('value' => 'boolean_true', 'label' => 'Trim chr-prefix from contig names', 'checked'=>false)),
                 array('style'=>'clear:none')      
            ),
            // Add hidden configuration parameters
            new JFormComponentHidden('output','default_output_directory'),
            new JFormComponentHidden('genomebuild',$ref_genome),
            //new JFormComponentHidden('mincov',0),
            //new JFormComponentHidden('mingenotypequal',0),
            new JFormComponentHidden('projectid',$project_ids[0]),
            new JFormComponentHidden('projectcol','projects'),
            new JFormComponentHidden('samples',''),
            new JFormComponentHidden('samplescol','samples'),
            new JFormComponentHidden('email_to', str_replace( "\"", "'",json_encode(array($_SESSION['email'])))),

            // Add jquery functions for styling
            new JFormComponentHtml(
                '<script>
                $("#files").chosen({placeholder_text_multiple:"Select one or more files...",width: "400px"});
                $("#bampair").chosen({placeholder_text_multiple:"Select bam pairs if you want to do paired variant calling...",width: "400px"});
                $("#bamtrio").chosen({placeholder_text_multiple:"Select bam trios if you want to do trio variant calling...",width: "400px"});
                $("#algorithm").chosen({placeholder_text_single:"Select a caller...",width: "350px"});
                $("#platform").chosen({placeholder_text_single:"Select a platform...",width: "350px"});
                $(".jFormWrapperContainer").css("overflow","visible");
                $(".jFormPageWrapper").css("overflow","visible");
                $(".jFormSection").css("overflow","visible");
                $(".add_mo_line").button({icons: {primary: "ui-icon-circle-plus"}});
                $(".remove_mo_line").button({icons: {primary: "ui-icon-circle-minus"}});
                </script>'
            )
        );
    }
    else {
        $formcomponents = array(
            new JFormComponentHtml(
                "<div>Please select samples with the same reference genome!</div>"
            )
        );
    }
    $section->addJFormComponentArray($formcomponents);
}
elseif ($type == 'register') {
    $dropdown = country_list();
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Register</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentName('name', 'Name:', array(
            'validationOptions' => array('required'),
            'middleInitialHidden' => true,
        )),
        new JFormComponentSingleLineText('email', 'E-mail address:', array(
            'width' => 'long',
            'validationOptions' => array('required', 'email'),
            'tip' => '<p>Enter a valid email address</p>',
        )),
        new JFormComponentSingleLineText('institution', 'Institution:', array(
            'width' => 'longest',
        )),
        new JFormComponentSingleLineText('departement', 'Departement:', array(
            'width' => 'longest',
        )),
        new JFormComponentDropDown('country', 'Country:',
            $dropdown,
            array('width' => 'long','tip' => '<p>Select the country where you are working</p>')          
        ),
        new JFormComponentSingleLineText('password', 'Password:', array(
            'width' => 'long',
            'type' => 'password',
            'validationOptions' => array('required'),
            'tip' => '<p>The password can be any combination of characters<br>We require a minimum of 4 characters and advise 8!</p>',
        )),
        new JFormComponentSingleLineText('pass2', 'Confirm your password:', array(
            'width' => 'long',
            'type' => 'password',
            'tip' => '<p>Please repeat your password</p>',
            'validationOptions' => array('required','matches' => 'password'),
        ))
    ));
}
elseif ($type == 'user') {
    $dropdown = country_list();
    $user = $collections['users']->findOne(array('email'=>$_SESSION['email']));
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Change your personal information</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentName('name', 'Name:', array(
            'validationOptions' => array('required'),
            'middleInitialHidden' => true,
            'initialValues' => array('firstName'=>$user['firstname'],'middleInitial'=>'','lastName'=>$user['lastname']),
        )),
        new JFormComponentSingleLineText('email', 'E-mail address:', array(
            'width' => 'long',
            'validationOptions' => array('required', 'email'),
            'initialValue' => $user['email'], 
        )),
        new JFormComponentSingleLineText('institution', 'Institution:', array(
            'width' => 'longest',
            'initialValue' => $user['institution'],
        )),
        new JFormComponentSingleLineText('departement', 'Departement:', array(
            'width' => 'longest',
            'initialValue' => $user['departement'],
        )),
        new JFormComponentDropDown('country', 'Country:',
            $dropdown,
            array('width' => 'long')
        ),
        new JFormComponentSingleLineText('password', 'Password:', array(
            'width' => 'long',
            'type' => 'password',
            'validationOptions' => array('required'),
            'tip' => 'Enter your old password.',
        )),
        new JFormComponentSingleLineText('new_pass', 'Change password:', array(
            'width' => 'long',
            'type' => 'password',
            'tip' => '<p>The password can be any combination of characters<br>We require a minimum of 4 characters and advise 8!</p>',
        )),
        new JFormComponentSingleLineText('new_pass2', 'Confirm your new password:', array(
            'width' => 'long',
            'type' => 'password',
            'validationOptions' => array('matches' => 'new_pass'),
        ))
    ));
}
elseif ($type == 'contact') {
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Contact us</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentSingleLineText('subject', 'Subject:', array(
            'width' => 'longest',
            'validationOptions' => array('required'),
        )),
        new JFormComponentTextArea('message', 'Message:', array(
            'width' => 'longest',
            'height' => 'medium',
            'validationOptions' => array('required'),
        )),
        new JFormComponentName('name', 'Name:', array(
            'validationOptions' => array('required'),
            'middleInitialHidden' => true,
        )),
        new JFormComponentSingleLineText('email', 'E-mail address:', array(
            'width' => 'long',
            'validationOptions' => array('required', 'email'),
        ))
    ));
}
elseif ($type == 'join_group') {
    $groups_id = isset($_POST['groups_id']) ? $_POST['groups_id']  : $formValues->formSection->groups_id;
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Join group request</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentTextArea('request', 'Message:', array(
            'width' => 'longest',
            'height' => 'medium',
        )),
        new JFormComponentHidden('groups_id', $groups_id),
    ));
}
elseif ($type == 'approve_group') {
    $groups_id = isset($_POST['groups_id']) ? $_POST['groups_id']  : $formValues->formSection->groups_id;
    $user_id = isset($_POST['user_id']) ? $_POST['user_id']  : $formValues->formSection->user_id;
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Join group request</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentMultipleChoice('approve', 'Approve:', 
            array(
                array(
                    'value' => '1',
                    'label' => 'Approve'
                ),
                array(
                    'value' => '0',
                    'label' => 'Reject'
                ),
            ),
            array('multipleChoiceType'=>'radio','tip' => 'Select approve to allow this user access to your group. Reject to deny access.<br> The user will be notified of your decision.')
        ),
        new JFormComponentHidden('groups_id',$groups_id),
        new JFormComponentHidden('user_id',$user_id),
    ));
}
elseif ($type == 'unsubscribe_group') {
    $groups_id = isset($_POST['groups_id']) ? $_POST['groups_id']  : $formValues->formSection->groups_id;
    $group = $collections['groups']->findOne(array('_id'=>new MongoId($groups_id)));
    $user_id = isset($_POST['user_id']) ? $_POST['user_id']  : '';
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Unsubscribe from group: <i>'.$group['name'].'</i></h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentHidden('groups_id',$groups_id),
        new JFormComponentHidden('user_id',$user_id),
        new JFormComponentHidden('unsubscribe',1)
    ));
}
elseif ($type == 'manage_group') {
    $admin_users = array();
    $delete_users = array();
    $groups_id = isset($_POST['groups_id']) ? $_POST['groups_id']  : '';
    $group = $collections['groups']->findOne(array('_id'=>new MongoId($groups_id)));
    if ($group['public'] == 'yes'){
        $checked = true;
    }
    else {
        $checked = false;
    }
    $admin = $collections['users']->findOne(array('_id'=>$group['admin']));
    $user_query = $collections['users']->find();
    foreach($user_query as $key=>$users){
        if (in_array($users['_id'],$group['users']) && in_array($users['_id'],$group['approved']) && $users['email'] != 'GUEST@SEQPLORER.ORG'){  
            if (in_array($users['_id'],$group['users']) && $users['email'] == $admin['email']){
                array_push($admin_users, array('value'=>$users['_id'].'','label'=>$users['email'],'selected' => true,));
            }
            else {
                array_push($admin_users, array('value'=>$users['_id'].'','label'=>$users['email']));
                array_push($delete_users, array('value'=>$users['_id'].'','label'=>$users['email']));
            } 
        }
    }
    if (count($delete_users) == 0) {
        array_push($delete_users, array ('value' => '','label' => 'No other users in this group','disabled' => true,'selected' => true,));
    }
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Group info</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentSingleLineText('groupname', 'Group name:', array(
            'width' => 'longest',
            'initialValue' => $group['name'], 
            'validationOptions' => array('required'),
        )),
        new JFormComponentTextArea('description', 'Description:', array(
            'width' => 'longest',
            'height' => 'medium',
            'initialValue' => $group['description'], 
        )),
        new JFormComponentDropDown('admin', 'Admin:', 
            $admin_users,
            array(
                'width' => 'long',
                'tip' => '<p>Select another admin amongst the members of your group.<br>If your group has no other members, you cannot transfer the adminship.</p>',
                'initialValue' => $admin['email'],
        )),
        new JFormComponentDropDown('delete', 'Remove user:', 
            $delete_users,
            array(
                'width' => 'long',
                'multiple' => true,
                'size' => 3,
                'tip' => '<p>Delete users from your group by selecting one or more email addresses.</p>',
        )),
        new JFormComponentSingleLineText('invite', 'Invite:', array(
            'width' => 'longest',
            'validationOptions'=>array('email'),
            'instanceOptions'=>array('max' => 0),
        )),
        new JFormComponentMultipleChoice('public', '', array(
            array('value' => 'yes', 'label' => 'Set public', 'checked'=>$checked))      
        ),
        new JFormComponentHidden('groups_id',$groups_id),
    ));
}
elseif ($type == 'new_group') {
    $section = new JFormSection($form->id.'Section', array(
        'title' => '<h4>Create a new group</h4>',
    ));
    $section->addJFormComponentArray(array(
        new JFormComponentSingleLineText('groupname', 'Group name:', array(
            'width' => 'longest',
            'validationOptions' => array('required'),
        )),
        new JFormComponentTextArea('description', 'Description:', array(
            'width' => 'longest',
            'height' => 'medium',
        )),
        new JFormComponentSingleLineText('invite', 'Invite:', array(
            'width' => 'longest',
            'validationOptions'=>array('email'),
            'instanceOptions'=>array('max' => 0),
        )),
        new JFormComponentMultipleChoice('public', '', array(
            array('value' => 'yes', 'label' => 'Set public'))
        ),
    ));
}
elseif ($type == 'forgot') {
    $section = new JFormSection($form->id.'Section', array(
            'title' => '<h4>Forgot password</h4>',
        ));
        $section->addJFormComponentArray(array(
            new JFormComponentSingleLineText('email', 'E-mail address:', array(
                'width' => 'long',
                'validationOptions' => array('required', 'email'),
               'tip' => '<p> Provide your login email adress</p>',
            ))
        ));
}

// add the section to the form
$form->addJFormSection($section);
// process the request
$form->processRequest();


////////////////////////////////
// SUCCESS FUNCTIONS
////////////////////////////////

// Set the function for a successful form submission
function onlogsSubmit($formValues){
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    if ($formValues->complete_job != ''){
        $job_id = $formValues->complete_job;
    }
    elseif ($formValues->running_job != '') {
        $job_id = $formValues->running_job;
    }
    elseif ($formValues->error_job != '') {
        $job_id = $formValues->error_job;
    }
    $success = "var html = \"<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a><div id='logs_popup'><h2>Logs</h2><div id='splitview'><div class='leftside' id='logs_tree'></div><div class='rightside' id='messages'></div></div></div>\";";
    $success .= " $('#showhide').html(html);";
    $success .= "$('#splitview').simplesplitview();";
    $success .= "$('#logs_tree').jstree({'html_data' : {'ajax' : {'url' : 'query/logs.php','data' : { 'jobid' : '".$job_id."'}}},'themes' : {'theme' : 'classic','icons' : false},'plugins' : [ 'themes', 'html_data' ]});";
    $success .= "$('#showhide').css({height:$('#splitview').height()});";
    $success .= "$('#showhide').css({width:$('#splitview').width()});";
    
    // $response = array(
    //     'failureNoticeHtml' => $formValues->log
    // );
    $response = array(
                'successJs' => $success
            );
    return $response;
}
function onloginSubmit($formValues){
    $db = connect_mongo();
    $collections = get_collections($db);

    $formValues = $formValues->formSection;

    $userinfo = $collections['users']->findOne(array('email'=>strtoupper($formValues->email)));
    if (!$userinfo) {
        // wrong user, focus on user input field
        $response = array(
            'failureNoticeHtml' => 'Unknown user.',
            'failureJs' => "$('#email').val('').focus(); $('#password').val('')"
        );
    }

    else {
        $dbpassword = $userinfo['password'];
        $dbstatus = $userinfo['active'];
        $user_fn = $userinfo['firstname'];
        $user_ln = $userinfo['lastname'];

        if ($formValues->password != $dbpassword) {
            // wrong password, focus on password input field
            $response = array(
                'failureNoticeHtml' => 'Invalid password.',
                'failureJs' => "$('#password').val('').focus();"
            );
        } 
        else if (isset($dbstatus)){
            // User and password OK: login, create session
            $_SESSION['email'] = strtoupper($formValues->email);
            $_SESSION['password'] = $formValues->password;
            $_SESSION['active'] = $dbstatus;   
            $response = array(
                'successJs' => "messageFade('<p>Welcome, ".$user_fn." ".$user_ln."</p>');"
            );
        }
        else {
            // user exists, valid password but account not validated yet
            $response = array(
                'failureNoticeHtml' => 'Your profile has not been activated yet. Please check your email inbox for the confirmation link.'
            );
        }
    }
    return $response;
}
function onigvSubmit($formValues){
    $formValues = $formValues->formSection;
    $link = "";
    foreach ($formValues->files as $file) {
        $link .= $file.",";
    }
    $link = substr($link, 0, -1);
    // appRequest(port, dataUrl, genomeID, mergeFlag, locusString, trackName)
    // $response = array('failureNoticeHtml' => $link);
    $response = array(
        'successJs' => 'console.log("'.$link.'");appRequest(60151, "'.$link.'", "", "true");setTimeout(function(){$("#showhide").fadeOut("slow");$("#showhide").html();},2000);'
    );
    return $response;
}
function onshinySubmit($formValues){
    $db = connect_mongo();
    $collections = get_collections($db);
    $credentials = read_credentials($_SESSION['config']);
    // Collect values
    $formValues = $formValues->formSection;
    // $link = $credentials->site->url.'shiny/';
    $link = 'https://brenner.ugent.be/shiny/';
    

    $info = $collections['plots']->findOne(array('_id'=>new MongoId($formValues->plot)));
    if ($info['cumulativeid']) {
        $link .= 'coveragegraph/#dataset='.$formValues->plot;
        // $link .= 'coveragegraphs/#dataset='.$formValues->plot;
    }
    else {
        $link .='defaultgraphs/#dataset='.$formValues->plot;
    }
    $response = array(
                'successJs' => 'showPlot("'.$info['name'].'","'.$link.'");'
            );
    // $response = array('failureNoticeHtml' => '<p'.$link.'</p>');
    return $response;

}
function onload_filterSubmit($formValues){
    // Collect values
    $formValues = $formValues->formloadFilter;
    // curl get naar backend als filter ingeladen dus als id als attr aan knopt hangt
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['api'].'/filter/'.$formValues->load_filter);
    $resp = curl_exec($ch);
    $response = json_decode($resp);

    $response = array('successJs' => "newAdvancedFilter ( '$formValues->filter_name', '$formValues->load_filter', '".json_encode((array)$response->where)."' );$('#filter_opt').toggle();");
    // $response = array('failureNoticeHtml' => '<p>Something went wrong. Please try again.</p>');
    return $response;
}
function onsave_filterSubmit($formValues){
    $formValues = $formValues->formsaveFilter;
    $data['name']=$formValues->save_filter;
    $name = $data['name'];
    $data = json_encode($data);
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
    curl_setopt($ch, CURLOPT_PROXY, null);
    curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['api'].'/filter/'.$name.'/'.$formValues->filter_id);
    //curl_setopt($ch, CURLOPT_URL, 'http://localhost:3939/filter/52974b7f7412df2165050000');
    $resp = curl_exec($ch);
    $response = array(
        'successJs' => "$('#filter_opt').toggle();",
        'successPageHtml' => "Your filter has been saved as <b>".$name."</b>."
    );
    //$response = array('failureNoticeHtml' => '<p>Something went wrong. Please try again.</p>','failureJs'=> "console.log('".$_SESSION['credentials']['site']['api']."/filter/".$name."/".$formValues->filter_id."')");
    return $response;
}
function onload_viewSubmit($formValues){
    // Collect values
    $formValues = $formValues->formloadView;

    $response = array('successJs' => "applyView ( '$formValues->view_name','$formValues->load_view');$('#view_opt').toggle();");
    return $response;
}
function onsave_viewSubmit($formValues){
    $formValues = $formValues->formsaveView;
    $data['name']=$formValues->save_view;
    $data = json_encode($data);
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
    curl_setopt($ch, CURLOPT_PROXY, null);
    curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['api'].'/view/'.$data['name'].'/'.$formValues->view_id);
    //curl_setopt($ch, CURLOPT_URL, 'http://localhost:3939/filter/52974b7f7412df2165050000');
    $resp = curl_exec($ch);
    $response = array(
        'successJs' => "$('#view_opt').toggle();",
        'successPageHtml' => "Your view has been saved as <b>".$data['name']."</b>."
    );
    $response = array('failureNoticeHtml' => '<p>Something went wrong. Please try again.</p>');
    return $response;
}
function oncreate_viewSubmit($formValues){
    $formValues = $formValues->formsaveView;
    $db = connect_mongo();
    $collections = get_collections($db);

    $view = array();
    if ($formValues->save_view){
        $view['columns'] = json_decode(str_replace("'", "\"",$formValues->col_string));
        $view['collection'] = $formValues->collection;
        $view['dom'] = $formValues->dom;
        $view['name'] = '';
        $view['projects'] = json_decode(str_replace("'", "\"", $formValues->projects_id));
        $view['restrict'] = json_decode(str_replace("'", "\"",$formValues->restrict));

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($view));
        curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['api'].'/view');
        $resp = curl_exec($ch);
        $response = json_decode($resp);
        $response = array(
            'successJs' => "$('#view_opt').toggle();applyView ( 'NO NAME','$response->_id');"
        );
    }
    else {
        $response = array('failureNoticeHtml' => '<p>Something went wrong. Please try again.</p>');
    }
    return $response;
}
function onadd_projectSubmit($formValues){
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    $group_name = $collections['groups']->findOne(
        array(
            '_id'=>new MongoId($formValues->groupid)
        )
    );

    $create_project = $collections['projects']->insert(
        array(
            'description'=>$formValues->description,
            'groups'=>array(
                array(
                    'id'=>new MongoId($formValues->groupid),
                    'name'=> $group_name['name']
                )
            ),
            'name'=>$formValues->projectname
        )
    );
    
    $response = array(
        'successJs' => "messageFade('<p>Your project ".addslashes($formValues->projectname)." has been added.</p>');"
    );
    return $response;
}
function onmanage_projectSubmit($formValues){
    $db = connect_mongo();
    $collections = get_collections($db);

    $formValues = $formValues->formSection;
    $find_query = $collections['projects']->findOne(array('_id'=>new MongoId($formValues->projects_id)));
    $group_name = $collections['groups']->findOne(
        array(
            '_id'=>new MongoId($formValues->group)
        )
    );
    $update_query = $collections['projects']->update(
        array('_id'=>new MongoId($formValues->projects_id)),
        array(
            '$set'=> array(
                'description'=>$formValues->description,
                'groups'=>array(
                    array(
                        'id'=>new MongoId($formValues->group),
                        'name'=> $group_name['name']
                    )
                ),
                'name'=>$formValues->projectname
            )
        )
    );    
    $response = array(
        'successJs' => "messageFade('<p>The details of your project ".addslashes($formValues->projectname)." have been modified.</p>');"
    );
    return $response;
}
function onadd_sampleSubmit($formValues){
    $db = connect_mongo();
    $collections = get_collections($db);

    // get sample info
    $sampleValues = $formValues->formSampleinfo;

    // get files info
    $filesValues = $formValues->formSection;

    // convert files section array-notation
    // array(array('type'=>..., 'path'=>..., 'host'=>...),array('type'=>..., 'path'=>..., 'host'=>...),...)
    $files_array = array();
    foreach ($filesValues as $key => $row) {
        // collect the name of the column, i.e. 'column', 'operator' or 'value'
        //$temp_key = substr($key,7);
        if (preg_match('/([a-z]+)([0-9]+)$/', $key,$matches)){
            if (!isset($files_array[$matches[2]])) {
                $files_array[$matches[2]] = array();
            }
            if (!isset($files_array[$matches[2]][$matches[1]])) {
                $files_array[$matches[2]][$matches[1]] = array();
            }
            $files_array[$matches[2]][$matches[1]] = $row;
        }
    }

    $files = array();
    foreach ($files_array as $file){
        if ($file['samplefiletype']){
            $newfile = array();
            foreach ($file as $key => $value) {
                if ($value !== ''){
                    if ($key == 'samplefiletype'){
                        $key = 'type';
                    } elseif ($key == 'https') {
                        $key = 'pass';
                    }
                    $newfile[$key] = $value;                    
                }
            }
            array_push($files, $newfile);
        }
    }

    $create_sample = $collections['samples']->insert(
        array(
            'description'=>$sampleValues->description,
            'project'=>array(
                array(
                    'id'=>new MongoId($sampleValues->projectid),
                    'name'=> $_SESSION['projects'][$sampleValues->projectid]['name']
                )
            ),
            'genome' => $sampleValues->genomebuild,
            'name'=>$sampleValues->samplename,
            'files' => $files
        )
    );

    $response = array(
        'successJs' => "messageFade('<p>Sample ".addslashes($sampleValues->samplename)." has been added.</p>');"
    );

    return $response;
}
function onmanage_sampleSubmit($formValues){
    $db = connect_mongo();
    $collections = get_collections($db);

    $sampleValues = $formValues->formSection;
    $db_sample = $collections['samples']->findOne(
        array(
            '_id'=>new MongoId($sampleValues->sampleid)
        )
    );

    $set_array = array();
    $set_array['description'] = $sampleValues->description;
    // $set_array['name'] = $sampleValues->samplename;
    $set_array['genome'] = $sampleValues->genome;  
    $projects = json_decode(str_replace( "'", '"',$sampleValues->project),true);
    foreach ($projects as $key => $proj) {
        $projects[$key]['id'] = create_mongo_id($proj['id']);
    }
    // $set_array['project'] = $projects;
    if ($db_sample['name'] == $sampleValues->samplename) {
        $update_query = $collections['samples']->update(
            array(
                '_id'=>new MongoId($sampleValues->sampleid)
            ),
            array(
                '$set'=> $set_array
            )
        ); 
        $response = array(
            'successJs' => "messageFade('<p>The details of your sample ".addslashes($sampleValues->samplename)." have been modified.</p>');"
        ); 
    }
    else {
        // update sample_only values
        $update_query = $collections['samples']->update(
            array(
                '_id'=>new MongoId($sampleValues->sampleid)
            ),
            array(
                '$set'=> $set_array
            )
        ); 
        // update sample name (samples & variants)
        $config = $_SESSION['credentials']['backend']['job_config'];
        $config['config_id'] = $sampleValues->config_id;
        $config['email_to'] = $sampleValues->email_to;
        $config['sampleid'] = $sampleValues->sampleid;
        $config['samplename'] = $sampleValues->samplename;
        // use global to collect data from global variables in function
        global $type, $job_scripts;
        $data = array('script'=>$job_scripts[$type].'.pl','config'=>json_encode($config)); 
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['api'].'/qsub');
        curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        $resp = curl_exec($ch);
        curl_close($ch); 
        $answer = json_decode($resp);
        if (isset($answer->config_id)){
            $response = array(
                'successJs' => "messageFade('<p>Your job (".$answer->config_id.") has been submitted successfully</p>');"
            );
        }
        else {
            $response = array('failureNoticeHtml' => 'Something went wrong. Please try again later.');
        }
    } 
    $response = array('failureNoticeHtml' => 'Something went wrong. Please try again later.');
    return $response;
}
function onjobsSubmit($formValues){
    $formValues = $formValues->formSection;
    // var_dump($formValues);
    $config = $_SESSION['credentials']['backend']['job_config'];
    foreach ($formValues as $key => $value) {
        if (is_array($value)){
            if (count($value) == 1 && $value[0] == "boolean_true"){
                $config[$key] = true;
            }
            else {
               foreach ($value as $val) {
                    $json_val = json_decode(str_replace( "'", '"',$val));
                    if ($json_val) {
                        $config[$key][] = $json_val;
                    } else {
                       $config[$key][] = $val;
                    }   
                } 
            }   
        }
        else {
            if (preg_match('/^mo_/', $key)){
                if (preg_match('/^mo_key_/', $key) && $value !='') {
                   preg_match('/(^mo_key_)(\d+)/', $key,$matches);
                    $val_string = 'mo_value_'.$matches[2];
                    $config[$value] = $formValues->$val_string;
                }    
            }
            else {
                $json_value = json_decode(str_replace( "'", '"',$value));
                if ($json_value) {
                    $config[$key] = $json_value;
                } else {
                    if (strpos($value, ',')){
                        $value = preg_replace( '/\s+/', '', $value);
                        $array_value = explode(",", $value);
                        $value = $array_value;
                    }
                    $config[$key] = $value;
                }
            }  
        }  
    }

    // use global to collect data from global variables in function
    global $type, $job_scripts;

    $data = array('script'=>$job_scripts[$type].'.pl','config'=>json_encode($config)); 

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $_SESSION['credentials']['site']['api'].'/qsub');
    curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    $resp = curl_exec($ch);
    //var_dump($resp);
    curl_close($ch); 
    $answer = json_decode($resp);
    if (isset($answer->config_id)){
        $response = array(
            'successJs' => "messageFade('<p>Your job (".$answer->config_id.") has been submitted successfully</p>');"
        );
    }
    else {
        $response = array('failureNoticeHtml' => 'Something went wrong. Please try again later.', 'failureJs' => "console.log('".json_encode($config)."')");
    }
    return $response;
}
function onregisterSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $url = $credentials->site->url;
    $domain = $credentials->site->domain;
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    // set email to all upercase
    $email = strtoupper($formValues->email);
    $check_result = $collections['users']->find(array('email'=>$email))->count();
    // username must be unique, else: error
    if ($check_result > 0) {
        $response = array('failureNoticeHtml' => 'Sorry, the email address '.$email.' already is in use.', 'failureJs' => "$('#email').val('').focus();$('#password').val('')");
    } else {
        $date = date('Y-m-d H:i:s');
        // everything is correct, we create a new user
        $insert_arr = array('email'=>$email,'password'=>$formValues->password,'firstname'=>$formValues->name->firstName,'lastname'=>$formValues->name->lastName,'institution'=>$formValues->institution,'departement'=>$formValues->departement,'country'=>$formValues->country,'active'=>0,'member_since'=>$date);
        $user_insert = $collections['users']->insert($insert_arr);
        $groups_insert = $collections['groups']->insert(array('admin'=>$insert_arr['_id'],'approved'=>array($insert_arr['_id']),'description'=>'Private group of user '.$email,'name'=>'Private','public'=>'no','users'=>array($insert_arr['_id'])));
        $public_update = $collections['groups']->update(array('name'=>'Public'),array('$addToSet'=>array('approved'=>$insert_arr['_id'],'users'=>$insert_arr['_id'])));
        // // if a user was invited a group will be posted, we add the user to that group
        // if ($formValues->group != ''){       
        //     $invited_groups_insert = $collections['groups']->update(array('name'=>$formValues->group),array('$addToSet'=>array('approved'=>$insert_arr['_id'],'users'=>$insert_arr['_id'])));
        // }
    
        // send cofirmation e-mail
        $to      = $email;
        $subject = '[seqplorer] Complete your registration';
        $message = "Dear ".$formValues->name->firstName." ".$formValues->name->lastName.",\n\nThank you for submitting your registration information to the seqplorer website. \nTo complete your registration, and to continue on with your request, please click on this link to activate your account:
                    \n".$url."complete_registration.php?id=".$insert_arr['_id']."\n\nBest regards,\n\nThe seqplorer-Team\ninfo@$domain";               
        $headers = 'From: info@'.$domain . "\r\n" .
                    'Reply-To: info@'.$domain . "\r\n" .
                    'X-Mailer: PHP/' . phpversion();
    
        mail($to, $subject, $message, $headers);
        $response = array('successJs' => 'messageFade("<p>Thank you for registering. You will receive a verification mail shortly.<br>After this verification you can log in.</p>");');
        
    }
    return $response;
}
function onuserSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;

    $user_update_array = array('$set'=>array('email'=>strtoupper($formValues->email),'firstname'=>$formValues->name->firstName,'lastname'=>$formValues->name->lastName,'institution'=>$formValues->institution,'departement'=>$formValues->departement,'country'=>$formValues->country));
        // d41d8cd98f00b204e9800998ecf8427e = md5("") --> used when no new password is given, but md5 is triggered
        if ($formValues->new_pass != 'd41d8cd98f00b204e9800998ecf8427e' || $formValues->new_pass != ''){
            $user_update_array = array('$set'=>array('email'=>strtoupper($formValues->email),'password'=>$formValues->new_pass,'firstname'=>$formValues->name->firstName,'lastname'=>$formValues->name->lastName,'institution'=>$formValues->institution,'departement'=>$formValues->departement,'country'=>$formValues->country));
        }
        $update_user = $collections['users']->update(array('email'=>$formValues->email),$user_update_array);

    $response = array('successJs' => 'messageFade("<p>Your information has been updated successfully.</p>");');
    return $response;
}
function oncontactSubmit($formValues){
    $formValues = $formValues->formSection;
    if(!empty($formValues->name->middleInitial)) {
        $name = $formValues->name->firstName.' '.$formValues->name->middleInitial.' '.$formValues->name->lastName;
    }
    else {
        $name = $formValues->name->firstName.' '.$formValues->name->lastName;
    }
    $subject =$formValues->subject; 
    $message=$formValues->message; 
    $mail_from=$formValues->email; 
    $header="from: ".$name." <$mail_from>";    
    $to ='jasper.anckaert@ugent.be';
    $send_contact=mail($to,$subject,$message,$header);
    $response = array('successJs' => 'messageFade("<p>Thanks for contacting us</p><p>Your message has been successfully sent.</p>");');
    return $response;
}
function onjoin_groupSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $url = $credentials->site->url;
    $domain = $credentials->site->domain;
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    $user_select = $collections['users']->find(array('email'=>$_SESSION['email']));
    // Update DB --> add user(s) to group(s)
    foreach($user_select as $key=>$user){
        $user_insert = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$addToSet'=>array('users'=>$user['_id'])));
    }
    $groups_admin=$collections['groups']->find(array('_id'=>new MongoId($formValues->groups_id)));
    foreach ($groups_admin as $key=>$admin_data){
        $admin_select = $collections['users']->find(array('_id'=>$admin_data['admin']));
        $groupname = $admin_data['name'];
        foreach ($admin_select as $key=> $admin_email){
            $admin = $admin_email['email'];
        }
    }
    // Send e-mail notification to group admin
    $to      = $admin;
    $subject = '[seqplorer] Request to join group: '.$groupname;
    $message = "Dear group admin,\n\nUser ".$_SESSION['email']." has requested to be granted access to group ".$groupname.":\nPlease log in to the ".$url." site to approve this request\n\nThis was the request message:\n".$formValues->request."\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";
    $headers = 'From: info@'.$domain . "\r\n" .
                    'Reply-To: info@'.$domain . "\r\n" .
                    'X-Mailer: PHP/' . phpversion();    
    mail($to, $subject, $message, $headers);
    $response = array('successJs' => 'messageFade("<p>Your request was sent to the group administrator.</p>");'); 
    return $response;
}
function onapprove_groupSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $url = $credentials->site->url;
    $domain = $credentials->site->domain;
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    $user = $collections['users']->findOne(array('_id'=>new MongoId($formValues->user_id)));
    $email = $user['email'];
    $group = $collections['groups']->findOne(array('_id'=>new MongoId($formValues->groups_id)));
    $groupname = $group['name'];
    if ($formValues->approve == 1){     
        // Add userid to group (DB update)
        $approve = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$addToSet'=>array('approved'=>new MongoId($user['_id']))));
        
        // Send e-mail confirmation to added user
        $to      = $email;
        $subject = '[seqplorer] Request to join group:'.$groupname;
        $message = "Dear ".$user['firstname']." ".$user['lastname'].",\n\nYou have been granted access to the group: ".$groupname.".\n\nLogin to the seqplorer website to see the projects shared by this group\n\n".$url."\n\nKind regards,\nThe seqplorer-Team\ninfo@$domain";
        $headers =  'From: info@'.$domain . "\r\n" .
                    'Reply-To: info@'.$domain . "\r\n" .
                    'X-Mailer: PHP/' . phpversion();

        mail($to, $subject, $message, $headers); 
        $response = array('successJs' => '$("#showhide").html("You have approved the request of <i>'.$email.'</i> to join group: <i>'.$groupname.'</i></p>");setTimeout(function(){$("#showhide").fadeOut("slow");$("#showhide").html();},2000);reload("1000");'); 
    }
    elseif ($formValues->approve == 0) {
        $reject = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$pull'=>array('users'=>new MongoId($formValues->user_id))));        
        // Send e-mail notification to user
        $to      = $email;
        $subject = '[seqplorer] Request to join group:'.$groupname;
        $message = "Dear ".$user['firstname']." ".$user['lastname'].",\n\nYour request for group access to group: ".$groupname." was rejected\n\nKind regards,\nThe seqplorer-Team\ninfo@$domain";
        $headers =  'From: info@'.$domain . "\r\n" .
                    'Reply-To: info@'.$domain . "\r\n" .
                    'X-Mailer: PHP/' . phpversion();

        mail($to, $subject, $message, $headers);
        $response = array('successJs' => 'messageFade("You have rejected the request of <i>'.$email.'</i> to join group: <i>'.$groupname.'</i></p>");'); 
    }
    return $response;
}
function onunsubscribe_groupSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $url = $credentials->site->url;
    $domain = $credentials->site->domain;
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    // DB update ==> delete userid from group
    $reject = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$pull'=>array('users'=>new MongoId($formValues->user_id),'approved'=>new MongoId($formValues->user_id))));
    $group=$collections['groups']->findOne(array('_id'=>new MongoId($formValues->groups_id)));
    $admin = $collections['users']->findOne(array('_id'=>$group['admin']));
    $user = $collections['users']->findOne(array('_id'=>new MongoId($formValues->user_id)));     
    // Send e-mail notification to group admin
    $to      = $admin['email'];
    $subject = '[seqplorer] Unsubscription from group: '.$groupname;
    $message = "Dear ".$admin['firstname']." ".$admin['lastname'].",\n\nUser ".$user['firstname']." ".$user['lastname']." unsubscribed from your group ".$group['name'].".\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";

    $headers = 'From: info@'.$domain . "\r\n" .
               'Reply-To: info@'.$domain . "\r\n" .
               'X-Mailer: PHP/' . phpversion();
    
    mail($to, $subject, $message, $headers);
    $response = array('successJs' => 'messageFade("<p>You unsubscribed from group '.$group["name"].'</i></p>");');
    return $response;
}
function onmanage_groupSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $url = $credentials->site->url;
    $domain = $credentials->site->domain;
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    if ($formValues->public[0] == null){
        $formValues->public[0] = 'no';
    }
    $udpate = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$set'=>array('name'=>$formValues->groupname,'description'=>$formValues->description,'public'=>$formValues->public[0])));
    $update_projects = $collections['projects']->update(array('groups.id'=>new MongoId($formValues->groups_id)),array('$set'=>array('groups.$.name'=>$formValues->groupname)));
    // Get group admin from database    
    $group=$collections['groups']->findOne(array('_id'=>new MongoId($formValues->groups_id)));
    $admin = $collections['users']->findOne(array('_id'=>$group['admin']));
    $new_admin = $collections['users']->findOne(array('_id'=>new MongoId($formValues->admin)));
    // Assign new group admin   
    if ($formValues->admin != $admin['_id'].''){
        $to = $new_admin['email'];
        $subject = "[seqplorer] ".$formValues->groupname." admin ";
        $message = "Dear ".$new_admin['email'].",\n\n".$admin['firstname']." ".$admin['lastname']." has assigned you as admin of the ".$formValues->groupname."-group.\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";
                    
        $headers = 'From: info@'.$domain. "\r\n" .
                    'Reply-To: info@'.$domain. "\r\n" .
                    'X-Mailer: PHP/' . phpversion();
        mail($to, $subject, $message, $headers);
        $udpate = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$set'=>array('admin'=>new MongoId($formValues->admin))));
    }
    // Invite others to join group
    if (count($formValues->invite) >= 1 && $formValues->invite[0] != ''){
        // Make seperate values of each invite            
        for ($i=0;$i<count($formValues->invite);$i++){
            if (count($formValues->invite) > 1) {
                $invite = $formValues->invite[$i];
            }
            else {
                $invite = $formValues->invite;
            }
            $invite_query = $collections['users']->find(array('email'=>strtoupper($invite)));       
            $invite_check = $invite_query->count();
            // Unknown email, invite people to join NXT-VAT
            if ($invite_check == 0) {
                $to      = $invite;
                $subject = '[seqplorer] Invitation to seqplorer';
                $message = "Dear ".$invite.",\n\n".$admin['firstname']." ".$admin['lastname']." wants you to register to NXT-Variant Tracker in order to join his group and gain access to his project data.\nYou can do so by clicking the following link:
                            \n".$url."registration_page.php?group=".$formValues->groups_id."\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";
                            
                $headers = 'From: info@'.$domain . "\r\n" .
                            'Reply-To: info@'.$domain . "\r\n" .
                            'X-Mailer: PHP/' . phpversion();
                mail($to, $subject, $message, $headers); 
            } 
            else {
                foreach($invite_query as $key=>$invite_data){
                    $invite_id = $invite_data['_id'];
                    $invite_fn = $invite_data['firstname'];
                    $invite_ln = $invite_data['lastname'];
                }
                // email known, invite user(s) to join group
                $to      = $invite;
                $subject = '[seqplorer] Invitation to seqplorer group';
                $message = "Dear ".$invite_fn." ".$invite_ln.",\n\n".$admin['firstname']." ".$admin['lastname']." added you to his group ".$formValues->groupname." on the seqplorer website in order for you to gain access to his project data.\nYou can unsubscribe at any time on the website.\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";
                            
                $headers = 'From: info@'.$domain . "\r\n" .
                            'Reply-To: info@'.$domain . "\r\n" .
                            'X-Mailer: PHP/' . phpversion();
                mail($to, $subject, $message, $headers);
                // create an inactive group link for this user
                $adduser = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$addToSet'=>array('users'=>$invite_id,'approved'=>$invite_id)));
            }
             
        }
    }
    // Remove group member(s)
    if (count($formValues->delete) >= 1 && $formValues->delete[0] != ''){
        foreach ($formValues->delete as $key => $value){
            $deleteuser = $collections['groups']->update(array('_id'=>new MongoId($formValues->groups_id)),array('$pull'=>array('users'=>new MongoId($value),'approved'=>new MongoId($value))));
            $user = $collections['users']->findOne(array('_id'=>new MongoId($value)));
            // Send email notification to deleted user
            $to      = $user['email'];
            $subject = '[NXVAT] Deletion from seqplorer group';
            $message = "Dear ".$user['firstname']." ".$user['lastname'].",\n\n".$admin['firstname']." ".$admin['lastname']." deleted you from his group ".$formValues->groupname." on the seqplorer website. You no longer have access to his project data.\nYou can send a request to join this group again at any time on the website.\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";                       
            $headers = 'From: info@'.$domain . "\r\n" .
                       'Reply-To: info@'.$domain . "\r\n" .
                       'X-Mailer: PHP/' . phpversion();
            mail($to, $subject, $message, $headers);
        }
    }
    $response = array('successJs' => 'messageFade("<p>Your group settings have been updated successfully.</i></p>");');
    return $response;
}
function onnew_groupSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $url = $credentials->site->url;
    $domain = $credentials->site->domain;
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    if ($formValues->public[0] == null){
        $formValues->public[0] = 'no';
    }
    $group_check = $collections['groups']->find(array('name'=>$formValues->groupname))->count();
    if ($group_check != 0) {
        $response = array('failureNoticeHtml' => 'This group already exist in our database.', 'failureJs' => "$('#groupname').val('').focus();");
    } 
    else {
        // create the group
        $user = $collections['users']->findOne(array('email'=>$_SESSION['email']));
        $create_group = array('admin'=>$user['_id'],'approved'=>array($user['_id']),'description'=>$formValues->description,'name'=>$formValues->groupname,'public'=>$formValues->public[0],'users'=>array($user['_id']));
        $collections['groups']->insert($create_group);
        $groupid = $create_group['_id'].'';
        // Invite others to join group
        if (count($formValues->invite) >= 1 && $formValues->invite[0] != ''){
            // Make seperate values of each invite            
            for ($i=0;$i<count($formValues->invite);$i++){
                if (count($formValues->invite) > 1) {
                    $invite = $formValues->invite[$i];
                }
                else {
                    $invite = $formValues->invite;
                }
                $invite_query = $collections['users']->find(array('email'=>strtoupper($invite)));       
                $invite_check = $invite_query->count();
                // Unknown email, invite people to join NXT-VAT
                if ($invite_check == 0) {
                    $to      = $invite;
                    $subject = '[seqplorer] Invitation to seqplorer';
                    $message = "Dear ".$invite.",\n\n".$user['firstname']." ".$user['lastname']." wants you to register to NXT-Variant Tracker in order to join his group and gain access to his project data.\nYou can do so by clicking the following link:
                                \n".$url."registration_page.php?group=".$groupid."\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";
                                
                    $headers = 'From: info@'.$domain . "\r\n" .
                                'Reply-To: info@'.$domain . "\r\n" .
                                'X-Mailer: PHP/' . phpversion();
                    mail($to, $subject, $message, $headers); 
                } 
                else {
                    foreach($invite_query as $key=>$invite_data){
                        $invite_id = $invite_data['_id'];
                        $invite_fn = $invite_data['firstname'];
                        $invite_ln = $invite_data['lastname'];
                    }
                    // email known, invite user(s) to join group
                    $to      = $invite;
                    $subject = '[seqplorer] Invitation to seqplorer group';
                    $message = "Dear ".$invite_fn." ".$invite_ln.",\n\n".$user['firstname']." ".$user['lastname']." added you to his group ".$formValues->groupname." on the seqplorer website in order for you to gain access to his project data.\nYou can unsubscribe at any time on the website.\n\nKind regards,\n\nThe seqplorer-Team\ninfo@$domain";
                                
                    $headers = 'From: info@'.$domain . "\r\n" .
                                'Reply-To: info@'.$domain . "\r\n" .
                                'X-Mailer: PHP/' . phpversion();
                    mail($to, $subject, $message, $headers);
                    // create an inactive group link for this user
                    $adduser = $collections['groups']->update(array('_id'=>new MongoId($groupid)),array('$addToSet'=>array('users'=>$invite_id,'approved'=>$invite_id)));
                }
                 
            }
        }
        $response = array('successJs' => 'messageFade("<p>Your group has been created successfully.<br>Any invitations have been sent.</p>");');
    }
    return $response;
}
function onforgotSubmit($formValues){
    $credentials = read_credentials($_SESSION['config']);
    $url = $credentials->site->url;
    $domain = $credentials->site->domain;
    $db = connect_mongo();
    $collections = get_collections($db);
    $formValues = $formValues->formSection;
    $query = $collections['users']->find(array('email'=>strtoupper($formValues->email)));
    $query_count = $query->count();
    if ($query_count == 0) {
        $response = array('failureNoticeHtml' => 'Unknown user.', 'failureJs' => "$('#email').val('').focus();$('#password').val('')");
    } 
    // User exists --> continue
    else {
        $user = $collections['users']->findOne(array('email'=>strtoupper($formValues->email)));
        $new_pass = generatePassword();
        // Change db-entry
        $collections['users']->update(array("email"=>strtoupper($formValues->email)),array('$set'=>array("password"=>md5($new_pass))));
        
        // send cofirmation e-mail
        $to      = $formValues->email;
        $subject = '[seqplorer] Reset your NVT password';
        $message = "Dear ".$user['firstname']." ".$user['lastname'].",\n\nYour password for the seqplorer website has been reset to:\n\n".$new_pass."\n\nBe sure to change your password after you logged in.\n\nBest regards,\n\nThe seqplorer-Team\ninfo@$domain";               
        $headers = 'From: info@'.$domain . "\r\n" .
                    'Reply-To: info@'.$domain . "\r\n" .
                    'X-Mailer: PHP/' . phpversion();
    
        mail($to, $subject, $message, $headers);
        $response = array('successJs' => 'messageFade("<p>You have requested a new password. You will receive an email shortly.</p>");');        
    }
    return $response;
}
function __createfilterline($i,$columns,$column,$operator,$value){
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

    // add the column dropdown to the form
    array_push($line, 
        new JFormComponentDropDown(
            'filter_column'.$i,
            '',
            $columns,
            array(
                'width' => 'long',
                'initialValue'=>str_replace(
                    "\"",
                    "'",
                    json_encode($column['queryname'])
                ),
            )
        )
    );

    $style = 'clear: none;';
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
    array_push($line, 
        new JFormComponentDropDown(
            'filter_operator'.$i,
            '', 
            $operatorhash[$column['searchtype']],
            array(
                'style'=>'clear:none',
                'initialValue'=>$operator,
            )
        )
    );

    // add values
    if ($column['searchtype'] == 'list'){
        $values = array();
        foreach ($column['list'] as $val){
            array_push($values, array('value' => $val, 'label' => $val));
        }
        array_push(
            $line,
            new JFormComponentDropDown(
                'filter_value'.$i,
                '',
                $values,
                array(
                    'width' => 'long',
                    'style'=>$style,
                    'initialValue'=>$value,
                    'multiple'=>true
                )
            )
        );
    } else {
        array_push(
            $line, 
               new JFormComponentTextArea(
                'filter_value'.$i,
                '',
                array(
                    'style'=>$style,
                    'initialValue'=>$value,
                    'autogrow'=>true
                )
            )
        );
    }
    
    array_push(
        $line, 
        new JFormComponentHtml(
            '<button id="filter_remove'.$i.'" counter="'.$i.'" class="remove_filter_line">Remove</button>'
        )
    );
    return $line;
}
?>