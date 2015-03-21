<?php
session_start();
include '../functions.php';
authenticate();

$db = connect_mongo();
$collections = get_collections($db);

$email=$_SESSION['email'];
$user = $collections['users']->findOne(array('email'=>$email,'active'=>1), array('_id'=>true));
?>
<ul> 
	<li title='Manage your groups here'><a href="#">Manage</a>
		<ul> <?php
			$manage_groups_result = $collections['groups']->find(array('admin'=>$user['_id']));
			foreach ($manage_groups_result as $key => $manage_groups){ ?>
				<li><a href='#' class='popup' action='manage_group' groups_id='<?php echo $manage_groups['_id'];?>' title='<?php echo $manage_groups['description']; ?>'><?php echo $manage_groups['name']; ?></a></li> <?php
			} ?>
			<li><a href='#' class='popup' action='new_group' title="Create a new group and invite members">Add new</a></li>
		</ul>
	</li>
	<?php
	$unsubscribe_groups_result = $collections['groups']->find(array('admin'=>array('$ne'=>$user['_id']),'approved'=>$user['_id'],'name'=>array('$ne'=>'Public')));
	if ($unsubscribe_groups_result->count() > 0){?>
		<li title='Here your group membership is displayed'><a href="#">Unsubscribe</a>
			<ul> <?php
			foreach($unsubscribe_groups_result as $key => $unsubscribe_groups){
				?>
				<li><a class='popup' action='unsubscribe_group' groups_id='<?php echo $unsubscribe_groups['_id']; ?>' title='<?php echo $unsubscribe_groups['description']; ?>' user='<?php echo $user['_id']; ?>' ><?php echo $unsubscribe_groups['name']; ?></a></li>
					<?php
			}?>
			</ul>
		</li> <?php
	}
	else {
		?> <li class="ui-state-disabled" title='No available groups to leave'><a href="#">No groups to leave</a> </li><?php
	}
	$approve_result = $collections['groups']->find(array('admin'=>$user['_id']));
	foreach($approve_result as $key=>$approve){
		if(count($approve['users']) != count($approve['approved'])){
			$diff = array_diff($approve['users'],$approve['approved']);
			foreach ($diff as $key=>$value){
				$user_id = $value;
			}?>
			<li title='Grant group access requests'><a href="#">Approve</a>
				<ul>
					<li><a class='popup' action='approve_group' groups_id='<?php echo $approve['_id']; ?>' user='<?php echo $user_id; ?>' title='<?php echo $approve['description']; ?>'><?php echo $approve['name']; ?></a></li>
				</ul>
			</li> <?php 
		}
	} ?>
		<?php
		$join_groups_result=$collections['groups']->find(array('users'=>array('$ne'=>$user['_id']),'public'=>'yes'));
		if ($join_groups_result->count() > 0){?>
			<li title='Select a group you would like to join'><a href="#">Join</a>
				<ul> <?php
			foreach ($join_groups_result as $key => $join_groups){ ?>
				<li><a class='popup' action='join_group' groups_id='<?php echo $join_groups['_id'];?>' title='<?php echo $join_groups['description']; ?>'><?php echo $join_groups['name']; ?></a></li> <?php
			}
			?> </ul> <?php
		}
		else {?>
			<li class="ui-state-disabled" title='No available public groups'><a href="#">No public groups to join</a></li>
		<?php } ?>
	</li>
</ul>