//# sourceURL=J_SonosSystem1.js
/**
 * J_SonosSystem1.js
 * Part of the Sonos Plugin for Vera and openLuup
 * Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
 * For license information, see https://github.com/toggledbits/Sonos-Vera
 */
/* globals api,jQuery,$,unescape,setTimeout,MultiBox */
/* jshint multistr: true, laxcomma: true */

//"use strict"; // fails on UI7, works fine with ALTUI

var SonosSystem = (function(api, $) {

	/* unique identifier for this plugin... */
	var uuid = '79bf9374-f989-11e9-884c-dbb32f3fa64a'; /* SonosSystem 2019-12-11 19345 */

	var pluginVersion = '2.0develop-19353';

	var _UIVERSION = 19301;     /* must coincide with Lua core */

	var myModule = {};

	var TTSLanguages = [
						[ "en", "English" ],
						[ "en-GB", "English (British)" ],
						[ "en-US", "English (American)" ],
						[ "en-CA", "English (Canadian)" ],
						[ "en-AU", "English (Australian)" ],
						[ "nl", "Dutch" ],
						[ "fr", "French" ],
						[ "fr-CA", "French (Canadian)" ],
						[ "fr-FR", "French (French)" ],
						[ "de", "German" ],
						[ "it", "Italian" ],
						[ "pt", "Portugese" ],
						[ "pt-BR", "Portugese (Brazilian)" ],
						[ "pt-PT", "Portugese (Portugese)" ],
						[ "ru", 'Russian' ],
						[ "es", "Spanish" ],
						[ "es-mx", "Spanish (Mexican)" ],
						[ "es-es", "Spanish (Spanish)" ]
	];

	var TTSEngines = [
					[ "GOOGLE", "Google" ],
					[ "OSX_TTS_SERVER", 'OSX TTS server' ],
					[ "MICROSOFT", "Microsoft" ],
					[ "MARY", "Mary" ],
					[ "RV", "ResponsiveVoice" ]
	];

	var isOpenLuup = false;

	var Sonos = {
		timeoutVar : undefined,
		timeoutVar2 : undefined,
		timeoutVar3 : undefined,
		browserIE : false,
		parseXml : undefined,

		prevGroups : undefined,
		prevSavedQueues : undefined,
		prevQueue : undefined,
		prevFavRadios : undefined,
		prevFavorites : undefined,
		prevCoordinator : undefined,
		prevOnlineState : undefined,
		prevCurrentAlbumArtUrl : undefined,
		prevTitle : undefined,
		prevAlbum : undefined,
		prevArtist : undefined,
		prevDetails : undefined,
		prevCurrentTrack : undefined,
		prevNbrTracks : undefined,
		prevPlaying : undefined,
		prevActions : undefined,
		prevTransportUri : undefined,
		prevCurrentService : undefined,
		prevCurrentRadio : undefined,
		prevMute : undefined,
		prevVolume : undefined,

		prevModelName : undefined,
		prevIp : undefined,
		prevZone : undefined,
		prevOnlineState2 : undefined,
		prevProxy : undefined,
		prevResultDiscovery : undefined,
		prevPatchInstalled : undefined,

		prevOnlineState3 : undefined,

		SONOS_SID : 'urn:micasaverde-com:serviceId:Sonos1',
		SONOS_SYS_SID : 'urn:toggledbits-com:serviceId:SonosSystem1',
		SONOS_ZONE_SID : 'urn:micasaverde-com:serviceId:Sonos1',
		AVTRANSPORT_SID : 'urn:upnp-org:serviceId:AVTransport',
		RENDERING_CONTROL_SID : 'urn:upnp-org:serviceId:RenderingControl',
		MEDIA_NAVIGATION_SID : 'urn:micasaverde-com:serviceId:MediaNavigation1',
		VOLUME_SID : 'urn:micasaverde-com:serviceId:Volume1',
		DEVICE_PROPERTIES_SID : 'urn:upnp-org:serviceId:DeviceProperties',
		ZONEGROUPTOPOLOGY_SID : 'urn:upnp-org:serviceId:ZoneGroupTopology',
		CONTENT_DIRECTORY_SID : 'urn:upnp-org:serviceId:ContentDirectory',

		buttonBgColor : '#3295F8',
		offButtonBgColor : '#3295F8',
		onButtonBgColor : '#025CB6',
		tableTitleBgColor : '#025CB6'
	};

	function TBD() { alert("TBD"); }

/** ***************************************************************************
 *
 *  S E T T I N G S
 *
 ** **************************************************************************/

	function updatePatchStatus(device) {
		var patchInstalled = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "DiscoveryPatchInstalled") || "0";
		$('span#discovery-state').text( "1" === patchInstalled ? "INSTALLED" : "not installed" );
		$('button#discovery-install').prop( 'disabled', "1" === patchInstalled );
		$('button#discovery-uninstall').prop( 'disabled', "0" === patchInstalled );
	}

	function updateDebugStatus(device) {
		var logs = parseInt( api.getDeviceState( device, Sonos.SONOS_SYS_SID, "DebugLogs" ) || "0" );
		if ( isNaN( logs ) ) {
			logs = 0;
		}
		$( 'input#debug-plugin' ).prop( 'checked', 0 !== ( logs & 1 ) );
		$( 'input#debug-upnp' ).prop( 'checked', 0 !== ( logs & 2 ) );
		$( 'input#debug-tts').prop( 'checked', 0 !== ( logs & 4 ) );
	}

	function handlePatchInstallClick( ev ) {
		var device = api.getCpanelDeviceId();
		api.performActionOnDevice( device, Sonos.SONOS_SYS_SID, "InstallDiscoveryPatch",
			{
				actionArguments: { },
				onSuccess: function() {
					updatePatchStatus(device);
				},
				onFailure: function() {
					alert("Something went wrong. Luup may be restarting. Try again in a moment.");
				}
			}
		);
	}

	function handlePatchUninstallClick( ev ) {
		var device = api.getCpanelDeviceId();
		api.performActionOnDevice( device, Sonos.SONOS_SYS_SID, "UninstallDiscoveryPatch",
			{
				actionArguments: { },
				onSuccess: function() {
					updatePatchStatus(device);
				},
				onFailure: function() {
					alert("Something went wrong. Luup may be restarting. Try again in a moment.");
				}
			}
		);
	}

	function updateDiscoveryStatus(device) {
		var val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "DiscoveryMessage") || "";
		$( '#discovery-status' ).text( val );
		if ( "" !== val && !val.match(/(complet|abort)ed/i ) ) {
			setTimeout( function() { updateDiscoveryStatus(device); }, 500 );
		} else {
			/* Finished. Re-enable button. */
			$("button#discover").prop( 'disabled', false );
		}
	}

	function handleDiscoverClick( ev ) {
		var device = api.getCpanelDeviceId();
		$( ev.target ).prop( 'disabled', true );
		api.performActionOnDevice( device, Sonos.SONOS_SYS_SID, "StartSonosDiscovery",
			{
				actionArguments: { },
				onSuccess: function() {
					$("span#discovery-status").text("Please wait...");
					setTimeout( function() { updateDiscoveryStatus(device); }, 1000 );
				},
				onFailure: function() {
					alert("Something went wrong. Luup may be restarting. Try again in a moment.");
				}
			}
		);
	}

	function makeSettingsRow( label, $container ) {
		var $row = $('<div class="row"/>').appendTo( $container );
		var $col = $( '<div class="col-xs-6 col-sm-6 col-md-4 text-right"><span class="rowlabel"/></div>' )
			.appendTo( $row );
		if ( "" !== ( label || "" ) ) {
			$('span.rowlabel', $col).text( label );
		}
		$col = $( '<div class="col-xs-6 col-sm-6 col-md-8"/>' )
			.appendTo( $row );
		return $col;
	}

	function handleSettingsSaveClick( ev ) {
		var device = api.getCpanelDeviceId();
		api.performActionOnDevice(device, Sonos.SONOS_SYS_SID, 'SetupTTS',
			{
				actionArguments: {
					'DefaultLanguage':$( "select#tts-lang" ).val() || "",
					'DefaultEngine':$( "select#tts-engine" ).val() || "",
					'GoogleTTSServerURL':$( "input#tts-google-url" ).val() || "",
					'OSXTTSServerURL':$( "input#tts-osx-url" ).val() || "",
					'MaryTTSServerURL':$( "input#tts-mary-url" ).val() || "",
					'ResponsiveVoiceTTSServerURL': $( "input#tts-rv-url" ).val() || "",
					'MicrosoftClientId':$( "input#tts-msftid" ).val() || "",
					'MicrosoftClientSecret':$( "input#tts-msftsecret" ).val() || "",
					'MicrosoftOption':$( "input#tts-msftopt" ).val() || "",
					'Pitch':$( "input#tts-pitch" ).val() || "",
					'Rate':$( "input#tts-rate" ).val() || ""
				},
				onSuccess: function() {
					/* If that went well, these are assumed to go well. */
					var val = 0;
					val |= $( 'input#debug-plugin' ).is( ':checked' ) ? 1 : 0;
					val |= $( 'input#debug-upnp' ).is( ':checked' ) ? 2 : 0;
					val |= $( 'input#debug-tts' ).is( ':checked' ) ? 4 : 0;
					api.performActionOnDevice( device, Sonos.SONOS_SYS_SID, "SetDebugLogs",
						{ actionArguments: { enable: String(val) } } );

					val = $( 'input#read-queue' ).is( 'checked ' );
					api.performActionOnDevice( device, Sonos.SONOS_SYS_SID, "SetReadQueueContent",
						{ actionArguments: { enable: val ? "1" : "0" } } );
				},
				onFailure: function() {
					alert("There was a problem saving the settings. Luup may be reloading. Try again in a moment.");
				}
			}
		);
	}

	function doSettings()
	{
		var k, val;
		var device = api.getCpanelDeviceId();

		if (typeof Sonos.timeoutVar2 != 'undefined') {
			clearTimeout(Sonos.timeoutVar2);
		}

		Sonos_detectBrowser();
		Sonos_defineUIStyle();

		Sonos_initXMLParser();

		var rate = api.getDeviceState(device, Sonos.SONOS_SID, "CheckStateRate") || "";

		var html =  '<div id="sonos-settings" class="sonostab" />';
		api.setCpanelContent(html);
		var $container = $( 'div#sonos-settings' );

		var $row = $('<div class="row"/>');
		var $col = $( '<div class="col-xs-12 col-sm-12">Device (Zone) Discovery</div>' )
			.appendTo( $row );
		$row.appendTo( $container );

		/* Discovery Patch */
		$col = makeSettingsRow( "Discovery Patch:", $container );
		$( '<span id="discovery-state">unknown</span').appendTo( $col );
		$( '<button id="discovery-install" class="btn btn-sm">Install</button>' )
			.appendTo( $col );
		$( '<button id="discovery-uninstall" class="btn btn-sm">Uninstall</button>' )
			.appendTo( $col );
		updatePatchStatus( device );
		$( 'button#discovery-install' ).on( 'click.sonos', handlePatchInstallClick );
		$( 'button#discovery-uninstall' ).on( 'click.sonos', handlePatchUninstallClick );

		$col = makeSettingsRow( false, $container );
		$( '<button id="discover" class="btn btn-sm btn-success">Start Discovery</button>' )
			.on( 'click.sonos', handleDiscoverClick )
			.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "DiscoveryMessage");
		$( '<span id="discovery-status"/>' ).text(val || "").appendTo( $col );

		$row = $('<div class="row"/>').appendTo( $container );
		$col = $( '<div class="col-xs-12 col-sm-12">Text-to-Speech (TTS)</div>' )
			.appendTo( $row );

		$col = makeSettingsRow( "Default Language:", $container );
		var $el = $( '<select id="tts-lang" class="form-control" />' );
		$el.appendTo( $col );
		$( '<option/>' ).val( "" ).text("(system default: en)").appendTo( $el );
		for ( k=0; k<TTSLanguages.length; ++k ) {
			$('<option/>').val( TTSLanguages[k][0] )
				.text( TTSLanguages[k][1] )
				.appendTo( $el );
		}
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "DefaultLanguageTTS") || "";
		if ( 0 === $('option[value=' + JSON.stringify(val) + ']', $el ).length ) {
			$('<option/>').val( val ).text( String(val) + " ?" )
				.prependTo( $el );
		}
		$el.val( val );

		$col = makeSettingsRow( "Default Engine:", $container );
		$el = $( '<select id="tts-engine" class="form-control" />' );
		$el.appendTo( $col );
		$( '<option/>' ).val( "" ).text("(system default: GOOGLE)").appendTo( $el );
		for ( k=0; k<TTSEngines.length; ++k ) {
			$('<option/>').val( TTSEngines[k][0] )
				.text( TTSEngines[k][1] )
				.appendTo( $el );
		}
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "DefaultEngineTTS") || "";
		if ( 0 === $('option[value=' + JSON.stringify(val) + ']', $el ).length ) {
			$('<option/>').val( val ).text( String(val) + " ?" )
				.prependTo( $el );
		}
		$el.val( val );

		$col = makeSettingsRow( "Google TTS Server URL:", $container );
		$el = $( '<input id="tts-google-url" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "GoogleTTSServerURL");
		$el.val( val || "" );

		$col = makeSettingsRow( "OSX TTS Server URL:", $container );
		$el = $( '<input id="tts-osx-url" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "OSXTTSServerURL");
		$el.val( val || "" );

		$col = makeSettingsRow( "MaryTTS Server URL:", $container );
		$el = $( '<input id="tts-mary-url" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "MaryTTSServerURL");
		$el.val( val || "" );

		$col = makeSettingsRow( "ResponsiveVoice Server URL:", $container );
		$el = $( '<input id="tts-rv-url" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "ResponsiveVoiceTTSServerURL");
		$el.val( val || "" );

		$col = makeSettingsRow( "Microsoft TTS Client ID:", $container );
		$el = $( '<input id="tts-msftid" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "MicrosoftClientId");
		$el.val( val || "" );

		$col = makeSettingsRow( "Microsoft TTS Client Secret:", $container );
		$el = $( '<input id="tts-msftsecret" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "MicrosoftClientSecret");
		$el.val( val || "" );

		$col = makeSettingsRow( "Microsoft TTS Option:", $container );
		$el = $( '<input id="tts-msftopt" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "MicrosoftOption");
		$el.val( val || "" );

		$col = makeSettingsRow( "Voice Rate (0-2):", $container );
		$el = $( '<input id="tts-rate" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "TTSRate");
		$el.val( val || "" );

		$col = makeSettingsRow( "Voice Pitch (0-1):", $container );
		$el = $( '<input id="tts-pitch" class="form-control">' );
		$el.appendTo( $col );
		val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "TTSPitch");
		$el.val( val || "" );

		$row = $( '<div class="row"/>' );
		$col = $( '<div class="col-xs-12 col-sm-12">Other Settings</div>' )
			.appendTo( $row );
		$row.appendTo( $container );

		if ( !isOpenLuup ) {
			$col = makeSettingsRow( "UPnP Event Proxy:", $container );
			$el = $( '<span id="proxy-state" />' );
			$el.appendTo( $col );
			var devices = api.getListOfDevices();
			var installed = false;
			for (k=0; k<devices.length; k++) {
				if ( devices[k].device_type === "urn:schemas-futzle-com:device:UPnPProxy:1" ) {
					$el.text("Installed (#" + String(devices[k].id) + ")");
					installed = true;
					break;
				}
			}
			if ( ! installed ) {
				$el.text("not installed -- ");
				$( '<a/>' ).attr( 'href', api.getDataRequestURL() + "?id=action&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=CreatePlugin&PluginNum=3716" )
					.attr( 'target', '_blank' )
					.text( "install it now" )
					.appendTo( $col );
			}
		}

		$col = makeSettingsRow( "Debug Logs:", $container );
		$( '<label class="checkbox" for="debug-plugin"><input type="checkbox" id="debug-plugin" value="1">Plugin</label>' )
			.appendTo( $col );
		$( '<label class="checkbox" for="debug-upnp"><input type="checkbox" id="debug-upnp" value="2">UPnP</label>' )
			.appendTo( $col );
		$( '<label class="checkbox" for="debug-tts"><input type="checkbox" id="debug-tts" value="4">TTS Engines</label>' )
			.appendTo( $col );
		updateDebugStatus( device );

		$col = makeSettingsRow( "Read Queue:", $container );
		$( '<label for="read-queue"><input type="checkbox" id="read-queue" value="1">&nbsp;</label>' )
			.appendTo( $col );
		var readQueue = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "FetchQueue") || "0";
		$( 'input#read-queue' ).prop( 'checked', "0" !== readQueue );

		$col = makeSettingsRow( "", $container ); /* Spacer */
		$col = makeSettingsRow( "", $container );
		$el = $('<button id="save-settings" class="btn btn-sm btn-primary">Save Changes</button>');
		$el.on( 'click.sonos', handleSettingsSaveClick ).appendTo( $col );
	}

/** ***************************************************************************
 *
 *  M I S C
 *
 ** **************************************************************************/

	function Sonos_detectBrowser()
	{
		if (navigator.userAgent.toLowerCase().indexOf('msie') >= 0 ||
			navigator.userAgent.toLowerCase().indexOf('trident') >= 0) {
			Sonos.browserIE = true;
		}
		else {
			Sonos.browserIE = false;
		}
	}

	function Sonos_defineUIStyle()
	{
		if (typeof api !== 'undefined') {
			Sonos.buttonBgColor = '#006E47';
			Sonos.offButtonBgColor = '#006E47';
			Sonos.onButtonBgColor = '#00A652';
			Sonos.tableTitleBgColor = '#00A652';
		}
		else {
			Sonos.buttonBgColor = '#3295F8';
			Sonos.offButtonBgColor = '#3295F8';
			Sonos.onButtonBgColor = '#025CB6';
			Sonos.tableTitleBgColor = '#025CB6';
		}
	}

	function Sonos_initXMLParser()
	{
		if (typeof Sonos.parseXml == 'undefined') {
			if (typeof window.DOMParser != "undefined") {
				Sonos.parseXml = function(xmlStr) {
					return ( new window.DOMParser() ).parseFromString(xmlStr, "text/xml");
				};
			}
			else if (typeof window.ActiveXObject != "undefined" && new window.ActiveXObject("Microsoft.XMLDOM")) {
				Sonos.parseXml = function(xmlStr) {
					var xmlDoc = new window.ActiveXObject("Microsoft.XMLDOM");
					xmlDoc.async = "false";
					xmlDoc.loadXML(xmlStr);
					return xmlDoc;
				};
			}
			else {
				Sonos.parseXml = function(xmlStr) {
					return undefined;
				};
			}
		}
	}

/** ***************************************************************************
 *
 * C L O S I N G
 *
 ** **************************************************************************/

	console.log("Initializing SonosSystem (UI7) module");

	myModule = {
		uuid: uuid,
		doSettings: function() { try { doSettings(); } catch(e) { console.log(e); } }
	};
	return myModule;
})(api, $ || jQuery);