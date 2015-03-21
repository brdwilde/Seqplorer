<?php
session_start();
include '../functions.php';
authenticate();

$db = connect_mongo();
$collections = get_collections($db);

$email=$_SESSION['email'];

// get groups_id
$user = $collections['users']->findOne(array('email'=>$email,'active'=>1), array('_id'=>true));
// $user['_id'] = new MongoId('50d1e3b8721c5a0142000001');

$groups_result = $collections['groups']->find(array('admin'=>$user['_id']), array('_id'=>true));
foreach ($groups_result as $key => $group){
	$groups_id[] = $group['_id'];
	$group_id_strings[] = $group['_id']."";
}

$projects = $collections['projects']->find(array('groups.id'=>array('$in'=>$groups_id)));

?>
<ul> <?php 
	foreach ($projects as $key => $project){?>
		<li>
			<a href='#' class='popup' action='manage_project' user='<?php echo $user['_id'].""; ?>' groups_id='<?php echo json_encode($group_id_strings);?>' projectsid='<?php echo $project['_id'].""; ?>' ><?php echo $project['name']; ?></a>
			<ul><?php
				$samples_result =$collections['samples']->find(array('project.id'=>$project['_id']))->sort(array('name'=>1));
				foreach ($samples_result as $key => $sample){?>
					<li>
						<a href='#' class='popup' action='manage_sample' user='<?php echo $user['_id'].""; ?>' groups_id='<?php echo json_encode($group_id_strings);?>' projectsid='<?php echo $project['_id'].""; ?>' samplesid=<?php echo $sample['_id']."";?> title='<?php echo $sample['description']; ?>'><?php echo $sample['name']; ?></a>
					</li>
					<?php
				}
				if ($email != strtoupper("guest@seqplorer.org")){ ?>
					<li>
						<a class='popup' action='add_sample' projectsid='<?php echo $project['_id'];?>' title='Create a new sample in project <?php echo $project['name'];?>'>Add sample</a>
					</li>
					<!-- 
					<li><a id='showdiv' url='add_sample.php' get='id=<?php //echo $project['_id'];?>&add=files' projectsid='<?php //echo $project['_id'];?>' title='Add files to an existing sample in project <?php //echo $project['name'];?>'>Add files</a></li> --><?php
				}?>
			</ul>
		</li><?php
	}
	if ($email != strtoupper("guest@seqplorer.org")){ ?>
		<li>
			<a href='#' class='popup' action='add_project' title='Create a new project'>Add project</a>
		</li><?php
	}