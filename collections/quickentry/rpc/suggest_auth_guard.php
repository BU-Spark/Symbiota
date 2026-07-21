<?php
// Auth gate for quick-entry suggest RPC endpoints.
// These are only invoked from the occurrence editor (collections.editor.main.js),
// which is itself editor-gated, so require a logged-in user with any collection
// edit/admin right. Blocks anonymous cross-collection enumeration of
// collector/determiner/locality autocomplete values over the whole omoccurrences table.
// Requires config/symbini.php already included (defines $SYMB_UID, $IS_ADMIN, $USER_RIGHTS).
$isEditor = false;
if($SYMB_UID){
	if($IS_ADMIN){
		$isEditor = true;
	}
	elseif(!empty($USER_RIGHTS['CollAdmin']) || !empty($USER_RIGHTS['CollEditor'])){
		$isEditor = true;
	}
}
if(!$isEditor){
	http_response_code(401);
	echo 'Unauthorized';
	exit;
}
?>
