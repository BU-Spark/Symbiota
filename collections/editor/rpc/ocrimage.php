<?php
include_once('../../../config/symbini.php');
include_once($SERVER_ROOT.'/classes/SpecProcessorOcr.php');

// Callers (collections.editor.imgtools.js ocrImage()) post 'imgid'; reading 'mediaId' here left $imgid empty and broke OCR.
$imgid = filter_var($_REQUEST['imgid'], FILTER_SANITIZE_NUMBER_INT);
$x = (array_key_exists('x', $_REQUEST) && is_numeric($_REQUEST['x'])) ? $_REQUEST['x'] : 0;
$y = (array_key_exists('y', $_REQUEST) && is_numeric($_REQUEST['y'])) ? $_REQUEST['y'] : 0;
$w = (array_key_exists('w', $_REQUEST) && is_numeric($_REQUEST['w'])) ? $_REQUEST['w'] : 1;
$h = (array_key_exists('h', $_REQUEST) && is_numeric($_REQUEST['h'])) ? $_REQUEST['h'] : 1;
$ocrBest = array_key_exists('ocrbest', $_REQUEST) ? filter_var($_REQUEST['ocrbest'], FILTER_SANITIZE_NUMBER_INT) : 0;
$target = (array_key_exists('target', $_REQUEST) && in_array($_REQUEST['target'], array('tesseract','google','external','others'), true)) ? $_REQUEST['target'] : 'tesseract';

$rawStr = '';
$ocrManager = new SpecProcessorOcr();
$ocrManager->setCropX($x);
$ocrManager->setCropY($y);
$ocrManager->setCropW($w);
$ocrManager->setCropH($h);
$rawStr = $ocrManager->ocrImageById($imgid, $target, $ocrBest);

echo $rawStr;
?>