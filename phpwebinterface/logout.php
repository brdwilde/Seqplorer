<?php
 // Start session and check if user is allowed on this page
session_start();
include_once 'functions.php';
authenticate();
?>
<a id='hidediv' href=''><img class='cancel_popup' src='img/back.png'></img></a>
<?php
// connect to the database
$credentials = read_credentials($_SESSION['config']);
$db = connect_mongo();
$collections = get_collections($db);
session_destroy();
?>
<p>You have been logged out successfully...</p>
<script type="text/javascript" >reload('1000');</script>