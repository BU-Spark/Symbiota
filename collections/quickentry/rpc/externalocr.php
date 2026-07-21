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

// SSRF prevention: derive the image URL server-side from imgid rather than trusting client input.
$imageUrl = '';
$occid = $occManager->getOneOccID($imgId);
if($occid){
	$occManager->setOccId($occid);
	$imgInfo = $occManager->getImageInfo($imgId);
	if(isset($imgInfo[$imgId])){
		$imageUrl = $imgInfo[$imgId]['origurl'] ? $imgInfo[$imgId]['origurl'] : $imgInfo[$imgId]['url'];
	}
}
if(empty($imageUrl)){
	echo json_encode(["error" => "Missing image URL"]);
	exit;
}

// SSRF guard: reject non-http(s) schemes and block link-local / private ranges.
// The middleware fetches this URL server-side, so an editor-controlled origurl
// could otherwise reach internal services (IMDS, sidecars, etc.).
$parsedUrl = parse_url($imageUrl);
$scheme = strtolower($parsedUrl['scheme'] ?? '');
if(!in_array($scheme, ['http', 'https'], true)){
	echo json_encode(["error" => "Invalid image URL"]);
	exit;
}
$host = $parsedUrl['host'] ?? '';
// Resolve to IP for range checks (falls back to the literal if already an IP).
$ip = filter_var($host, FILTER_VALIDATE_IP) ? $host : gethostbyname($host);
if(filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) === false){
	// ponytail: blocks RFC-1918, link-local (169.254/16), loopback, multicast.
	// Does not cover IPv6 ULA; add FILTER_FLAG_IPV6 + separate check if needed.
	echo json_encode(["error" => "Image URL resolves to a disallowed address"]);
	exit;
}

$url = 'http://ocr_middleware:8000/evaluate/azure?url=' . urlencode($imageUrl);

$options = [
    'http' => [
        'method'  => 'POST',
        'header'  => "Accept: application/json\r\n",
        'content' => '', // empty body
        'ignore_errors' => true,
    ]
];

$context = stream_context_create($options);
$response = file_get_contents($url, false, $context);

if ($response === FALSE) {
    echo json_encode(["error" => "Failed to fetch API response"]);
    exit;
}

$decoded = json_decode($response, true);

if ($decoded === null) {
    echo json_encode(["error" => "Invalid JSON response from OCR service"]);
    exit;
}

echo json_encode($decoded);
?>
