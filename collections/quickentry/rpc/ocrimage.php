<?php
include_once('../../../config/symbini.php');
include_once($SERVER_ROOT.'/classes/OccurrenceEditorManager.php');
include_once($SERVER_ROOT.'/classes/SpecProcessorOcr.php');

$imgid = filter_var($_REQUEST['imgid'], FILTER_SANITIZE_NUMBER_INT);

// Authorization: resolve collid from imgid and require admin/editor rights.
$occManager = new OccurrenceEditorManager();
$collid = $occManager->getCollIdByImgId($imgid);
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

$x = (array_key_exists('x', $_REQUEST) && is_numeric($_REQUEST['x'])) ? $_REQUEST['x'] + 0 : 0;
$y = (array_key_exists('y', $_REQUEST) && is_numeric($_REQUEST['y'])) ? $_REQUEST['y'] + 0 : 0;
$w = (array_key_exists('w', $_REQUEST) && is_numeric($_REQUEST['w'])) ? $_REQUEST['w'] + 0 : 1;
$h = (array_key_exists('h', $_REQUEST) && is_numeric($_REQUEST['h'])) ? $_REQUEST['h'] + 0 : 1;
$ocrBest = array_key_exists('ocrbest', $_REQUEST) ? filter_var($_REQUEST['ocrbest'], FILTER_SANITIZE_NUMBER_INT) : 0;
// Restrict target to a known set of OCR engine identifiers.
$allowedTargets = array('tesseract', 'google', 'azure', 'others');
$target = (array_key_exists('target', $_REQUEST) && in_array($_REQUEST['target'], $allowedTargets, true)) ? $_REQUEST['target'] : 'tesseract';

$rawStr = '';
$ocrManager = new SpecProcessorOcr();
$ocrManager->setCropX($x);
$ocrManager->setCropY($y);
$ocrManager->setCropW($w);
$ocrManager->setCropH($h);
$rawStr = $ocrManager->ocrImageById($imgid, $target, $ocrBest);

echo $rawStr;
?>
