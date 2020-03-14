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

	var pluginVersion = '2.0develop-20074.1525';

	var _UIVERSION = 20073;     /* must coincide with Lua core */

	var myModule = {};

	var TTSEngines = {};

	var sysDefaultTTS = "MARY";

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

	function isEmpty( s ) {
		return undefined === s || null === s || "" === s ||
			( "string" === typeof( s ) && null !== s.match( /^\s*$/ ) );
	}

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

	function makeSettingsRow( label, $container, $pred ) {
		var $row = $('<div class="row"/>');
		if ( $pred ) {
			$row.insertAfter( $pred );
		} else {
			$row.appendTo( $container );
		}
		var $col = $( '<div class="col-xs-6 col-sm-6 col-md-4 text-right"><span class="rowlabel"/></div>' )
			.appendTo( $row );
		if ( "" !== ( label || "" ) ) {
			$('span.rowlabel', $col).text( label || "" );
		}
		$col = $( '<div class="col-xs-6 col-sm-6 col-md-8"/>' )
			.appendTo( $row );
		return $col;
	}

	function doSettingsSave() {
		var device = api.getCpanelDeviceId();

		var tts;
		var s = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "TTSConfig") || "";
		try {
			tts = JSON.parse( s );
		} catch (e) {
			tts = { engines: {} };
		}
		tts.defaultengine = $( 'select#tts-engine' ).val() || sysDefaultTTS;
		var opts = {};
		$( '.enginesetting' ).each( function( ix, obj ) {
			var $f = $(obj);
			var val = $f.val() || "";
			if ( ! isEmpty( val ) ) {
				var id = $f.attr( 'id' ).replace( /^val-/, "" );
				var meta = (TTSEngines[tts.defaultengine].options || {})[id];
				/* Write if not empty, not same as default */
				opts[id] = val;
			}
		});
		if ( undefined === tts.engines || ( Array.isArray( tts.engines ) && tts.engines.length == 0 ) ) {
			tts.engines = {};
		}
		tts.engines[tts.defaultengine] = opts;
		tts.version = 1;
		tts.serial = ( tts.serial || 0 ) + 1;
		tts.timestamp = Math.floor( Date.now() / 1000 );
		var ts = JSON.stringify( tts );
		console.log(ts);
		api.setDeviceStatePersistent(device, Sonos.SONOS_SYS_SID, "TTSConfig", ts,
			{
				'onSuccess' : function() {
					/* If that went well, these are assumed to go well. */
					if ( "undefined" === typeof(MultiBox) ) {  /* isALTUI */
						/* For whatever reason this makes ALTUI nuts */
						api.setDeviceState(device, Sonos.SONOS_SYS_SID, "TTSConfig", ts);
					}

					var val = 0;
					val |= $( 'input#debug-plugin' ).is( ':checked' ) ? 1 : 0;
					val |= $( 'input#debug-upnp' ).is( ':checked' ) ? 2 : 0;
					val |= $( 'input#debug-tts' ).is( ':checked' ) ? 4 : 0;
					api.performActionOnDevice( device, Sonos.SONOS_SYS_SID, "SetDebugLogs",
						{ actionArguments: { enable: String(val) } } );

					if ( false ) {
						val = $( 'input#read-queue' ).is( 'checked ' );
						api.performActionOnDevice( device, Sonos.SONOS_SYS_SID, "SetReadQueueContent",
							{ actionArguments: { enable: val ? "1" : "0" } } );
					}

					alert("Settings saved!");
				},
				'onFailure' : function( a,b,c ) {
					alert('There was a problem saving the configuration. Vera/Luup may have been restarting. Please wait a few seconds and try again.');
				}
			}
		); /* setDeviceStateVariable */
	}

	function handleSaveSettingsClick( ev ) {
		try {
			doSettingsSave();
		} catch (e) {
			console.log(e);
			assert(e);
		}
	}

	function changeTTSEngine() {
		var $container = $( 'div#sonos-settings' );
		var $el = $( 'select#tts-engine', $container );
		var eid = $el.val() || sysDefaultTTS;
		var tts;
		var s = api.getDeviceState(api.getCpanelDeviceId(), Sonos.SONOS_SYS_SID, "TTSConfig") || "";
		try {
			tts = JSON.parse( s );
		} catch (e) {
			tts = {};
		}
		tts.engines = tts.engines || {};
		/* Clear all existing option fields */
		$( '.engineopt', $container ).remove();
		if ( TTSEngines[eid] ) {
			var currOpts = tts.engines[eid] || {};
			var $last = $el.closest( 'div.row' );
			var eng = TTSEngines[eid];
			var elist = [];
			for ( var opt in ( eng.options || {} ) ) {
				if ( eng.options.hasOwnProperty( opt ) ) {
					eng.options[opt].id = opt;
					elist.push( eng.options[opt] );
				}
			}
			elist.sort(function( a, b ) {
				var ai = a.index || 32767;
				var bi = b.index || 32767;
				if ( ai === bi ) {
					if ( a.title === b.title ) return 0;
					return ( a.title || "" ) < ( b.title || "" ) ? -1 : 1;
				}
				return ai < bi ? -1 : 1;
			});
			for ( var k=0; k<elist.length; ++k ) {
				var meta = elist[k];
				var $col = makeSettingsRow( ( meta.title || meta.id ) + ":", $container, $last );
				$col.addClass( "form-inline" );
				var $row = $col.closest( 'div.row' );
				$row.attr( 'id', 'eopt-' + meta.id ).addClass( "engineopt" );
				var currVal = undefined === currOpts[meta.id] ? "" : currOpts[meta.id];
				if ( undefined !== meta.values ) {
					var $mm = $( '<select class="form-control form-control-sm"/>' )
						.attr( 'id', 'sel-' + meta.id )
						.appendTo( $col );
					if ( meta.unrestricted ) {
						$( '<option/>' ).val( "*" ).text( "(user-supplied/custom value)" )
							.appendTo( $mm );
					}
					if ( Array.isArray( meta.values ) ) {
						meta.values.sort();
						if ( undefined !== meta.default ) {
							$( '<option/>' ).val( "" ).text( "(engine default: " + meta.default + ")" )
								.prependTo( $mm );
						}
						for ( var ix=0; ix<meta.values.length; ix++ ) {
							$( '<option/>' ).val( meta.values[ix] )
								.text( meta.values[ix] )
								.appendTo( $mm );
						}
					} else {
						var vl = [];
						for ( var key in meta.values ) {
							if ( meta.values.hasOwnProperty( key ) ) {
								vl.push( { id: key, val: meta.values[key] } );
							}
						}
						vl.sort( function( a, b ) {
							var v1 = a.val || a.id;
							var v2 = b.val || b.id;
							if ( v1 == v2 ) return 0;
							return v1 < v2 ? -1 : 1;
						});
						if ( undefined !== meta.default ) {
							$( '<option/>' ).val( "" ).text( "(engine default: " +
								( meta.values[meta.default] ? meta.values[meta.default] : meta.default ) +
								")" ).prependTo( $mm );
						}
						for ( var ix=0; ix<vl.length; ix++ ) {
							$( '<option/>' ).val( vl[ix].id ).text( vl[ix].val )
								.appendTo( $mm );
						}
					}
					/* Add the "real" value field */
					$( '<input/>' ).attr( 'type', 'hidden' )
						.attr( 'id', 'val-' + meta.id )
						.addClass("form-control form-control-sm enginesetting")
						.attr( 'placeholder', 'Enter custom/non-standard value' )
						.val( currVal )
						.appendTo( $col );
					/* Now preselect the menu value */
					var $option = $( 'option[value="' + currVal + '"]', $mm );
					if ( 0 === $option.length ) {
						/* The current value is not a menu choice. If the option allows, make entry field visible */
						if ( meta.unrestricted ) {
							$( 'input#val-' + meta.id ).attr( 'type', 'text' );
							$mm.val( "*" ); /* select custom entry option */
						} else {
							/* No. Force first menu item */
							$( 'option:first', $mm ).prop( 'selected', true );
							currVal = $mm.val();
							$( 'input#val-' + meta.id ).val( currVal );
						}
					} else {
						$mm.val( currVal );
					}
					/* On menu change, manage hidden field value (and possibly visibility) */
					$mm.on( 'change.sonos', function( ev ) {
						var $el = $( ev.currentTarget );
						var val = $el.val();
						var id = $el.attr( 'id' ).replace( /^sel-/, "val-" );
						var $f = $( 'input#' + id );
						if ( "*" === val ) {
							$f.attr( 'type', 'text' ).val( "" );
						} else {
							$f.attr( 'type', 'hidden' ).val( val );
						}
					});
				} else {
					$( '<input type="text" class="form-control form-control-sm enginesetting"/>' )
						.attr( 'id', 'val-' + meta.id )
						.val( currVal )
						.appendTo( $col );
				}
				if ( undefined !== meta.infourl ) {
					$( '<a/>' ).attr( 'href', meta.infourl ).attr( 'target', '_blank' )
						.text( '[info]' ).appendTo( $col );
				}
				if ( undefined !== meta.default ) {
					$( '<div class="inp-default" />' ).text( "Default: " + meta.default )
						.appendTo( $col );
				}
				if ( meta.required ) {
					$( 'span.rowlabel', $row ).addClass( 'inp-required' );
				}
				$last = $row;
			}
		}
	}

	function handleTTSEngineChange( ev ) {
		try {
			changeTTSEngine();
		} catch( e ) {
			console.log( e );
			alert( e );
		}
	}

	function doSettings()
	{
		var k, val;
		var device = api.getCpanelDeviceId();

		if (typeof Sonos.timeoutVar2 != 'undefined') {
			clearTimeout(Sonos.timeoutVar2);
		}

		/* Check agreement of plugin core and UI */
		var s = api.getDeviceState( device, Sonos.SONOS_SYS_SID, "_UIV", { dynamic: false } ) || "0";
		console.log("doSettings() for device " + device + " requires UI version " + _UIVERSION + ", seeing " + s);
		if ( String(_UIVERSION) != s ) {
			api.setCpanelContent( '<div class="sonoswarning" style="border: 4px solid red; padding: 8px;">' +
				" ERROR! The plugin core version and UI version do not agree." +
				" This may cause errors or corrupt your configuration." +
				" Please hard-reload your browser and try again " +
				' (<a href="https://duckduckgo.com/?q=hard+reload+browser" target="_blank">how?</a>).' +
				" If you have update plugin files, you may not have successfully installed all required files," +
				" have left or introduced incompatible files," +
				" or have both compressed and uncompressed copies of the files on your system." +
				" Expected " + String(_UIVERSION) + " got " + String(s) +
				".</div>" );
			return false;
		}

		Sonos_detectBrowser();
		Sonos_defineUIStyle();

		Sonos_initXMLParser();

		var rate = api.getDeviceState(device, Sonos.SONOS_SID, "CheckStateRate") || "";

		var html =  '<div id="sonos-settings" class="sonostab" />';
		api.setCpanelContent(html);

		if ( 0 === $( 'style#sonos-settings-styles' ).length ) {
			$( '<style id="sonos-settings-styles"> \
div#sonos-settings div.row { margin-top: 12px; } \
div.inp-default { color: #666; font-size: 0.80em; } \
.inp-required { font-weight: bold } \
</style>' ).appendTo( $('head') );
		}

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
		$( '<div>Tip: try discovery without installing the discovery patch first--it works much of the time.</div>')
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

		$col = makeSettingsRow( "Default Engine:", $container );
		$col.attr( 'id', 'ttsenginerow' ).addClass( "form-inline" );
		var $el = $( '<select id="tts-engine" class="form-control" />' );
		$el.appendTo( $col );
		$.ajax({
			url: api.getDataRequestURL(),
			data: {
				id: "lr_SonosSystem",
				action: "ttsengines"
			},
			dataType: "json",
			timeout: 15000
		}).done( function( data ) {
			var $opt;
			var $el = $( 'select#tts-engine' );
			TTSEngines = data.engines;
			for ( var eid in ( TTSEngines || {} ) ) {
				if ( TTSEngines.hasOwnProperty( eid ) ) {
					var eng = TTSEngines[eid];
					$opt = $( '<option/>' ).val( eid ).text( eng.name || eid );
					$el.append( $opt );
				}
			}

			var val = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "TTSConfig") || "";
			var tts;
			try {
				tts = JSON.parse( val );
			} catch (e) {
				tts = { engines: {} };
			}
			val = isEmpty( tts.defaultengine ) ? sysDefaultTTS : tts.defaultengine;

			$opt = $( 'option[value="' + val + '"]', $el );
			if ( 0 === $opt.length ) {
				$( '<option/>' ).val( val ).text( val + " (not available)" )
					.appendTo( $el );
			}
			$el.val( val ).on( 'change.sonos', handleTTSEngineChange );
			handleTTSEngineChange();
		}).fail( function() {
			$el.replaceWith( "<span>Failed to load TTS engines; Luup may be reloading. To retry, wait a moment, then go back to the Control tab, then come back here.</span>");
		});

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

		if ( false ) {
			$col = makeSettingsRow( "Read Queue:", $container );
			$( '<label for="read-queue"><input type="checkbox" id="read-queue" value="1">&nbsp;</label>' )
				.appendTo( $col );
			var readQueue = api.getDeviceState(device, Sonos.SONOS_SYS_SID, "FetchQueue") || "0";
			$( 'input#read-queue' ).prop( 'checked', "0" !== readQueue );
		}

		$col = makeSettingsRow( "", $container ); /* Spacer */
		$col = makeSettingsRow( "", $container );
		$el = $('<button id="save-settings" class="btn btn-sm btn-primary">Save Changes</button>');
		$el.on( 'click.sonos', handleSaveSettingsClick ).appendTo( $col );

		$( '<div class="sonos-footer">Sonos Plugin version ' + pluginVersion + '</div>' )
			.appendTo( $container );
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
