<?php
// Start session and check if user is allowed on this page
session_start();

header('Access-Control-Allow-Origin: *');

include_once 'functions.php';
authenticate();

$db = connect_mongo();
$collections = get_collections($db);
$email=$_SESSION['email'];

// get the user database id ( works only for active users)
$user = $collections['users']->findOne(
	array(
		'email'=>$email,
		'active'=>1
		),
 	array(
 		'_id'=>true
 		)
 	);
// get the groups the users belongs to (only if group access is approved)
if ($user['_id']){
	$groups_result = $collections['groups']->find(
		array(
			'users'=>$user['_id'],
			'approved'=>$user['_id']
			)
		);

	foreach ($groups_result as $key => $group){
		// add group id's and group name to session
		$_SESSION['groups'][$group['_id'].""] = $group['name'];
		$group_ids[] = $group['_id'];
	}

	// get projects belonging to the groups
	$projects = $collections['projects']->find(
		array(
			'groups.id'=>array('$in'=>$group_ids)
			)
		);
	foreach ($projects as $key => $project){
		// add project infor to the session
	 	$_SESSION['projects'][$project['_id'].""]=$project;

	 	// add samples in the projects to the session
	 	$samples_result =$collections['samples']->find(array('project.id'=>$project['_id']));
	 	foreach ($samples_result as $key => $sample){
	 		$_SESSION['samples'][$sample['_id'].""] = $sample;
	 	}
	}
	// session now contains all groups, projects and samples for this user
}

// build the SEQPLORER object using this user info
$seqplorer_args = json_encode(
	array(
		"user"=>$email,
		"all_groups"=>$_SESSION['groups'],
		"all_projects"=>$_SESSION['projects'],
		"all_samples"=>$_SESSION['samples'],
		"accordion"=>array(
			"projects"=>0,
			"samples"=>1,
			"variants"=>2),
		"job_config"=>$_SESSION['credentials']['backend']['job_config'],
		"site_config"=>$_SESSION['credentials']['site'],
		#"site"=>$_SESSION['credentials']['site'],
		"interface_vars"=>array(
			"height_correction"=>array(
				'variants'=>270,
				'only_variants'=>300,
				'other'=>200
				),
			"width_correction"=> 67),
		"tables"=>array(
			'samples'=>array(
				'view'=>'samples',
				'name'=>'samples',
				'collection'=>'samples'
			),
			'projects'=>array(
				'view'=>'projects',
				'name'=>'projects',
				'collection'=>'projects'
			),
			'variants'=>array(
				'view'=>'variants',
				'name'=>'variants',
				'collection'=>'variants'
			)
			)
		)
	);
?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<!--
Design by Free CSS Templates
http://www.freecsstemplates.org
Released for free under a Creative Commons Attribution 2.5 License

Name       : Old Stairwell 
Description: A two-column, fixed-width design with dark color scheme.
Version    : 1.0
Released   : 20130313

-->
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<title>seqplorer - Live</title>
	<meta name="keywords" content="" />
	<meta name="description" content="" />
	<link href="https://fonts.googleapis.com/css?family=Open+Sans:400,300,600,700" rel="stylesheet" type="text/css">
		
	<!-- Load stylesheets -->
	<style type="text/css">@import "css/jquery-ui-seqplorer/jquery.ui.all.css";</style>
	<style type="text/css">@import "css/jquery-ui-seqplorer/jquery.autocomplete.css"; </style>
	<style type="text/css">@import "css/colvis.css";</style>
	<style type="text/css">@import "css/jformer.css";</style>
	<style type="text/css">@import "css/tool.css";</style>
	<style type="text/css">@import "css/chosen.css";</style>
		
	<!-- Load jquery plugins from local source -->
	<script type="text/javascript"	src="js/jquery_1.9.0.js"></script>
	<script type="text/javascript"	src="js/jquery-ui_1.10.0.js"></script>
	<script type="text/javascript" 	src="js/jquery-layout_1.3.0.js"></script>
	<script type="text/javascript" 	src="js/jquery-layout-dataTables-resize.js"></script>
	<script type='text/javascript' 	src="js/jquery_SimpleSplitView_1.0.1.js"></script>

	<script type="text/javascript" src="js/dataTables_1.9.4.js"></script>
	<script type="text/javascript" src="js/dataTables-ColVis_1.0.9-dev.js"></script>

	<script type="text/javascript" src="js/jstree.js"></script>
	<script type="text/javascript" src="js/jformer.js"></script>

	<!-- Add project specific scripts and functions -->
	<script type="text/javascript" src="js/functions.js"></script>
	<script type="text/javascript" src="js/seqplorer.js"></script>
	<script type="text/javascript" src="js/project.js"></script>
	<script type="text/javascript" src="js/json2.js"></script>
	<script type="text/javascript" src="js/md5.js"></script>
	<script type="text/javascript" src="js/webstart.js"></script>

	<script type="text/javascript" src="js/chosen.jquery.js"></script>

	<!-- Get userid from session variables -->
	<script language="javascript" type="text/javascript">
   		var userid = '<?php echo $_SESSION['email']; ?>';
   		var SEQPLORER = new SEQPLORER('<?php echo $seqplorer_args; ?>');
 	</script>
</head>
<body>
	<div id="wrapper">
		<div id="header">
			<div id="logo">
				<a href="https://www.seqplorer.org"><img src="img/seqplorer_final.png" alt="" /></a>
			</div>
			<div id="menu">
				<ul>
					<?php if ($_SESSION['email'] != strtoupper('guest@seqplorer.org')){ ?>
						<li><a class=' menu headermenu pv_normal' href='' type='projects' title='Manage projects &  samples'><img src='img/projects.png' /></a></li>
						<li><a class='settings headermenu pv_normal' href='' title='Settings'><img src='img/settings.png' /></a></li>
		 				<!--<li><a class='logs headermenu ' action='logs' href='' title='Show logs'><img src='img/logs.png' /></a></li>-->
					<?php } ?>
					<li><a class='page_view headermenu pv_variants' pview='variants' href='' title='Show my projects'><img src='img/default_view.png' /></a></li>
					<li><a class='page_view headermenu pv_normal' pview='only_variants' href='' title='Show all variants in the database'><img src='img/variants_view.png' /></a></li>
		<!--			<li><a id='showdiv' class='headermenu' url='faq.php' href='https://github.com/brdwilde/Seqplorer/wiki' title='FAQ'><img src='img/faq.png' /></a></li>-->
					<li><a id='showdiv' class='headermenu' url='manual.php' href='https://github.com/brdwilde/Seqplorer/wiki' title='Manual'><img src='img/manual.png' /></a></li>
					<li><a  class='popup headermenu' action='contact' href='https://github.com/brdwilde/Seqplorer/wiki' title='Contact'><img src='img/contact.png' /></a></li>
					<?php if ($_SESSION['email'] == strtoupper('guest@seqplorer.org')){ ?>
						<li><a class='popup headermenu' action='login' href='' title='Login/Register'><img src='img/login.png' /></a></li>
					<?php } else {?>
						<li><a class='logout headermenu' href='' title='Logout'><img src='img/logout.png' /></a></li>
					<?php }?>
					<li><a class='headermenu' href='index.php' title='Home'><img src='img/home.png' /></a></li>
				</ul>
			</div>
		</div>
		<div id="page">
			<!-- Main div -->
			<div id="accordion" class="basic">
				<h3 class='pane' showtable='projects'>
					<a href='' class='header_button popup' title='Create a new project' action='add_project'><img src='img/new_sample.png' /></a>
					<a href="" id="projects_header" >Projects:</a>
				</h3>
				<div>
					<div id="table_projects"></div>
					<div id="welcome"></div>
				</div>
				<h3 class='pane' showtable='samples'>
					<a href='' class="header_button popup need_samples" title='Compare variants' action="compare_variants"><img src="img/compare.png"></a>
					<a href='' class="header_button popup need_samples" title='Calculate coverage' action="coverage"><img src="img/coverage.png"></a>
					<a href='' class="header_button popup need_samples" title='View plots' action="shiny"><img src="img/stats.png"></a>
					<a href='' class="header_button igv need_samples" title='Start IGV'><img src='img/IGV_32.png'/></a>
					<a href='' class='header_button popup add_sample' title='Create a new sample in the currently selected project' action='add_sample'><img src='img/new_sample.png' /></a>
					<a href='' class="header_button" title='Jobs'>
						<img class='jobs_opt' src='img/jobs.png'/>
						<div id='jobs_opt'>
							<ul>
								<li class='header_button popup need_samples need_projects' action='map_reads'>Map reads</li>
								<li class='header_button popup need_samples need_projects' action='call_variants'>Call variants</li>
							</ul>
						</div>
					</a>
					<a href="" id="samples_header">Samples:</a>
				</h3>
				<div>
					<div id="table_samples"></div>
				</div>
				<h3 class='pane' showtable='variants'>
					<a href='' class="header_button" title='Filter options'>
						<img class='filter_opts' src='img/af.png'/>
						<div id='filter_opt'>
							<ul>
								<li class='popup need_samples need_projects' action='create_filter'>Create & edit filter</li>
								<li class='popup' action='save_filter'>Save filter</li>
								<li class='popup' action='load_filter'>Load filter</li>
								<li class="reset_filter">Reset filter</li>
							</ul>
						</div>
					</a>
					<a href='' class="header_button" title='View options'>
						<img class='view_opts' src='img/transcript_view.png'/>
						<div id='view_opt'>
							<ul>
								<li class='popup' action='create_view'>Create & edit view</li>
								<li class='popup' action='save_view'>Save view</li>
								<li class='popup' action='load_view'>Load view</li>
								<li class="reset_view">Reset view</li>
							</ul>
						</div>
					</a>
				    <?php if ($_SESSION['email'] != strtoupper('guest@seqplorer.org')){ ?>
				    	<a href='' class='export' action='export' table='variants' title='Export'><img src='img/export.png' /></a>
				    	<a href='' class='export' action='create_plot' table='variants' title='Create plot'><img src='img/stats.png' /></a>
				    <!-- <a href='' class='header_button' url='newsample.php' table='variants' title='New sample'><img src='img/new_sample.png' /></a> -->
				    <?php }?>
				    <a href='' id="variants_header">Variants: </a> 
				</h3>			
				<div>
					<ul id="af_filters"></ul>
					<div id="table_variants" showtable='variants'></div>				
				</div>
			</div>
			<div id="only_variants">
				<ul id="af_filters"></ul>
			</div>	
			<div id='showhide'></div>
		</div>
		<div id="footer">
			<p></p>
		</div>
	</div>
</body>
</html>
