<?php
include_once('../../../config/symbini.php');
include_once($SERVER_ROOT.'/classes/RpcOccurrenceEditor.php');
include_once('suggest_auth_guard.php');
header('Content-Type: application/json; charset='.$CHARSET);

$term = $_REQUEST['term'];

$searchManager = new RpcOccurrenceEditor();
$retArr = $searchManager->getIdentifedBySuggest($term);

echo json_encode($retArr);
?>