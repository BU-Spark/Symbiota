<?php
include_once('../../../config/symbini.php');
include_once($SERVER_ROOT.'/classes/OccurrenceEditorManager.php');

header('Content-Type: application/json');

$occManager = new OccurrenceEditorManager();

$imgId = isset($_POST['imgid']) ? filter_var($_POST['imgid'], FILTER_SANITIZE_NUMBER_INT) : null;

// Authorization: resolve collid from imgid and require admin/editor rights.
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
	echo json_encode(["error" => "Unauthorized"]);
	exit;
}

// Base URL for the alternate OCR output service (no shell invocation).
$OTHER_OCR_URL = 'http://ocr-server:8050/output/2';

$options = [
	'http' => [
		'method'  => 'GET',
		'header'  => "Accept: application/json\r\n",
		'ignore_errors' => true,
	]
];
$context = stream_context_create($options);
$response = file_get_contents($OTHER_OCR_URL, false, $context);

if ($response === FALSE) {
	echo json_encode(["error" => "Failed to fetch API response"]);
	exit;
}

// Decode the JSON response
$decodedResponse = json_decode($response, true);

// Define default variables
$ocr_catalogNumber = 0;
$ocr_collectionCode = 0;
$ocr_country = '';
$ocr_donatedBy = '';
$ocr_eventDate = '';
$ocr_institutionCode = 0;
$ocr_occurrenceID = 0;
$ocr_recordedBy = '';
$ocr_scientificName = '';
$ocr_yearDonated = 0;

// Update variables if the JSON response is valid
if ($decodedResponse !== null && is_array($decodedResponse)) {
	$catalogNumber = $decodedResponse['catalogNumber'] ?? $ocr_catalogNumber;
	$collectionCode = $decodedResponse['collectionCode'] ?? $ocr_collectionCode;
	$country = $decodedResponse['country'] ?? $ocr_country;
	$donatedBy = $decodedResponse['donatedBy'] ?? $ocr_donatedBy;
	$eventDate = $decodedResponse['eventDate'] ?? $ocr_eventDate;
	$institutionCode = $decodedResponse['institutionCode'] ?? $ocr_institutionCode;
	$occurrenceID = $decodedResponse['occurrenceID'] ?? $ocr_occurrenceID;
	$recordedBy = $decodedResponse['recordedBy'] ?? $ocr_recordedBy;
	$scientificName = $decodedResponse['scientificName'] ?? $ocr_scientificName;
	$yearDonated = $decodedResponse['yearDonated'] ?? $ocr_yearDonated;
}

// Return the raw JSON response directly
echo $response;
?>
