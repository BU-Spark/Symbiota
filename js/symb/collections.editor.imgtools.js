var activeImgIndex = 1;
var ocrFragIndex = 1;

// ===========================================================================
// ML confidence display helpers (shared by quickEntryOcrImage + pushDwcArrToForm)
// ---------------------------------------------------------------------------
// The middleware may return a structured envelope of the form:
//   { "scientificName": "...", "recordedBy": "...",
//     "_confidence": { "scientificName": 0.92, ... }, "_meta": {...} }
// Confidence keys arrive camelCase (DWC); form element names are lowercase.
// ===========================================================================

// Map camelCase DWC keys -> lowercase form element names. Used by BOTH handlers.
var dwcToFormField = {
	scientificName: "sciname",
	scientificNameAuthorship: "scientificnameauthorship",
	recordedBy: "recordedby",
	recordNumber: "recordnumber",
	eventDate: "eventdate",
	verbatimEventDate: "verbatimeventdate",
	family: "family",
	catalogNumber: "catalognumber",
	country: "country",
	stateProvince: "stateprovince",
	county: "county",
	continent: "continent",
	locality: "locality",
	habitat: "habitat",
	occurrenceRemarks: "occurrenceremarks",
	identifiedBy: "identifiedby",
	dateIdentified: "dateidentified",
	decimalLatitude: "decimallatitude",
	decimalLongitude: "decimallongitude",
	minimumElevationInMeters: "minimumelevationinmeters",
	maximumElevationInMeters: "maximumelevationinmeters",
	verbatimElevation: "verbatimelevation",
	verbatimCoordinates: "verbatimcoordinates",
	associatedTaxa: "associatedtaxa"
};

// Background colors keyed by confidence band.
var CONFIDENCE_COLORS = {
	high: "#77dd77",      // c >= 0.85  (green)
	medium: "#ffd27f",    // 0.6 <= c < 0.85 (amber)
	low: "#ff9b9b",       // c < 0.6 (red)
	neutral: "#d9d9d9"    // populated but no/invalid score (gray)
};

// Return a background color for a confidence value. Coerces with Number();
// null/undefined/NaN -> neutral. Never throws.
function confidenceColor(c){
	if(c === null || typeof c === "undefined") return CONFIDENCE_COLORS.neutral;
	var n = Number(c);
	if(isNaN(n)) return CONFIDENCE_COLORS.neutral;
	if(n >= 0.85) return CONFIDENCE_COLORS.high;
	if(n >= 0.6) return CONFIDENCE_COLORS.medium;
	return CONFIDENCE_COLORS.low;
}

// Apply confidence-based coloring + a hover tooltip to a populated form field.
// elem: DOM element; fieldKey: camelCase DWC key; confidenceMap: optional _confidence obj.
// Only the numeric score is ever rendered (no raw response text -> no XSS).
function applyConfidenceToField(elem, fieldKey, confidenceMap){
	if(!elem) return;
	var rawC = (confidenceMap && typeof confidenceMap === "object") ? confidenceMap[fieldKey] : undefined;

	// Determine whether we have a usable numeric score.
	var hasScore = !(rawC === null || typeof rawC === "undefined");
	var n = hasScore ? Number(rawC) : NaN;
	if(hasScore && isNaN(n)) hasScore = false;

	// Color the field.
	elem.style.backgroundColor = confidenceColor(hasScore ? n : null);
	elem.classList.add("ml-confidence-field");

	if(hasScore){
		elem.setAttribute("data-confidence", n);
		var pct = Math.round(n * 100);
		// title text is built only from the numeric score -> safe.
		elem.setAttribute("title", "ML confidence: " + pct + "%");
	}
	else{
		elem.removeAttribute("data-confidence");
		elem.setAttribute("title", "ML confidence: unavailable");
	}

	// Attach jQuery UI tooltip (already loaded). Safe: reads the title attr only.
	try{
		if(typeof $ !== "undefined" && $(elem).tooltip){
			$(elem).tooltip({ items: "[title]", track: true });
		}
	}
	catch(err){ /* tooltip not available; title attr still shows native tooltip */ }
}

// Detect the structured envelope: an object carrying a _confidence map and/or
// at least one recognized DWC key. Plain OCR text (string) returns false.
function isStructuredOcrEnvelope(obj){
	if(!obj || typeof obj !== "object") return false;
	if(obj._confidence && typeof obj._confidence === "object") return true;
	for(var key in dwcToFormField){
		if(Object.prototype.hasOwnProperty.call(obj, key)) return true;
	}
	return false;
}

$(document).ready(function() {
	//Remember image popout status 
	var imgTd = getCookie("symbimgtd");
	if(imgTd != "close") toggleImageTdOn();
	//if(imgTd == "open" || csMode == 1) toggleImageTdOn();
	initImgRes();
});

function toggleImageTdOn(){
	var imgSpan = document.getElementById("imgProcOnSpan");
	if(imgSpan){
		imgSpan.style.display = "none";
		document.getElementById("imgProcOffSpan").style.display = "block";
		var imgTdObj = document.getElementById("imgtd");
		if(imgTdObj){
			document.getElementById("imgtd").style.display = "block";
			initImageTool("activeimg-1");
			//Set cookie to tag td as open
	        document.cookie = "symbimgtd=open";
		}
	}
}

function toggleImageTdOff(){
	var imgSpan = document.getElementById("imgProcOnSpan");
	if(imgSpan){
		imgSpan.style.display = "block";
		document.getElementById("imgProcOffSpan").style.display = "none";
		var imgTdObj = document.getElementById("imgtd");
		if(imgTdObj){
			document.getElementById("imgtd").style.display = "none";
			//Set cookie to tag td closed
	        document.cookie = "symbimgtd=close";
		}
	}
}

function initImageTool(imgId){
	var img = document.getElementById(imgId);
	if(!img.complete){
		imgWait=setTimeout(function(){initImageTool(imgId)}, 500);
	}
	else{
		var portWidth = 400;
		var portHeight = 400;
		var portXyCookie = getCookie("symbimgport");
		if(portXyCookie){
			portWidth = parseInt(portXyCookie.substr(0,portXyCookie.indexOf(":")));
			portHeight = parseInt(portXyCookie.substr(portXyCookie.indexOf(":")+1));
		}
		$(function() {
			$(img).imagetool({
				maxWidth: 6000
				,viewportWidth: portWidth
		        ,viewportHeight: portHeight
			});
		});
	}
}

function setPortXY(portWidth,portHeight){
	document.cookie = "symbimgport=" + portWidth + ":" + portHeight;
}

function initImgRes() {
	var imgObj = document.getElementById("activeimg-"+activeImgIndex);
	if(imgObj){
		if(imgLgArr[activeImgIndex]){
			var imgRes = getImgRes(); 
			if(imgRes == 'lg') changeImgRes('lg');
		}
		else{
			imgObj.src = imgArr[activeImgIndex];
			document.getElementById("imgresmed").checked = true;
			var imgResLgRadio = document.getElementById("imgreslg");
			imgResLgRadio.disabled = true;
			imgResLgRadio.title = "Large resolution image not available";
		}
		if(imgArr[activeImgIndex]){
			//Do nothing
		}
		else{
			if(imgLgArr[activeImgIndex]){
				imgObj.src = imgLgArr[activeImgIndex];
				document.getElementById("imgreslg").checked = true;
				var imgResMedRadio = document.getElementById("imgresmed");
				imgResMedRadio.disabled = true;
				imgResMedRadio.title = "Medium resolution image not available";
			}
		}
	}
}

function changeImgRes(resType){
	var imgObj = document.getElementById("activeimg-"+activeImgIndex);
	var oldSrc = imgObj.src;
	if(resType == 'lg'){
        document.cookie = "symbimgres=lg";
    	if(imgLgArr[activeImgIndex]){
    		imgObj.src = imgLgArr[activeImgIndex];
    		document.getElementById("imgreslg").checked = true;
    	}
	}
	else{
        document.cookie = "symbimgres=med";
    	if(imgArr[activeImgIndex]){
    		imgObj.src = imgArr[activeImgIndex];
    		document.getElementById("imgresmed").checked = true;
    	}
	}
}

function rotateImage(rotationAngle, imgIndex){
	if(typeof imgIndex === 'undefined') {
		imgIndex = activeImgIndex;
	}
	
	var imgObj = document.getElementById("activeimg-"+imgIndex);
	if(!imgObj){
		console.error("Image element not found: activeimg-" + imgIndex);
		return;
	}
	
	var imgAngle = 0;
	if(imgObj.style.transform){
		var transformValue = imgObj.style.transform;
		var match = transformValue.match(/rotate\((-?\d+)deg\)/);
		if(match){
			imgAngle = parseInt(match[1]);
		}
	}
	
	imgAngle = imgAngle + rotationAngle;
	if(imgAngle < 0) imgAngle = 360 + imgAngle;
	else if(imgAngle >= 360) imgAngle = imgAngle % 360;
	
	imgObj.style.transform = "rotate("+imgAngle+"deg)";
	
	if(typeof $ !== 'undefined' && $(imgObj).data('imagetool')){
		$(imgObj).imagetool("option","rotationAngle",imgAngle);
		$(imgObj).imagetool("reset");
	}
}

function ocrImage(ocrButton, target, imgidVar, imgCnt){
	ocrButton.disabled = true;
	let wcElem = document.getElementById("workingcircle-"+target+"-"+imgCnt);
	if (wcElem) {
		wcElem.style.display = "inline";
	}
	
	let imgObj = document.getElementById("activeimg-"+imgCnt);
	let xVar = 0;
	let yVar = 0;
	let wVar = 1;
	let hVar = 1;
	let ocrBestVar = 0;

	if(document.getElementById("ocrfull-"+target).checked == false){
		xVar = $(imgObj).imagetool("properties").x;
		yVar = $(imgObj).imagetool("properties").y;
		wVar = $(imgObj).imagetool("properties").w;
		hVar = $(imgObj).imagetool("properties").h;
	}
	if(document.getElementById("ocrbest").checked == true){
		ocrBestVar = 1;
	}

	$.ajax({
		type: "POST",
		url: "rpc/ocrimage.php",
		data: { imgid: imgidVar, target: target, ocrbest: ocrBestVar, x: xVar, y: yVar, w: wVar, h: hVar }
	}).done(function( msg ) {
		let rawStr = msg;
		document.getElementById("tfeditdiv-"+imgCnt).style.display = "none";
		document.getElementById("tfadddiv-"+imgCnt).style.display = "block";
		let addform = document.getElementById("ocraddform-"+imgCnt);
		addform.rawtext.innerText = rawStr;
		addform.rawtext.textContent = rawStr;
		//Add OCR source with date
		let today = new Date();
		let dd = today.getDate();
		let mm = today.getMonth()+1; //January is 0!
		let yyyy = today.getFullYear();
		if(dd<10) dd='0'+dd;
		if(mm<10) mm='0'+mm;
		if(target == "tess") target = "Tesseract";
		else target = "Digi-Leap";
		addform.rawsource.value = target+": "+yyyy+"-"+mm+"-"+dd;
		
		if (wcElem) {
			wcElem.style.display = "none";
		}
		ocrButton.disabled = false;
	});
}

// Function to run OCR via Vouchervision-Go API
async function ocrVV(ocrButton, imgCnt){

	// Get the busy indicator and image url
	const busy = $('#workingcircle-vv-' + imgCnt);
	const imgurl = $('#activeimg-' + imgCnt).attr('src');

	// Get user-selected parameters
	const prompt = $('#prompt').val();
	const llm_model = $('#llm-model').val();
    const engines = [];
    $('input[name="engines"]:checked').each(function() {
        engines.push($(this).attr('id'));
    });
    const ocrOnly = $('#ocrOnly').is(':checked');

    // Show busy indicator
    busy.show();

    // Disable additional OCR Image button presses
    $(ocrButton).prop('disabled', true);

    // Symbiota field mappings for data returned by various prompts
	const vvMapping = {
		SLTPvM_default: {
			// James Note: Catch-all field: Turning this off may be preferred, it accumulates a lot of junk.
			additionalText: "occurrenceremarks",
			// James Note: I think this is currently a bit shaky for an important field
			//catalogNumber: "catalognumber",
			collectedBy: "recordedby",
			collectionDate: "eventdate",
			collectionDateEnd: "eventdate2",
			collectorNumber: "recordnumber",
			continent: "continent",
			country: "country",
			county: "county",
			cultivated: "cultivationstatus", // checkbox
			// James Note: decimal lat/long can sometimes be hallucinated,
			// incorrectly derived from locality,
			// or improperly converted from other coordinates
			decimalLatitude: "decimallatitude",
			decimalLongitude: "decimallongitude",
			//elevationUnits: "",
			//genus: "",
			habitat: "habitat",
			//identificationHistory: "",
			identifiedBy: "identifiedby",
			identifiedConfidence: "identificationqualifier",
			identifiedDate: "dateidentified",
			identifiedRemarks: "identificationremarks",
			locality: "locality",
			maximumElevationInMeters: "maximumelevationinmeters",
			minimumElevationInMeters: "minimumelevationinmeters",
			scientificName: "sciname",
			scientificNameAuthorship: "scientificnameauthorship",
			//specificEpithet: "",
			specimenDescription: "verbatimattributes",
			stateProvince: "stateprovince",
			verbatimCollectionDate: "verbatimeventdate",
			verbatimCoordinates: "verbatimcoordinates"
		},
		OSC_Symbiota: {
			// James Note: I think this is currently a bit shaky for an important field
			//catalogNumber: "catalognumber",
			collector: "recordedby",
			associatedCollectors: "associatedcollectors",
			collectorNumber: "recordnumber",
			verbatimCollectionDate: "verbatimeventdate",
			collectionDate: "eventdate",
			scientificName: "sciname",
			scientificNameAuthorship: "scientificnameauthorship",
			family: "family",
			// James Note: Asking for genus, specific epithet and infra-epithet and
			// constructing a scientific name with that was more reliable than the
			// scientific name returned by Vouchervision for Gemini 1.5 Flash at least
			// Tendency for the full scientific name to include authors
			//genus: "",
			//specificEpithet: "",
			//infraspecificEpithet: "",
			identifiedBy: "identifiedby",
			identifiedConfidence: "identificationqualifier",
			identifiedDate: "dateidentified",
			identifiedRemarks: "identificationremarks",
			continent: "continent",
			country: "country",
			stateProvince: "stateprovince",
			county: "county",
			locality: "locality",
			// James Note: decimal lat/long can sometimes be hallucinated,
			// incorrectly derived from locality,
			// or improperly converted from other coordinates
			decimalLatitude: "decimallatitude",
			decimalLongitude: "decimallongitude",
			verbatimCoordinates: "verbatimcoordinates",
			datum: "geodeticdatum",
			verbatimElevation: "verbatimelevation",
			cultivated: "cultivationstatus",
			habitat: "habitat",
			specimenDescription: "verbatimattributes",
			associatedSpecies: "associatedtaxa",
			// James Note: Catch-all field: Turning this off may be preferred
			additionalText: "occurrenceremarks",
		}
	}

	// Construct a data object with parameters to pass to the API
	const vvData = {
		image_url: imgurl,
		engines: engines,
		prompt: prompt + '.yaml',
		llm_model: llm_model,
		ocr_only: ocrOnly
	};

	// Start a timer to check how long the API call took
	var start = Date.now();

    // Send the request to VoucherVision-Go
	$.ajax({
		type: 'POST',
		url: 'rpc/voucherVisionGo.php',
		data: JSON.stringify(vvData),
		dataType: 'json',
		contentType: 'application/json',
		success: function (data) {

			// Object to store the costs
			let cost = {"ocr": 0, "transcription": 0, "total": 0};

			// Get transcription cost
			cost.transcription = data.parsing_info.cost_in + data.parsing_info.cost_out;

			// Get OCR cost
			Object.keys(data.ocr_info).forEach(key => {
				cost.ocr += data.ocr_info[key].cost_in + data.ocr_info[key].cost_out;
			});

			// Calculate the total cost
			cost.total = cost.transcription + cost.ocr;

			// Format the cost as a currency string
			let costStr = new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD',
				minimumFractionDigits: 6}).format(cost.total);

			// Write out message on success, along with the time, cost, and returned data object
			console.log('VoucherVision-Go returned data after ' + ((Date.now() - start)/1000).toFixed(2) +
				' seconds. Total cost: ' + costStr + '\n', data);

			// Get the OCR text
			let ocr = data.ocr;

			// Hide the edit div (existing content), and show the add div for new OCR content
			$('#tfeditdiv-' + imgCnt).hide();
			$('#tfadddiv-' + imgCnt).show();

			// Add OCR data to the editor
			$('#tfadddiv-' + imgCnt + ' textarea[name="rawtext"]').val(ocr);

			// Construct the OCR source string
			// Add the date
			let today = new Date();
			// Add leading zeros to day and month
			let dd = String(today.getDate()).padStart(2, '0');
			let mm = String(today.getMonth()+1).padStart(2, '0'); //January is 0!
			let yyyy = today.getFullYear();

			// Add Vouchervision-Go, the date, and the OCR/Transcription models to the source string
			let sourceStr = 'Vouchervision-Go: ' + yyyy + '-' + mm + '-' + dd;
			sourceStr += '; OCR Model(s): ' + engines.join("+");
			sourceStr += '; Transcription Model: ' + llm_model + "; Prompt: " + prompt;

			// Put the source string in the OCR source field
			$('input[name="rawsource"]').val(sourceStr);

			// If not just OCRing, add the data to the editor using the field mappings
			if(!ocrOnly){

				// Get the categorized data
				let json = data.formatted_json;

				// Color to highlight the form fields that have been changed by Vouchervision-Go
				let vvColor = 'moccasin';

				// Make sure there is data returned before proceeding
				if(json){
					// Cycle through all the fields in the field mapping object for the given prompt
					for (const [field, mapping] of Object.entries(vvMapping[prompt])) {

						// Get the edit form element
						const elem = $('[name="' + mapping + '"]');

						// First modify cultivationstatus if needed, this is a checkbox. Save status if the element is not disabled
						if(json[field] && mapping == "cultivationstatus" && !elem.prop('disabled')) {

							// Set cultivation status and highlight the checkbox
							elem.prop('checked', true);
							elem.css({"accent-color": vvColor, "box-shadow": "0 0 2px 1px gray"});

							// Trigger a fieldChanged event
							fieldChanged(mapping);

						// For the rest of the fields, avoid saving data into disabled, hidden, or non-empty elements
						} else if (json[field] && !elem.prop('disabled') && elem.attr('type') != 'hidden' && elem.val() === '') {

							// Save data returned from VoucherVision to the mapped form element and highlight the form element
							elem.val(json[field]);
							elem.css('background-color', vvColor);

							// Trigger a fieldChanged event
							fieldChanged(mapping);

						}
					}
				}
			}

			// Stop the busy indicator, and re-enable OCR button
			busy.hide();
			$(ocrButton).prop('disabled', false);
		},
		error: function(xhr, status, error) {
			// Failed to get data back from the Vouchervision-Go API
			console.log("Failed to get an OCR response from Vouchervision-Go", xhr, status, error);
			alert("Failed to get an OCR response from Vouchervision-Go");

			// Stop busy indicator, and re-enable OCR button
			busy.hide();
			$(ocrButton).prop('disabled', false);
		}
	});
}



function nlpLbcc(nlpButton,prlid){
	let wcElem = document.getElementById("workingcircle_lbcc-"+prlid);
	if (wcElem) {
		wcElem.style.display = "inline";
	}
	nlpButton.disabled = true;
	var f = nlpButton.form;
	var rawOcr = f.rawtext.innerText;
	if(!rawOcr) rawOcr = f.rawtext.textContent;
	var cnumber = f.cnumber.value;
	var collid = f.collid.value;
	//alert("rpc/nlplbcc.php?collid="+collid+"&catnum="+cnumber+"&rawocr="+rawOcr);
	$.ajax({
		type: "POST",
		url: "rpc/nlplbcc.php",
		data: { rawocr: rawOcr, collid: collid, catnum: cnumber }
	}).done(function( msg ) {
		pushDwcArrToForm(msg, "#ebbb7f");
		nlpButton.disabled = false;
		let wcElem = document.getElementById("workingcircle_lbcc-"+prlid);
		if (wcElem) {
			wcElem.style.display = "none";
		}
	});
}

function nlpSalix(nlpButton,prlid){
	let wcElem = document.getElementById("workingcircle_salix-"+prlid);
	if (wcElem) {
		wcElem.style.display = "inline";
	}
	nlpButton.disabled = true;
	var f = nlpButton.form;
	var rawOcr = f.rawtext.innerText;
	if(!rawOcr) rawOcr = f.rawtext.textContent;
	//alert("rpc/nlpsalix.php?rawocr="+rawOcr);
	$.ajax({
		type: "POST",
		url: "rpc/nlpsalix.php",
		data: { rawocr: rawOcr }
	}).done(function( msg ) {
		pushDwcArrToForm(msg,"#77dd77");
		nlpButton.disabled = false;
		let wcElem = document.getElementById("workingcircle_salix-"+prlid);
		if (wcElem) {
			wcElem.style.display = "none";
		}
	});
}

// confArg (optional 3rd param) may be either a _confidence map object, OR
// omitted. If the parsed message itself carries a "_confidence" key it is used
// as a fallback. Fields keyed lowercase in the form are matched to camelCase
// confidence keys via dwcToFormField (reverse lookup).
function pushDwcArrToForm(msg,bgColor,confArg){
	try{
		var dwcArr = $.parseJSON(msg);
		var f = document.fullform;
		//var fieldsTransfer = "";
		//var fieldsSkip = "";
		var scinameTransferred = false;
		var verbatimElevTransferred = false;

		// Resolve a confidence map: explicit arg wins, else any _confidence on the payload.
		var confidenceMap = (confArg && typeof confArg === "object") ? confArg :
			((dwcArr && typeof dwcArr._confidence === "object") ? dwcArr._confidence : null);

		// Build a reverse lookup: lowercase form name -> camelCase DWC key (for confidence).
		var formNameToDwc = {};
		for(var dwcKey in dwcToFormField){
			formNameToDwc[dwcToFormField[dwcKey]] = dwcKey;
		}

		for(var k in dwcArr){
			try{
				// Skip envelope/meta keys.
				if(k == '_confidence' || k == '_meta') continue;
				if(k != 'family' && k != 'scientificnameauthorship'){
					var elem = f.elements[k];
					var inVal = dwcArr[k];
					if(inVal && elem && elem.value == "" && elem.disabled == false && elem.type != "hidden"){
						if(k == "sciname") scinameTransferred = true;
						if(k == "verbatimelevation") verbatimElevTransferred = true;
						elem.value = inVal;
						// Confidence-based coloring when a score is available; else fall back to bgColor.
						var dwcK = formNameToDwc[k];
						if(confidenceMap && dwcK && typeof confidenceMap[dwcK] !== "undefined" && confidenceMap[dwcK] !== null){
							applyConfidenceToField(elem, dwcK, confidenceMap);
						}
						else{
							elem.style.backgroundColor = bgColor;
						}
						//fieldsTransfer = fieldsTransfer + ", " + k;
						fieldChanged(k);
					}
					else{
						//fieldsSkip = fieldsSkip + ", " + k;
					}
				}
			}
			catch(err){
				//alert(err);
			}
		}
		if(scinameTransferred) verifyFullFormSciName();
		if(verbatimElevTransferred) parseVerbatimElevation(f);
		//if(fieldsTransfer == "") fieldsTransfer = "none";
		//if(fieldsSkip == "") fieldsSkip = "none";
		//alert("Field parsed: " + fieldsTransfer + "\nFields skipped: " + fieldsSkip);
	}
	catch(err){
		//JSON parsing error
		//alert(msg);
		alert(err);
	}
	
}

function getImgRes() {
	const resRadio = document.querySelector('#imgres input[name="resradio"]:checked');
	return resRadio? resRadio.value: getCookie("symbimgres");
}

function nextLabelProcessingImage(imgCnt){
	document.getElementById("labeldiv-"+(imgCnt-1)).style.display = "none";
	var imgObj = document.getElementById("labeldiv-"+imgCnt);
	if(!imgObj){
		imgObj = document.getElementById("labeldiv-1");
		imgCnt = "1";
	}
	imgObj.style.display = "block";
	
	activeImgIndex = imgCnt;
	initImageTool("activeimg-"+imgCnt);
	initImgRes()
	
	return false;
}

function nextRawText(imgCnt,fragCnt){
	document.getElementById("tfdiv-"+imgCnt+"-"+(fragCnt-1)).style.display = "none";
	var fragObj = document.getElementById("tfdiv-"+imgCnt+"-"+fragCnt);
	if(!fragObj) fragObj = document.getElementById("tfdiv-"+imgCnt+"-1");
	fragObj.style.display = "block";
	ocrFragIndex = fragCnt;
	return false;
}

function quickEntryOcrImage(ocrButton, imgidVar, imgCnt, imgURl) {
	console.log("Function quickEntryOcrImage called");
	console.log(imgURl);
	imgCnt = 0; // Reset image counter
	ocrButton.disabled = true; // Disable button to prevent multiple clicks

	// Show loading spinner
	let wcElem = document.getElementById("workingcircle-tess-" + imgCnt);
	if (wcElem) {
		wcElem.style.display = "inline";
	}

	// Get selected OCR 
	let target = document.getElementById("ocr-method").value;
	ocrAnalysisMode = !!(document.getElementById("ocr-analysis") && document.getElementById("ocr-analysis").checked);

	let ocrUrl = "";
	if (target === "external") {
		ocrUrl = "../quickentry/rpc/externalocr.php";
	} else if (target === "others") {
		ocrUrl = "../quickentry/rpc/otherocr.php";
	} else {
		ocrUrl = "../quickentry/rpc/ocrimage.php";
	}

	$.ajax({
		type: "POST",
		url: ocrUrl,
		data: { imgid: imgidVar, target: target, imgurl: imgURl },
		success: function(response) {
			let decodedResponse;
			if (typeof response === "string") {
				try {
					decodedResponse = JSON.parse(response);
				} catch (e) {
					// Plain text response (e.g. tesseract/others) - not JSON.
					decodedResponse = response;
				}
			} else {
				decodedResponse = response;
			}

			let rawtextBox = document.getElementById("rawtext");

			// BRANCH: structured envelope (Azure) vs. plain text (tesseract/others).
			if (isStructuredOcrEnvelope(decodedResponse)) {
				let confidenceMap = (decodedResponse._confidence && typeof decodedResponse._confidence === "object")
					? decodedResponse._confidence : null;

				// Populate matching form fields (only empty/enabled/non-hidden) and
				// color/tooltip each by confidence. Never clobber a human edit.
				for (const [dwcKey, formName] of Object.entries(dwcToFormField)) {
					if (!Object.prototype.hasOwnProperty.call(decodedResponse, dwcKey)) continue;
					let val = decodedResponse[dwcKey];
					if (val === null || typeof val === "undefined" || val === "") continue;

					let elem = document.querySelector('[name="' + formName + '"]');
					if (elem && elem.value === "" && elem.disabled === false && elem.type !== "hidden") {
						elem.value = val;
						applyConfidenceToField(elem, dwcKey, confidenceMap);
						if (typeof fieldChanged === "function") fieldChanged(formName);
					}
				}

				// Also build a readable plain-text version for the rawtext box (reference).
				// Only DWC value fields are included; _confidence/_meta are excluded.
				let plainTextResponse = "";
				for (const [key, value] of Object.entries(decodedResponse)) {
					if (key === "_confidence" || key === "_meta") continue;
					plainTextResponse += `${key}: ${value}\n`;
				}
				if (ocrAnalysisMode) {
					plainTextResponse = normalizeFieldValueText(plainTextResponse);
				}
				storedOcrResponse = plainTextResponse;
				if (rawtextBox) rawtextBox.value = plainTextResponse;
			}
			else {
				// Plain text path (tesseract/others): preserve existing behavior exactly.
				let plainTextResponse = "";
				if (typeof decodedResponse === "object") {
					for (const [key, value] of Object.entries(decodedResponse)) {
						plainTextResponse += `${key}: ${value}\n`;
					}
				} else {
					plainTextResponse = decodedResponse;
				}

				if (ocrAnalysisMode) {
					plainTextResponse = normalizeFieldValueText(plainTextResponse);
				}

				// Store in global variable for later use
				storedOcrResponse = plainTextResponse;

				// Update the textarea
				if (rawtextBox) rawtextBox.value = plainTextResponse;
			}

			if (wcElem) {
				wcElem.style.display = "none";
			}
			ocrButton.disabled = false;
		},
		error: function(xhr, status, error) {
			storedOcrResponse = "OCR Failed";
			console.error("External OCR Error: ", error);
			if (wcElem) {
				wcElem.style.display = "none";
			}
			ocrButton.disabled = false;
		}
	});
}

let storedOcrResponse = "";
let updateState = "needsValidation";  
let ocrAnalysisMode = false;

function normalizeFieldValueText(rawText){
	if(!rawText) return "";
	const normalized = [];
	const lines = rawText.split(/\r?\n/);
	const barcodePattern = /^[A-Z]{1,3}\d{5,}$/i;
	const institutionFallbackParts = [];
	
	const knownFields = ['recordedBy', 'location', 'scientificName', 'eventDate', 'barcode', 'institutionCode', 'image_path'];
	
	for(let i = 0; i < lines.length; i++){
		let line = lines[i].trim();
		if(!line) continue;

		let colonIndex = line.indexOf(":");
		let key = "";
		let value = "";
		
		if(colonIndex === -1){
			key = line;
		} else {
			key = line.slice(0, colonIndex).trim();
			value = line.slice(colonIndex + 1).trim();
		}

		// Check if it's already a known field
		if(knownFields.includes(key)){
			normalized.push(`${key}: ${value}`);
			continue;
		}

		// Check if key or value matches barcode pattern
		const barcodeMatchInKey = barcodePattern.test(key);
		const barcodeMatchInValue = barcodePattern.test(value);

		if (barcodeMatchInKey && !value) {
			normalized.push(`barcode: ${key}`);
			continue;
		}
		else if (barcodeMatchInValue) {
			normalized.push(`barcode: ${value.match(barcodePattern)[0]}`);
			continue;
		}

		// If it has a colon and both key and value, keep it as-is for now
		if(colonIndex !== -1 && key && value){
			institutionFallbackParts.push(value);
			continue;
		}
		
		// Single word or phrase without clear key-value structure
		const spaceIndex = line.indexOf(" ");
		if(spaceIndex !== -1 && colonIndex === -1){
			const firstWord = line.slice(0, spaceIndex).trim();
			const rest = line.slice(spaceIndex + 1).trim();
			if(firstWord && rest){
				institutionFallbackParts.push(rest);
				continue;
			}
		}

		// Look ahead for a value on the next line
		let valueLine = "";
		let j = i + 1;
		while(j < lines.length){
			const nextLine = lines[j].trim();
			if(nextLine){
				valueLine = nextLine;
				break;
			}
			j++;
		}

		if(valueLine){
			institutionFallbackParts.push(valueLine);
			i = j;
		}
		else if(key){
			institutionFallbackParts.push(key);
		}
	}
	
	// Add institution code from fallback parts if we collected any
	if(institutionFallbackParts.length > 0){
		const institutionValue = institutionFallbackParts.join(" ").replace(/\s+/g, " ").trim();
		if(institutionValue){
			normalized.push(`institutionCode: ${institutionValue}`);
		}
	}
	
	return normalized.join("\n");
}

function handleUpdateButtonClick() {
	if (updateState === "needsValidation") {
		confirmOCRresult();
		updateState = "ready";
		const btn = document.getElementById("updateButton");
		btn.innerText = "Update Form";
		btn.value = "Update Form";
		return false;
	} else {
		return UpdateFromWithOCR();
	}
}

// detect changes in the rawtext textarea
window.addEventListener('DOMContentLoaded', function () {
	const rawtextBox = document.getElementById("rawtext");
	const updateButton = document.getElementById("updateButton");

	if (rawtextBox) {
		console.log("textBox udpated");
		rawtextBox.addEventListener("input", function () {
			updateState = "needsValidation";
			updateButton.innerText = "Validate";
			updateButton.value = "Validate";
		});
	}
});

function confirmOCRresult() {
	if (event) event.preventDefault();

	let rawtextBox = document.getElementById("rawtext");

	if (!rawtextBox) {
		console.error("No OCR result box found");
		return false;
	}

	let rawText = rawtextBox.value.trim();

	if (rawText === "") {
		console.error("OCR result is empty");
		alert("OCR result is empty!");
		return false;
	}

	if(!ocrAnalysisMode){
		storedOcrResponse = rawText;
		console.log("OCR response confirmed (no analysis mode)");
		return false;
	}

	rawText = normalizeFieldValueText(rawText);
	rawtextBox.value = rawText;

	let lines = rawText.split("\n");
	let allValid = true;

	lines.forEach((line, index) => {
		line = line.trim();
		if (line === "") return; // skip empty lines

		const colonIndex = line.indexOf(":");
		if (colonIndex === -1) {
			console.error(`Line ${index + 1} is invalid: missing ':' separator.`);
			alert(`Error: Line ${index + 1} is invalid. Missing ':' separator.`);
			allValid = false;
			return;
		}

		// Split key and value
		let key = line.slice(0, colonIndex).trim();
		let value = line.slice(colonIndex + 1).trim();

		// Check key and value are not empty
		if (!key.trim() || !value) {
			console.error(`Line ${index + 1} is invalid: key or value is empty.`);
			alert(`Error: Line ${index + 1} has an empty key or value.`);
			allValid = false;
			return;
		}

		// Check for unwanted quotes in key or value
		if (key.includes('"') || value.includes('"')) {
			console.error(`Line ${index + 1} is invalid: contains quotation marks.`);
			alert(`Error: Line ${index + 1} should not contain quotation marks.`);
			allValid = false;
			return;
		}
	});

	if (!allValid) {
		console.warn("OCR confirmation aborted due to invalid format.");
		return false;
	}

	storedOcrResponse = rawText;
	console.log("OCR response confirmed");
	return false;
}

function UpdateFromWithOCR() {
	if (!storedOcrResponse || storedOcrResponse.trim() === "") {
		console.error("No OCR response available");
		return false;
	}

	let lines = storedOcrResponse.split("\n");

	const fieldGetters = {
		recordedBy: () => document.getElementById("ffrecordedby"),
		location: () => document.getElementById("ffgeowithin"),
		scientificName: () => document.getElementById("ffcurrname"),
		eventDate: () => document.getElementById("ffeventdate"),
		barcode: () => document.getElementById("barcode"),
		institutionCode: () => document.querySelector('input[name="institutioncode"]'),
		image_path: () => document.getElementById("image-path") || document.querySelector('input[name="image_path"]') || document.querySelector('input[name="imgpath"]')
	};

	const barcodePattern = /^[A-Z]{1,3}\d{5,}$/i;
	const institutionFallbackParts = [];
	let institutionAssigned = false;

	lines.forEach(line => {
		if (line.trim() === "") return;

		const colonIndex = line.indexOf(":");
		let key = "";
		let value = "";

		if (colonIndex === -1) {
			key = line.trim();
		} else {
			key = line.slice(0, colonIndex).trim();
			value = line.slice(colonIndex + 1).trim();
		}

		let normalizedKey = key;

		if (!fieldGetters[normalizedKey]) {
			const barcodeMatchInKey = barcodePattern.test(key);
			const barcodeMatchInValue = barcodePattern.test(value);

			if (barcodeMatchInKey && !value) {
				normalizedKey = 'barcode';
				value = key;
			}
			else if (barcodeMatchInValue) {
				normalizedKey = 'barcode';
				value = value.match(barcodePattern)[0];
			}
			else {
				const fallbackTextSource = value || key;
				const fallbackText = fallbackTextSource.trim();
				if (fallbackText) {
					institutionFallbackParts.push(fallbackText);
				} else {
					console.warn(`Unrecognized key '${key}' with empty value in OCR response.`);
				}
				return;
			}
		}

		let field = fieldGetters[normalizedKey] ? fieldGetters[normalizedKey]() : null;

		// Find the input field by key
		if (field) {
			field.value = value;
			field.dispatchEvent(new Event("change"));

			// Find the corresponding label and bold it
			let fieldBlock = field.closest(".field-block") || field.closest(".field-div");
			if (fieldBlock) {
				let label = fieldBlock.querySelector(".field-label");
				if (label) {
					label.classList.add("highlight-label");
				}
			}

			if (normalizedKey === 'institutionCode') {
				institutionAssigned = true;
				// Update the institution code display at the top of the page
				const displayElement = document.getElementById("institution-code-display");
				if (displayElement) {
					displayElement.textContent = value;
				}
			}
		} else {
			console.warn(`Unable to locate input field for key '${normalizedKey}'.`);
		}
	});

	if (!institutionAssigned && institutionFallbackParts.length) {
		const institutionField = fieldGetters['institutionCode'] ? fieldGetters['institutionCode']() : null;
		const institutionValue = institutionFallbackParts.join(" ").replace(/\s+/g, " ").trim();
		if (institutionField && institutionValue) {
			institutionField.value = institutionValue;
			institutionField.dispatchEvent(new Event("change"));
			let fieldBlock = institutionField.closest(".field-block") || institutionField.closest(".field-div");
			if (fieldBlock) {
				let label = fieldBlock.querySelector(".field-label");
				if (label) {
					label.classList.add("highlight-label");
				}
			}
			// Update the institution code display at the top of the page
			const displayElement = document.getElementById("institution-code-display");
			if (displayElement) {
				displayElement.textContent = institutionValue;
			}
		}
	}
	
	// Reset button state after successful update
	const updateButton = document.getElementById("updateButton");
	if (updateButton) {
		updateState = "needsValidation";
		updateButton.innerText = "Validate";
		updateButton.value = "Validate";
	}
	
	// Show success popup after form update
	showFormUpdateSuccessPopup();
	
	return false;
}

function showFormUpdateSuccessPopup() {
	alert("Form has been successfully validated and updated!");
}

function saveOCRResults() {
    const rawTextElement = document.getElementById('rawtext');
    const rawNotesElement = document.querySelector('input[name="rawnotes"]');
    const rawSourceElement = document.querySelector('input[name="rawsource"]');
    const imgId = document.querySelector('input[name="imgid"]').value;

    if (!rawTextElement) {
        alert('Error: Could not find the rawtext textarea.');
        return false;
    }

    const rawTextContent = rawTextElement.value;
    const rawNotesContent = rawNotesElement ? rawNotesElement.value : '';
    const rawSourceContent = rawSourceElement ? rawSourceElement.value : '';

    if (!imgId) {
        alert('Error: Could not find the image ID.');
        return false;
    }

    // Create an AJAX request to send the data to the server
    const xhr = new XMLHttpRequest();
    const url = '../../collections/quickentry/rpc/save_ocr_results.php';

    const params = `imgid=${encodeURIComponent(imgId)}&rawtext=${encodeURIComponent(rawTextContent)}&rawnotes=${encodeURIComponent(rawNotesContent)}&rawsource=${encodeURIComponent(rawSourceContent)}`;

    xhr.open('POST', url, true);
    xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');

    xhr.onload = function() {
        if (xhr.status === 200) {
            alert(xhr.responseText || 'OCR results saved successfully.');
        } else {
            alert('Error saving OCR results. Please try again.');
            console.error('Request failed. Returned status of ' + xhr.status);
        }
    };

    xhr.onerror = function() {
        alert('There was a network error while trying to save.');
        console.error('There was a network error.');
    };

    xhr.send(params);

    return false;
}

$(function() {
	$( "#zoomInfoDialog" ).dialog({
		autoOpen: false,
		position: { my: "left top", at: "right bottom", of: "#zoomInfoDiv" }
	});

	$( "#zoomInfoDiv" ).click(function() {
		$( "#zoomInfoDialog" ).dialog( "open" );
	});
});

function floatImgPanel(){
	$( "#labelProcFieldset" ).css('position', 'fixed');
	$( "#labelProcFieldset" ).css('top', '20px');
	var pos = $( "#labelProcDiv" ).position();
	var posLeft = pos.left - $(window).scrollLeft();
	$( "#labelProcFieldset" ).css('left', posLeft);
	$( "#floatImgDiv" ).hide();
	$( "#draggableImgDiv" ).hide();
	$( "#anchorImgDiv" ).show();
}

function draggableImgPanel(){
	$( "#labelProcFieldset" ).draggable();
	$( "#labelProcFieldset" ).draggable({ cancel: "#labelprocessingdiv" });
	$( "#labelHeaderDiv" ).css('cursor', 'move');
	$( "#labelProcFieldset" ).css('top', '10px');
	$( "#labelProcFieldset" ).css('left', '5px');
	$( "#floatImgDiv" ).hide();
	$( "#draggableImgDiv" ).hide();
	$( "#anchorImgDiv" ).show();
}

function anchorImgPanel(){
	$( "#draggableImgDiv" ).show();
	$( "#floatImgDiv" ).show();
	$( "#anchorImgDiv" ).hide();
	$( "#labelProcFieldset" ).css('position', 'static');
	$( "#labelProcFieldset" ).css('top', '');
	$( "#labelProcFieldset" ).css('left', '');
	try {
		$( "#labelProcFieldset" ).draggable( "destroy" );
		$( "#labelHeaderDiv" ).css('cursor', 'default');
	}
	catch(err) {
	}
}

function nextProcessingImage() {
	var imgCollectionInput = document.getElementById('image-collection-input');
	var imgArr = JSON.parse(imgCollectionInput.value);
	var currentImageIndex = parseInt(document.getElementById('current-image-index').textContent);
	var totalImages = imgArr.length;
	var nextImageIndex = (currentImageIndex + 1) % totalImages; // This ensures the index loops back to 0

	// reference the new image URL from the JS array
	var newImgSrc = imgArr[nextImageIndex]; // This should be the URL of the next image

	// Update the display of the current image index and count
	document.getElementById('current-image-index').textContent = nextImageIndex;
	document.getElementById('image-count').textContent = 'Image ' + (nextImageIndex + 1) + ' of ' + totalImages;
	document.getElementById('activeimg').src = newImgSrc;

	document.getElementById('activeimg').onload = function() {
		initImageTool('activeimg-' + nextImageIndex);
	};

	return false;
}
