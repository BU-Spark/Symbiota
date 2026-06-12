<?php
include_once('../../../config/symbini.php');
include_once($SERVER_ROOT.'/classes/OccurrenceEditorManager.php');
header("Content-Type: text/plain; charset=".$CHARSET);

$occManager = new OccurrenceEditorManager();

$imgId = isset($_POST['imgid']) ? filter_var($_POST['imgid'], FILTER_SANITIZE_NUMBER_INT) : null;

// Authorization: resolve collid from imgid and require admin/editor rights before saving.
$collid = $occManager->getCollIdByImgId($imgId);
$isEditor = false;
if($SYMB_UID){
	if($IS_ADMIN){
		$isEditor = true;
	}
	elseif($collid){
		if(array_key_exists("CollAdmin",$USER_RIGHTS) && in_array($collid,$USER_RIGHTS["CollAdmin"])) $isEditor = true;
		elseif(array_key_exists("CollEditor",$USER_RIGHTS) && in_array($collid,$USER_RIGHTS["CollEditor"])) $isEditor = true;
	}
}
if(!$isEditor){
	echo 'Unauthorized';
	exit;
}
$notes = isset($_POST['rawtext']) ? trim($_POST['rawtext']) : null;
$rawNotes = isset($_POST['rawnotes']) ? trim(strip_tags($_POST['rawnotes'])) : null;
$rawSource = isset($_POST['rawsource']) ? trim(strip_tags($_POST['rawsource'])) : null;

$status = $occManager->saveOcrResult($imgId, $notes, $rawNotes, $rawSource);

echo $status;
?>