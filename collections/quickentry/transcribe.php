<?php
include_once('../../config/symbini.php');
// TODO: double check what is this file for
include_once($SERVER_ROOT.'/classes/OccurrenceEditorDeterminations.php');
if($LANG_TAG != 'en' && file_exists($SERVER_ROOT.'/content/lang/collections/editor/transcribe.'.$LANG_TAG.'.php')) include_once($SERVER_ROOT.'/content/lang/collections/editor/transcribe.'.$LANG_TAG.'.php');
else include_once($SERVER_ROOT.'/content/lang/collections/editor/transcribe.en.php');
header("Content-Type: text/html; charset=".$CHARSET);

// exit is required, not decorative: header() only queues a redirect, so without it
// the whole page below still executes for an anonymous visitor -- running the batch
// queries and rendering the form. Same defect as occurrencequickentry.php.
// The old refurl also pointed at ../collections/editor/transcribe.php, which does
// not exist; this file lives in collections/quickentry/.
if(!$SYMB_UID){
	header('Location: ../../profile/index.php?refurl='.rawurlencode('../collections/quickentry/transcribe.php?'.$_SERVER['QUERY_STRING']));
	exit;
}

// Emit $val as a JS literal safe inside a double-quoted HTML event attribute.
// json_encode handles the JS-string layer, htmlspecialchars the attribute layer;
// either alone is insufficient. Same helper as occurrencequickentry.php --
// function_exists-guarded because these are separate page entry points.
if(!function_exists('qeJsAttrArg')){
	function qeJsAttrArg($val){
		if(!$val) return 'null';
		$json = json_encode((string)$val, JSON_INVALID_UTF8_SUBSTITUTE);
		if($json === false) return 'null';
		return htmlspecialchars($json, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
	}
}

$crowdSourceMode = array_key_exists('csmode', $_REQUEST) ? filter_var($_REQUEST['csmode'], FILTER_SANITIZE_NUMBER_INT) : 0;
$goToMode = array_key_exists('gotomode', $_REQUEST) ? filter_var($_REQUEST['gotomode'], FILTER_SANITIZE_NUMBER_INT) : 0;

// Numeric-coerced for the same reason as occurrencequickentry.php: this value
// reaches an href AND a bare JS argument list, and a number is safe in both.
$collid = array_key_exists('collid', $_REQUEST) && is_numeric($_REQUEST['collid'])
	? (int) $_REQUEST['collid'] : 0;

$occManager = new OccurrenceEditorDeterminations();
// Assigned before this call, not after: setCollId() previously received an
// undefined $collid, so the collection map was fetched for nothing.
$occManager->setCollId($collid);
$collMap = $occManager->getCollMap();
$qryCnt = $occManager->getQueryRecordCount();

if($collMap){
	if($collMap['colltype']=='General Observations'){
		$isGenObs = 1;
		$collType = 'obs';
	}
	elseif($collMap['colltype']=='Observations'){
		$collType = 'obs';
	}
	$propArr = $occManager->getDynamicPropertiesArr();
	if(isset($propArr['modules-panel'])){
		foreach($propArr['modules-panel'] as $module){
			if(isset($module['paleo']['status']) && $module['paleo']['status']) $moduleActivation[] = 'paleo';
			elseif(isset($module['matSample']['status']) && $module['matSample']['status']){
				$moduleActivation[] = 'matSample';
				if($tabTarget > 3) $tabTarget++;
			}
		}
	}
}

$isEditor = 0;
$batchIds = $occManager->getBatch($collid);

if($IS_ADMIN || (array_key_exists("CollAdmin",$USER_RIGHTS) && in_array($collid,$USER_RIGHTS["CollAdmin"]))){
	$isEditor = 1;
}
elseif(array_key_exists("CollEditor",$USER_RIGHTS) && in_array($collid,$USER_RIGHTS["CollEditor"])){
	$isEditor = 1;
}
$statusStr = '';

if ($_SERVER["REQUEST_METHOD"] === "POST") {
	if (isset($_POST["batchID"])) {
		$selectedBatchID = is_numeric($_POST["batchID"]) ? (int) $_POST["batchID"] : 0;
		$imgIDs = $occManager->getImgIDs($selectedBatchID);
	} else {
		$imgIDs = $occManager->getAllImgIDs();		
	}
	$firstImgId = $imgIDs[0];
	$firstBarcode = !empty($occManager->getBarcode($firstImgId)) ? ($occManager->getBarcode($firstImgId)) : 0;
	$firstIndex = 0;
	$lastImgId = end($imgIDs);
	$lastBarcode = !empty($occManager->getBarcode($lastImgId)) ? ($occManager->getBarcode($lastImgId)) : 0;
	$lastIndex = count($imgIDs) - 1;
	$occData = array();
	$lastEditImgId = $occManager->getlastEdit($selectedBatchID);
	$lastEditBarcode = !empty($occManager->getBarcode($lastEditImgId)) ? ($occManager->getBarcode($lastEditImgId)) : 0;
	$lastEditIndex = $occManager->getImgIndex($lastEditImgId) - 1;
	// occData is a hashtable, which has imgid as key, and occid as value
	foreach ($imgIDs as $imgID) {
        $occData[$imgID] = $occManager->getOneOccID($imgID);
    }
	$firstOccId = !empty($occData[$firstImgId]) ? ($occData[$firstImgId]) : 0;
	$lastOccId = !empty($occData[$lastImgId]) ? ($occData[$lastImgId]) : 0;
	$lastEditOccId = !empty($occData[$lastEditImgId]) ? ($occData[$lastEditImgId]) : 0;
}

?>

<html>
	<head>
	    <meta http-equiv="Content-Type" content="text/html; charset=<?php echo $CHARSET;?>">
		<title><?php echo $DEFAULT_TITLE.$LANG['IMAGE_BATCH']; ?></title>
		<?php
		$activateJQuery = true;
		if(file_exists($SERVER_ROOT.'/includes/head.php')){
			include_once($SERVER_ROOT.'/includes/head.php');
		}
		else{
			echo '<link href="'.$CLIENT_ROOT.'/css/jquery-ui.css" type="text/css" rel="stylesheet" />';
			echo '<link href="'.$CLIENT_ROOT.'/css/basse.css?ver=1" type="text/css" rel="stylesheet" />';
			echo '<link href="'.$CLIENT_ROOT.'/css/symbiota/quickentry.css" type="text/css" rel="stylesheet" />';
		}
		?>
		<script src="<?php echo $CLIENT_ROOT; ?>/js/jquery-3.7.1.min.js" type="text/javascript"></script>
		<script src="<?php echo $CLIENT_ROOT; ?>/js/jquery-ui.min.js" type="text/javascript"></script>
		<script src="<?php echo $CLIENT_ROOT; ?>/js/symb/collections.editor.query.js" type="text/javascript"></script>
		<script src="<?php echo $CLIENT_ROOT; ?>/js/symb/collections.editor.main.js" type="text/javascript"></script>
		<script type="text/javascript">
			function navigateToRecordNew(crowdSourceMode, gotomode, collId, batchId, imgId, imgIndex, barcode, occId, occIndex) {
				if(barcode == null && occId == null) {
					var url = 'occurrencequickentry.php?gotomode=' + gotomode + '&collid=' + collId + '&imgid=' + imgId + '&imgindex=' + imgIndex;
				} else {
					var url = 'occurrencequickentry.php?csmode=' + crowdSourceMode + '&collid=' + collId +'&batchid=' + batchId + '&imgid=' + imgId + '&imgindex=' + imgIndex + '&barcode=' + barcode + '&occid=' + occId + '&occindex=' + occIndex;
				}
				window.location.href = url;
				event.preventDefault();
			}
		</script>
	</head>
	<body>
	<?php
	include($SERVER_ROOT.'/includes/header.php');
	?>
	<div class='navpath'>
		<a href='../../index.php'><?php echo $LANG['HOME']; ?></a> &gt;&gt;
		<a href="../misc/collprofiles.php?collid=<?php echo (int)$collid; ?>&emode=1"><?php echo $LANG['COLL_MANAGE']; ?></a> &gt;&gt;
		<b><?php echo $LANG['BATCH_DETERS']; ?></b>
	</div>
	<!-- This is inner text! -->
	<div id="innertext">
		<?php
		if($isEditor){
			?>
			<div style="margin:0px;">
				<fieldset style="padding:10px;">
					<legend><b><?php echo $LANG['TRANSCRIBE_INTO_SPECIFY']; ?></b></legend>
					<div style="margin:15px;width:700px;">
                        <!-- TODO: update the submit function of the form -->
						<form name="batchform" method="post">
							<div style="margin-bottom:15px; align-items: center;">
								<h4 style="margin-right: 15px;">Work On batch: <?php echo htmlspecialchars((string)$selectedBatchID, ENT_QUOTES, 'UTF-8'); ?></h4>
								<div style="display: flex; flex-grow: 1;">
									<button type="button" name="first" style="flex-grow: 0.5; margin-right: 5px;" onclick="return navigateToRecordNew(<?php echo (int)$crowdSourceMode.', '.(int)$goToMode.', '.(int)$collid.', '.(int)$selectedBatchID.', '.($firstImgId).', '.($firstIndex).', '.qeJsAttrArg($firstBarcode).', '.($firstOccId).', '.($firstIndex) ; ?>)"><?php echo $LANG['START_FROM']; ?> first.</button>
									<button type="button" name="last" style="flex-grow: 0.5; margin-right: 5px;" onclick="return navigateToRecordNew(<?php echo (int)$crowdSourceMode.', '.(int)$goToMode.', '.(int)$collid.', '.(int)$selectedBatchID.', '.($lastImgId).', '.($lastIndex).', '.qeJsAttrArg($lastBarcode).', '.($lastOccId).', '.($lastIndex); ?>)"><?php echo $LANG['START_FROM']; ?> last.</button>
									<button type="button" name="lastView" style="flex-grow: 0.5;" onclick="return navigateToRecordNew(<?php echo (int)$crowdSourceMode.', '.(int)$goToMode.', '.(int)$collid.', '.(int)$selectedBatchID.', '.($lastEditImgId).', '.($lastEditIndex).', '.qeJsAttrArg($lastEditBarcode).', '.($lastEditOccId).', '.($lastEditIndex); ?>)"><?php echo $LANG['START_FROM']; ?> last edit.</button>
								</div>
							</div>
							<div>
								<b><?php echo $LANG['WORK_ON_BATCH']; ?></b>
								<select id="batchID" name="batchID" style="width:400px;" onchange="this.form.submit()">
									<option value="">-- Select Batch --</option>
									<?php
									foreach ($batchIds as $batchID) {
										$batch_name = current($occManager->getbatchName($batchID));
										echo "<option value=\"$batchID\">$batch_name</option>";
									}
									?>
								</select>
							</div>
						</form>
					</div>
				</fieldset>
				<!-- TODO: need to figure out what this status is -->
				<!-- <fieldset>
					<div>
						<p style="margin:0px;"><?php // echo $LANG['STATUS']; ?></p>
					</div>
				</fieldset> -->
			</div>
			<?php
		}
		else{
			?>
			<div style="font-weight:bold;margin:20px;font-weight:150%;">
				<?php echo $LANG['NO_PERMISSIONS']; ?>
			</div>
			<?php
		}
		?>
	</div>
	<?php
	include($SERVER_ROOT.'/includes/footer.php');
	?>
	</body>
</html>