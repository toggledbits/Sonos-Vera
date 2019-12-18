//# sourceURL=J_Sonos1.js
/**
 * J_Sonos1.js
 * Part of the Sonos Plugin for Vera and openLuup
 * Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
 * For license information, see https://github.com/toggledbits/Sonos-Vera
 */
/* globals api,jQuery,$,unescape,ace,Promise,setTimeout,MultiBox */
/* jshint multistr: true, laxcomma: true */

//"use strict"; // fails on UI7, works fine with ALTUI

var Sonos = (function(api, $) {

	/* unique identifier for this plugin... */
	var uuid = '79bf9374-f989-11e9-884c-dbb32f3fa64a'; /* SonosSystem 2019-12-11 19345 */

	var pluginVersion = '2.0develop-19352';

	var _UIVERSION = 19301;     /* must coincide with Lua core */

	var myModule = {};

	var timeoutVar;
	var timeoutVar2;
	var timeoutVar3;
	var browserIE = false;
	var parseXml;
	var prevGroups;
	var prevSavedQueues;
	var prevQueue;
	var prevFavRadios;
	var prevFavorites;
	var prevCoordinator;
	var prevOnlineState;
	var prevCurrentAlbumArtUrl;
	var prevTitle;
	var prevAlbum;
	var prevArtist;
	var prevDetails;
	var prevCurrentTrack;
	var prevNbrTracks;
	var prevPlaying;
	var prevActions;
	var prevTransportUri;
	var prevCurrentService;
	var prevCurrentRadio;
	var prevMute;
	var prevVolume;
	var prevModelName;
	var prevIp;
	var prevZone;
	var prevOnlineState2;
	var prevProxy;
	var prevResultDiscovery;
	var prevPatchInstalled;
	var prevOnlineState3;
	var SONOS_SID = 'urn:micasaverde-com:serviceId:Sonos1';
	var SONOS_SYS_SID = 'urn:toggledbits-com:serviceId:SonosSystem1';
	var AVTRANSPORT_SID = 'urn:upnp-org:serviceId:AVTransport';
	var RENDERING_CONTROL_SID = 'urn:upnp-org:serviceId:RenderingControl';
	var MEDIA_NAVIGATION_SID = 'urn:micasaverde-com:serviceId:MediaNavigation1';
	var VOLUME_SID = 'urn:micasaverde-com:serviceId:Volume1';
	var DEVICE_PROPERTIES_SID = 'urn:upnp-org:serviceId:DeviceProperties';
	var ZONEGROUPTOPOLOGY_SID = 'urn:upnp-org:serviceId:ZoneGroupTopology';
	var CONTENT_DIRECTORY_SID = 'urn:upnp-org:serviceId:ContentDirectory';
	var buttonBgColor = '#3295F8';
	var offButtonBgColor = '#3295F8';
	var onButtonBgColor = '#025CB6';
	var tableTitleBgColor = '#025CB6';

	/* Get parent state */
	function getParentState( varName, myid ) {
		var me = api.getDeviceObject( myid || api.getCpanelDeviceId() );
		return api.getDeviceState( me.id_parent || me.id, SONOS_SYS_SID, varName );
	}

	/* Set parent state */
	function setParentState( varName, val, myid ) {
		var me = api.getDeviceObject( myid || api.getCpanelDeviceId() );
		return api.setDeviceStatePersistent( me.id_parent || me.id, SONOS_SYS_SID, varName, val );
	}

	function doPlayer(device)
	{
		if (typeof timeoutVar != 'undefined') {
			clearTimeout(timeoutVar);
		}

		Sonos_detectBrowser();
		Sonos_defineUIStyle();

		Sonos_initXMLParser();

		var html = '';

		var minVolume = 0;
		var maxVolume = 100;

		html += '<table cellpadding="2">';
		html += '<tr>';
		html += '<td rowspan=6><img id="albumArt" width="100" height="100"/></td>';
		html += '<td id="service"></td>';
		html += '<td id="radio"></td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td id="trackLabel">Track:</td>';
		html += '<td id="track"></td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td id="artistLabel">Artist:</td>';
		html += '<td id="artist"></td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td id="albumLabel">Album:</td>';
		html += '<td id="album"></td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td id="titleLabel">Track title:</td>';
		html += '<td id="title"></td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td id="detailsLabel"></td>';
		html += '<td id="details"></td>';
		html += '</tr>';
		html += '</table>';
		html += '<DIV>';
		html += '<table>';
		html += '<tr>';
		html += '<td>';
		html += '<button id="prevTrack" type="button" class="btn btn-sm sonosbtn">Prev</button>';
		html += '</td>';
		html += '<td>';
		html += '<button id="play" type="button" class="btn btn-sm sonosbtn">Play</button>';
		html += '</td>';
		html += '<td>';
		html += '<button id="pause" type="button" class="btn btn-sm sonosbtn">Pause</button>';
		html += '</td>';
		html += '<td>';
		html += '<button id="stop" type="button" class="btn btn-sm sonosbtn">Stop</button>';
		html += '</td>';
		html += '<td>';
		html += '<button id="nextTrack" type="button" class="btn btn-sm sonosbtn">Next</button>';
		html += '</td>';
		html += '<td>Volume:</td>';
		html += '<td id="volume"></td>';
		html += '<td>';
		html += '<button id="volumeDown" type="button" class="btn btn-sm sonosbtn">-</button>';
		html += '</td>';
		html += '<td>';
		html += '<button id="volumeUp" type="button" class="btn btn-sm sonosbtn">+</button>';
		html += '</td>';
		html += '<td>';
		html += '<select id="newVolume" class="form-control form-control-sm">';
		for (i=minVolume; i<=maxVolume; i++) {
			html += '<option value="' + i + '">' + i + '</option>';
		}
		html += '</select>';
		html += '</td>';
		html += '<td>';
		html += '<button id="volumeSet" type="button" class="btn btn-sm sonosbtn">Set</button>';
		html += '</td>';
		html += '<td>';
		html += '<button id="mute" type="button" class="btn btn-sm sonosbtn">Mute</button>';
		html += '</td>';
		html += '</tr>';
		html += '</table>';
		html += '</DIV>';
		html += '<DIV>';
		html += '<table>';
		html += '<tr>';
		html += '<td>Audio Input:</td>';
		html += '<td class="form-inline">';
		html += '<select id="audioInputs" class="form-control form-control-sm"/>';
		html += '<button id="playAudioInput" type="button" class="btn btn-sm sonosbtn">Play</button>';
		html += '</td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Sonos playlist:</td>';
		html += '<td class="form-inline">';
		html += '<select id="savedQueues" class="form-control form-control-sm"/>';
		html += '<button id="playSQ" type="button" class="btn btn-sm sonosbtn">Play</button>';
		html += '</td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Queue:</td>';
		html += '<td class="form-inline">';
		html += '<select id="queue" class="form-control form-control-sm"/>';
		html += '<button id="playQueue" type="button" class="btn btn-sm sonosbtn">Play</button>';
		html += '<button id="clearQueue" type="button" class="btn btn-sm sonosbtn">Clear</button>';
		html += '</td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Favorite radios:</td>';
		html += '<td class="form-inline">';
		html += '<select id="favRadios" class="form-control form-control-sm"/>';
		html += '<button id="playFavRadio" type="button" class="btn btn-sm sonosbtn">Play</button>';
		html += '</td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Sonos favorites:</td>';
		html += '<td class="form-inline">';
		html += '<select id="favorites" class="form-control form-control-sm"/>';
		html += '<button id="playFavorite" type="button" class="btn btn-sm sonosbtn">Play</button>';
		html += '</td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>URI:</td>';
		html += '<td class="form-inline">';
		html += '<select id="protocol" class="form-control form-control-sm">';
		html += '<option value="" selected></option>';
		html += '<option value="x-file-cifs">x-file-cifs</option>';
		html += '<option value="file">file</option>';
		html += '<option value="x-rincon">x-rincon</option>';
		html += '<option value="x-rincon-mp3radio">x-rincon-mp3radio</option>';
		html += '<option value="x-rincon-playlist">x-rincon-playlist</option>';
		html += '<option value="x-rincon-queue">x-rincon-queue</option>';
		html += '<option value="x-rincon-stream">x-rincon-stream</option>';
		html += '<option value="x-sonosapi-stream">x-sonosapi-stream</option>';
		html += '<option value="x-sonosapi-radio">x-sonosapi-radio</option>';
		html += '<option value="AI">Audio input</option>';
		html += '<option value="SQ">Sonos playlist</option>';
		html += '<option value="SF">Sonos favorite</option>';
		html += '<option value="FR">Favorite radio</option>';
		html += '<option value="TR">TuneIn radio</option>';
		html += '<option value="SR">Sirius radio</option>';
		html += '<option value="GZ">Group zone</option>';
		html += '</select>';
		html += '<input id="uri" type="text" class="form-control form-control-sm"/>';
		html += '<button id="playUri" type="button" class="btn btn-sm sonosbtn">Play</button>';
		html += '</td>';
		html += '</tr>';
		html += '</table>';
		html += '</DIV>';

		//html += '<p id="debug">';
		
		api.setCpanelContent(html);
		$("button#prevTrack").on( "click.sonos", function( ev ) { Sonos_prevTrack(device); } );
		$("button#play").on( "click.sonos", function( ev ) { Sonos_play(device); } );
		$("button#pause").on( "click.sonos", function( ev ) { Sonos_pause(device); } );
		$("button#stop").on( "click.sonos", function( ev ) { Sonos_stop(device); } );
		$("button#nextTrack").on( "click.sonos", function( ev ) { Sonos_nextTrack(device); } );
		$("button#volumeUp").on( "click.sonos", function( ev ) { Sonos_volumeUp(device); } );
		$("button#volumeDown").on( "click.sonos", function( ev ) { Sonos_volumeDown(device); } );
		$("button#volumeSet").on( "click.sonos", function( ev ) { Sonos_setVolume(device); } );
		$("button#mute").on( "click.sonos", function( ev ) { Sonos_mute(device); } );
		$("button#playAudioInput").on( "click.sonos", function( ev ) { Sonos_playAudioInput(device); } );
		$("button#playSQ").on( "click.sonos", function( ev ) { Sonos_playSQ(device); } );
		$("button#playQueue").on( "click.sonos", function( ev ) { Sonos_playQueue(device); } );
		$("button#clearQueue").on( "click.sonos", function( ev ) { Sonos_clearQueue(device); } );
		$("button#playFavRadio").on( "click.sonos", function( ev ) { Sonos_playFavRadio(device); } );
		$("button#playFavorite").on( "click.sonos", function( ev ) { Sonos_playFavorite(device); } );
		$("button#playUri").on( "click.sonos", function( ev ) { Sonos_playUri(device); } );

		Sonos_refreshPlayer(device);
	}

	function doHelp(device)
	{
		var html, pos1, pos2;
		Sonos_defineUIStyle();

		Sonos_initXMLParser();

		var zone = api.getDeviceState(device, DEVICE_PROPERTIES_SID, "ZoneName", 1);
		var uuid = api.getDeviceState(device, DEVICE_PROPERTIES_SID, "SonosID", 1);
		var groups = api.getDeviceState(device, ZONEGROUPTOPOLOGY_SID, "ZoneGroupState", 1);

		var members;
		if (groups != undefined && groups != "") {
			var xmlgroups = parseXml(groups);
			if (typeof xmlgroups != 'undefined') {
				members = xmlgroups.getElementsByTagName("ZoneGroupMember");
			}
		}

		var version = getParentState("PluginVersion", device);
		if (version == undefined) {
			version = '';
		}

		html = '';

		html += '<table cellspacing="10">';
		html += '<tr>';
		html += '<td>Plugin version:</td>';
		html += '<td>' + version + '</td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Github/Wiki:</td>';
		html += '<td><a href="https://github.com/toggledbits/Sonos-Vera">link</a></td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Community Forum:</td>';
		html += '<td><a href="https://community.getvera.com/c/plugins-and-plugin-development/sonos-plugin">link</a></td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Sonos zone:</td>';
		html += '<td>' + zone + '</td>';
		html += '</tr>';
		html += '<tr>';
		html += '<td>Sonos UUID:</td>';
		html += '<td>' + uuid + '</td>';
		html += '</tr>';
		html += '</table>';

		html += '<table border="1">';
		html += '<tr align="center" style="background-color: '+ tableTitleBgColor + '; color: white">';
		html += '<th>Description</td>';
		html += '<th>Standard URI</td>';
		html += '<th>Alternative URI for PlayURI</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>Sonos queue</td>';
		html += '<td>x-rincon-queue:' + uuid + '#0</td>';
		html += '<td>Q:</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>Third item in Sonos queue</td>';
		html += '<td>x-rincon-queue:' + uuid + '#0 *</td>';
		html += '<td>Q:3</td>';
		html += '</tr>';
		
		var zoneUUID, zoneName, channelMapSet, isZoneBridge;

		if (typeof members != 'undefined') {
			for (i=0; i<members.length; i++) {
				zoneUUID = Sonos_extractXmlAttribute(members[i], 'UUID');
				zoneName = Sonos_extractXmlAttribute(members[i], 'ZoneName');
				channelMapSet = Sonos_extractXmlAttribute(members[i], 'ChannelMapSet');
				isZoneBridge = Sonos_extractXmlAttribute(members[i], 'IsZoneBridge');
				if (zoneName != zone && channelMapSet == undefined && isZoneBridge != "1") {
					html += '<tr>';
					html += '<td>Group with master zone "' + zoneName + '"</td>';
					html += '<td>x-rincon:' + zoneUUID + '</td>';
					html += '<td>GZ:' + zoneName + '</td>';
					html += '</tr>';
				}
			}
		}

		html += '<tr>';
		html += '<td>Local audio input</td>';
		html += '<td>x-rincon-stream:' + uuid + '</td>';
		html += '<td>AI:</td>';
		html += '</tr>';

		if (typeof members != 'undefined') {
			for (i=0; i<members.length; i++) {
				zoneUUID = Sonos_extractXmlAttribute(members[i], 'UUID');
				zoneName = Sonos_extractXmlAttribute(members[i], 'ZoneName');
				channelMapSet = Sonos_extractXmlAttribute(members[i], 'ChannelMapSet');
				isZoneBridge = Sonos_extractXmlAttribute(members[i], 'IsZoneBridge');
				if (channelMapSet == undefined && isZoneBridge != "1") {
					html += '<tr>';
					html += '<td>Audio input of zone "' + zoneName + '"</td>';
					html += '<td>x-rincon-stream:' + zoneUUID + '</td>';
					html += '<td>AI:' + zoneName + '</td>';
					html += '</tr>';
				}
			}
		}

		html += '<tr>';
		html += '<td>TuneIn radio with sid 50486</td>';
		html += '<td>x-sonosapi-stream:s50486?sid=254&flags=32 **</td>';
		html += '<td>TR:50486</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>Sirius radio with sid shade45</td>';
		html += '<td>x-sonosapi-hls:r%3ashade45?sid=37&flags=288 **</td>';
		html += '<td>SR:shade45</td>';
		html += '</tr>';

		var line, pos, title, value;
		
		var favRadios = api.getDeviceState(device, CONTENT_DIRECTORY_SID, "FavoritesRadios", 1);
		if (favRadios != undefined && favRadios != "") {
			pos = favRadios.indexOf('\n', 0);
			if (pos >= 0) {
				line = favRadios.substring(0, pos);
				pos2 = line.indexOf('@');
				if (pos2 >= 0) {
					title = line.substr(pos2+1);
					html += '<tr>';
					html += '<td>Favorite radio "' + title + '"</td>';
					html += '<td></td>';
					html += '<td>FR:' + title + '</td>';
					html += '</tr>';
				}
			}
		}

		var savedQueues = api.getDeviceState(device, CONTENT_DIRECTORY_SID, "SavedQueues", 1);
		if (savedQueues != undefined && savedQueues != "") {
			pos1 = 0;
			pos2 = savedQueues.indexOf('\n', pos1);
			while (pos2 >= 0) {
				line = savedQueues.substring(pos1, pos2);
				var pos3 = line.indexOf('@');
				if (pos3 >= 0) {
					value = line.substring(0, pos3);
					title = line.substr(pos3+1);
					html += '<tr>';
					html += '<td>Sonos playlist "' + title + '"</td>';
					html += '<td>file:///jffs/settings/savedqueues.rsq#' + value + '</td>';
					html += '<td>SQ:' + title + '</td>';
					html += '</tr>';
				}
				pos1 = pos2+1;
				pos2 = savedQueues.indexOf('\n', pos1);
			}
		}

		html += '</table>';
		html += '<p>* Seek action is then required to select the right item</p>';
		html += '<p>** Meta data have to be provided in addition to the standard URI</p>';

		var variables = [	[ AVTRANSPORT_SID, "AVTransportURI" ],
							[ AVTRANSPORT_SID, "AVTransportURIMetaData" ],
							[ AVTRANSPORT_SID, "CurrentTrackURI" ],
							[ AVTRANSPORT_SID, "CurrentTrackMetaData" ],
							[ ZONEGROUPTOPOLOGY_SID, "ZoneGroupState" ],
							[ SONOS_SID, 'SonosServicesKeys' ] ];
		html += '<table border="1">';
		html += '<tr align="center" style="background-color: '+ tableTitleBgColor + '; color: white">';
		html += '<th>Variable</td>';
		html += '<th>Value</td>';
		html += '</tr>';
		for (i=0; i<variables.length; i++) {
			value = api.getDeviceState(device, variables[i][0], variables[i][1], 1);
			if (value == undefined) {
				value = '';
			}
			html += '<tr>';
			html += '<td>' + variables[i][1] + '</td>';
			html += '<td>' + Sonos_escapeHtmlSpecialChars(value) + '</td>';
			html += '</tr>';
		}
		html += '</table>';

		html += '<BR>';

		api.setCpanelContent(html);
	}

	function doGroup(device)
	{
		Sonos_detectBrowser();
		Sonos_defineUIStyle();

		Sonos_initXMLParser();

		var html = '<DIV id="groupSelection"/>';

		html += '<BR>';
		html += '<button type="button" style="background-color:' + buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_refreshGroupSelection('+device+');">Refresh</button>';
		html += '<button type="button" style="margin-left: 10px; background-color:' + buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_selectAllMembers(true);">Select All</button>';
		html += '<button type="button" style="margin-left: 10px; background-color:' + buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_selectAllMembers(false);">Unselect All</button>';
		html += '<button id="applyGroup" type="button" style="margin-left: 10px; background-color:' + buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_updateGroup('+device+');">Apply</button>';

		//html += '<p id="debug">';

		api.setCpanelContent(html);

		Sonos_refreshGroupSelection(device);
	}

	function Sonos_refreshGroupSelection(device)
	{
		var html = '';
		var disabled = true;

		var groupMembers = api.getDeviceState(device, ZONEGROUPTOPOLOGY_SID, "ZonePlayerUUIDsInGroup", 1);
		var groups = api.getDeviceState(device, ZONEGROUPTOPOLOGY_SID, "ZoneGroupState", 1);
		if (groups != undefined && groups != "") {
			var xmlgroups = parseXml(groups);
			if (typeof xmlgroups != 'undefined') {
				var members = xmlgroups.getElementsByTagName("ZoneGroupMember");
				var nb=0;
				for (i=0; i<members.length; i++) {
					var name = Sonos_extractXmlAttribute(members[i], 'ZoneName');
					var uuid = Sonos_extractXmlAttribute(members[i], 'UUID');
					var invisible = Sonos_extractXmlAttribute(members[i], 'Invisible');
					var channelMapSet = Sonos_extractXmlAttribute(members[i], 'ChannelMapSet');
					var isZoneBridge = Sonos_extractXmlAttribute(members[i], 'IsZoneBridge');
					if (isZoneBridge != "1" && (channelMapSet == undefined || invisible == '1')) {
						html += '<input id="GroupMember' + nb +'" type="checkbox"';
						if (groupMembers.search(uuid) >= 0) {
							html += ' checked';
							disabled = false;
						}
						html += ' value="' + name + '" onchange="Sonos_updateGroupSelection();">' +
							(false /* ??? */ ? "&nbsp;(group coordinator)" : "") +
							name + '<BR>';
						nb++;
					}
				}
			}
		}

		jQuery('#groupSelection').html(html);
		jQuery('#applyGroup').get(0).disabled = disabled;
	}

	function Sonos_showTTS(device)
	{
		if (typeof timeoutVar3 != 'undefined') {
			clearTimeout(timeoutVar3);
		}

		Sonos_detectBrowser();
		Sonos_defineUIStyle();

		var html = '';

		var minVolume = 0;
		var maxVolume = 100;

		var engines = [	[ "GOOGLE", "Google" ],
						[ "OSX_TTS_SERVER", 'OSX TTS server' ],
						[ "MICROSOFT", "Microsoft" ],
						[ "MARY", "Mary" ],
						[ "RV", "ResponsiveVoice" ] ];
		var defaultEngine = api.getDeviceState(device, SONOS_SID, "DefaultEngineTTS", 1);
		if (defaultEngine == undefined) {
			defaultEngine = 'GOOGLE';
		}
		var languages = [	[ "en", "English" ],
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
							[ "es-es", "Spanish (Spanish)" ] ];
		var defaultLanguage = getParentState("DefaultLanguageTTS", device);
		if (defaultLanguage == undefined) {
			defaultLanguage = 'en';
		}

		var GoogleServerURL = api.getDeviceState(device, SONOS_SID, "GoogleTTSServerURL", 1);
		if (GoogleServerURL == undefined) {
			GoogleServerURL = '';
		}

		var serverURL = api.getDeviceState(device, SONOS_SID, "OSXTTSServerURL", 1);
		if (serverURL == undefined) {
			serverURL = '';
		}

		var MaryServerURL = api.getDeviceState(device, SONOS_SID, "MaryTTSServerURL", 1);
		if (MaryServerURL == undefined) {
			MaryServerURL = '';
		}

		var RVServerURL = api.getDeviceState(device, SONOS_SID, "ResponsiveVoiceTTSServerURL", 1);
		if (RVServerURL == undefined) {
			RVServerURL = '';
		}
		var clientId = api.getDeviceState(device, SONOS_SID, "MicrosoftClientId", 1);
		if (clientId == undefined) {
			clientId = '';
		}
		var clientSecret = api.getDeviceState(device, SONOS_SID, "MicrosoftClientSecret", 1);
		if (clientSecret == undefined) {
			clientSecret = '';
		}
		var option = api.getDeviceState(device, SONOS_SID, "MicrosoftOption", 1);
		if (option == undefined) {
			option = '';
		}
		var rate = api.getDeviceState(device, SONOS_SID, "TTSRate", 1);
		if (rate == undefined) {
			rate = '';
		}
		var pitch = api.getDeviceState(device, SONOS_SID, "TTSPitch", 1);
		if (pitch == undefined) {
			pitch = '';
		}

		html += '<table>';

		html += '<tr>';
		html += '<td>Text:</td>';
		html += '<td>';
		html += '<textarea id="text" cols="54" rows="3"></textarea>';
		html += '</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>Language:</td>';
		html += '<td>';
		html += '<select id="language1" onChange="Sonos_selectLang();">';
		for (i=0; i<languages.length; i++) {
			html += '<option';
			if (languages[i][0] == defaultLanguage) {
				html += ' selected';
			}
			html += ' value="' + languages[i][0] + '">' + languages[i][1] + '</option>';
		}
		html += '</select>';
		html += '<input id="language" type="text" value="' + defaultLanguage + '" style="margin-left: 5px; width: 50px"/>';
		html += '</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>Engine:</td>';
		html += '<td>';
		html += '<select id="engine">';
		for (i=0; i<engines.length; i++) {
			html += '<option';
			if (engines[i][0] == defaultEngine) {
				html += ' selected';
			}
			html += ' value="' + engines[i][0] + '">' + engines[i][1] + '</option>';
		}
		html += '</select>';
		html += '</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>Zones:</td>';
		html += '<td>';
		html += '<input id="NewGroup" type="radio" name="GroupTTS" checked value="NewGroup"/>Current zone';
		html += '<input id="CurrentGroup" type="radio" name="GroupTTS" style="margin-left: 10px" value="CurrentGroup"/>Current group';
		html += '<input id="GroupAll" type="radio" name="GroupTTS" style="margin-left: 10px" value="GroupAll"/>All zones';
		html += '</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>Volume:</td>';
		html += '<td>';
		html += '<select id="volumeTTS" style="margin-right: 10px">';
		html += '<option selected value=""></option>';
		for (i=minVolume; i<=maxVolume; i++) {
			html += '<option value="' + i + '">' + i + '</option>';
		}
		html += '</select>';
		html += 'Apply volume to all zones';
		html += '<input id="GroupVolume" type="checkbox" style="margin-left: 10px" value="GroupVolume"/>';
		html += '</td>';
		html += '</tr>';

		html += '<tr>';
		html += '<td>';
		html += '<button id="say" type="button" style="background-color:' + buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_say('+device+');">Say</button>';
		html += '</td>';
		html += '<td></td>';
		html += '</tr>';

		html += '</table>';

		//html += '<p id="debug">';

		api.setCpanelContent(html);

		prevOnlineState3 = undefined;

		Sonos_refreshTTS(device);
	}

	function Sonos_detectBrowser()
	{
		if (navigator.userAgent.toLowerCase().indexOf('msie') >= 0 ||
			navigator.userAgent.toLowerCase().indexOf('trident') >= 0) {
			browserIE = true;
		}
		else {
			browserIE = false;
		}
	}

	function Sonos_defineUIStyle()
	{
		if (typeof api !== 'undefined') {
			buttonBgColor = '#006E47';
			offButtonBgColor = '#006E47';
			onButtonBgColor = '#00A652';
			tableTitleBgColor = '#00A652';
		}
		else {
			buttonBgColor = '#3295F8';
			offButtonBgColor = '#3295F8';
			onButtonBgColor = '#025CB6';
			tableTitleBgColor = '#025CB6';
		}
		
		if ( $("style#sonos").length > 0 ) return;
		
		$( '<style id="sonos"> \
button.sonosbtn { background-color: ' + buttonBgColor + '; color: white; } \
button.sonosbtn.sonoson { background-color: ' + onButtonBgColor + '; } \
</style>' ).appendTo( $('head') );
	}

	function Sonos_initXMLParser()
	{
		if (typeof parseXml == 'undefined') {
			if (typeof window.DOMParser != "undefined") {
				parseXml = function(xmlStr) {
					return ( new window.DOMParser() ).parseFromString(xmlStr, "text/xml");
				};
			}
			else if (typeof window.ActiveXObject != "undefined" && new window.ActiveXObject("Microsoft.XMLDOM")) {
				parseXml = function(xmlStr) {
					var xmlDoc = new window.ActiveXObject("Microsoft.XMLDOM");
					xmlDoc.async = "false";
					xmlDoc.loadXML(xmlStr);
					return xmlDoc;
				};
			}
			else {
				parseXml = function(xmlStr) {
					return undefined;
				};
			}
		}
	}

	function Sonos_extractXmlTag(parent, tag)
	{
		var value;
		for (j=0; j<parent.childNodes.length; j++) {
			if (parent.childNodes[j].tagName == tag) {
				value = parent.childNodes[j].textContent;
				break;
			}
		}
		return value;
	}

	function Sonos_extractXmlAttribute(node, attribute)
	{
		return node.getAttribute(attribute);
	}

	function Sonos_escapeHtmlSpecialChars(unsafe)
	{
		return String(unsafe)
				.replace(/&/g, "&amp;")
				.replace(/</g, "&lt;")
				.replace(/>/g, "&gt;")
				.replace(/"/g, "&quot;");
	}

	function Sonos_refreshPlayer(device)
	{
		var html, pos1, pos2;
		var uuid = api.getDeviceState(device, DEVICE_PROPERTIES_SID, "SonosID", 1);

		var groups = api.getDeviceState(device, ZONEGROUPTOPOLOGY_SID, "ZoneGroupState", 1);
		if (groups != undefined && groups != "" && prevGroups != groups) {
			var xmlgroups = parseXml(groups);
			if (typeof xmlgroups != 'undefined') {
				var html = "";
				var members = xmlgroups.getElementsByTagName("ZoneGroupMember");
				for (i=0; i<members.length; i++) {
					var name = Sonos_extractXmlAttribute(members[i], 'ZoneName');
					var channelMapSet = Sonos_extractXmlAttribute(members[i], 'ChannelMapSet');
					var isZoneBridge = Sonos_extractXmlAttribute(members[i], 'IsZoneBridge');
					if (typeof name != 'undefined' && channelMapSet == undefined && isZoneBridge != "1") {
						var title = name;
						if (title.length > 60) {
							title = title.substr(0, 60) + '...';
						}
						html += '<option value="AI:' + name + '">' + title + '</option>';
					}
				}
				jQuery('#audioInputs').html(html);
			}
			prevGroups = groups;
		}

		var savedQueues = api.getDeviceState(device, CONTENT_DIRECTORY_SID, "SavedQueues", 1);
		if (savedQueues != undefined && savedQueues != prevSavedQueues) {
			html = "";
			pos1 = 0;
			pos2 = savedQueues.indexOf('\n', pos1);
			while (pos2 >= 0) {
				var line = savedQueues.substring(pos1, pos2);
				var pos3 = line.indexOf('@');
				if (pos3 >= 0) {
					var value = line.substring(0, pos3);
					var title = line.substr(pos3+1);
					if (title.length > 60) {
						title = title.substr(0, 60) + '...';
					}
					html += '<option value="' + value + '">' + title + '</option>';
				}
				pos1 = pos2+1;
				pos2 = savedQueues.indexOf('\n', pos1);
			}
			jQuery('#savedQueues').html(html);
			prevSavedQueues = savedQueues;
		}

		var queue = api.getDeviceState(device, CONTENT_DIRECTORY_SID, "Queue", 1);
		if (queue != undefined && queue != prevQueue) {
			html = "";
			pos1 = 0;
			pos2 = queue.indexOf('\n', pos1);
			while (pos2 >= 0) {
				var title = queue.substring(pos1, pos2);
				if (title.length > 50) {
					title = title.substr(0, 50) + '...';
				}
				html += '<option>' + title + '</option>';
				pos1 = pos2+1;
				pos2 = queue.indexOf('\n', pos1);
			}
			jQuery('#queue').html(html);
			prevQueue = queue;
		}

		var favRadios = api.getDeviceState(device, CONTENT_DIRECTORY_SID, "FavoritesRadios", 1);
		if (favRadios != undefined && favRadios != prevFavRadios) {
			html = "";
			pos1 = 0;
			pos2 = favRadios.indexOf('\n', pos1);
			while (pos2 >= 0) {
				var line = favRadios.substring(pos1, pos2);
				var pos3 = line.indexOf('@');
				if (pos3 >= 0) {
					var value = line.substr(0, pos3);
					var title = line.substr(pos3+1);
					if (title.length > 60) {
						title = title.substr(0, 60) + '...';
					}
					html += '<option value="' + value + '">' + title + '</option>';
				}
				pos1 = pos2+1;
				pos2 = favRadios.indexOf('\n', pos1);
			}
			jQuery('#favRadios').html(html);
			prevFavRadios = favRadios;
		}

		var favorites = api.getDeviceState(device, CONTENT_DIRECTORY_SID, "Favorites", 1);
		if (favorites != undefined && favorites != prevFavorites) {
			html = "";
			pos1 = 0;
			pos2 = favorites.indexOf('\n', pos1);
			while (pos2 >= 0) {
				var line = favorites.substring(pos1, pos2);
				var pos3 = line.indexOf('@');
				if (pos3 >= 0) {
					var value = line.substr(0, pos3);
					var title = line.substr(pos3+1);
					if (title.length > 60) {
						title = title.substr(0, 60) + '...';
					}
					html += '<option value="' + value + '">' + title + '</option>';
				}
				pos1 = pos2+1;
				pos2 = favorites.indexOf('\n', pos1);
			}
			jQuery('#favorites').html(html);
			prevFavorites = favorites;
		}

		var coordinator = api.getDeviceState(device, SONOS_SID, "GroupCoordinator", 1);
		if (coordinator == undefined) {
			coordinator = uuid;
		}
		var onlineState = api.getDeviceState(device, SONOS_SID, "SonosOnline", 1);
		if (onlineState == undefined) {
			onlineState = '1';
		}
		var currentAlbumArtUrl = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentAlbumArt", 1);
		if (currentAlbumArtUrl == undefined) {
			currentAlbumArtUrl = '';
		}
		var title = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentTitle", 1);
		if (title == undefined) {
			title = '';
		}
		var album = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentAlbum", 1);
		if (album == undefined) {
			album = '';
		}
		var artist = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentArtist", 1);
		if (artist == undefined) {
			artist = '';
		}
		var details = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentDetails", 1);
		if (details == undefined) {
			details = '';
		}
		var currentTrack = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentTrack", 1);
		if (currentTrack == undefined || currentTrack == "") {
			currentTrack = '1';
		}
		var nbrTracks = api.getDeviceState(device, AVTRANSPORT_SID, "NumberOfTracks", 1);
		if (nbrTracks == undefined || nbrTracks == "NOT_IMPLEMENTED") {
			nbrTracks = '';
		}
		var playing = api.getDeviceState(device, AVTRANSPORT_SID, "TransportState", 1);
		if (playing == undefined) {
			playing = '';
		}
		var actions = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentTransportActions", 1);
		if (actions == undefined) {
			actions = '';
		}
		actions = actions.toLowerCase();
		var transportUri = api.getDeviceState(device, AVTRANSPORT_SID, "AVTransportURI", 1);
		if (transportUri == undefined) {
			transportUri = '';
		}
		var currentService = api.getDeviceState(device, SONOS_SID, "CurrentService", 1);
		if (currentService == undefined) {
			currentService = '';
		}
		var currentRadio = api.getDeviceState(device, AVTRANSPORT_SID, "CurrentRadio", 1);
		if (currentRadio == undefined) {
			currentRadio = '';
		}
		var mute = api.getDeviceState(device, RENDERING_CONTROL_SID, "Mute", 1);
		if (mute == undefined || mute == "") {
			mute = '0';
		}
		var volume = api.getDeviceState(device, RENDERING_CONTROL_SID, "Volume", 1);
		if (volume == undefined || volume == "") {
			volume = 0;
		}

		if (coordinator != prevCoordinator ||
			onlineState != prevOnlineState ||
			currentAlbumArtUrl != prevCurrentAlbumArtUrl ||
			title != prevTitle ||
			album != prevAlbum ||
			artist != prevArtist ||
			details != prevDetails ||
			currentTrack != prevCurrentTrack ||
			nbrTracks != prevNbrTracks ||
			playing != prevPlaying ||
			actions != prevActions ||
			transportUri != prevTransportUri ||
			currentService != prevCurrentService ||
			currentRadio != prevCurrentRadio ||
			mute != prevMute ||
			volume != prevVolume) {

			jQuery('#albumArt').attr('src',currentAlbumArtUrl);

			var label;

			if (title.indexOf('x-sonosapi', 0) == 0) {
				title = '';
			}
			if (title != '') {
				label = 'Track title:';
			}
			else {
				label = '';
			}
			jQuery('#titleLabel').html(label);
			jQuery('#title').html(title);

			if (album != '') {
				label = 'Album:';
			}
			else {
				label = '';
			}
			jQuery('#albumLabel').html(label);
			jQuery('#album').html(album);

			if (artist != '') {
				label = 'Artist:';
			}
			else {
				label = '';
			}
			jQuery('#artistLabel').html(label);
			jQuery('#artist').html(artist);

			if (details != '') {
				label = 'Information:';
			}
			else {
				label = '';
			}
			jQuery('#detailsLabel').html(label);
			jQuery('#details').html(details);

			if (onlineState != '1' || coordinator != uuid || transportUri == '') {
				if (onlineState != '1') {
					jQuery('#trackLabel').html('Offline');
				}
				else if (coordinator != uuid) {
					jQuery('#trackLabel').html('Group driven by another zone');
				}
				else {
					jQuery('#trackLabel').html('No music');
				}
				jQuery('#track').html('');
				jQuery('#service').html('');
				jQuery('#radio').html('');
				$('button.sonosbtn')
					.prop('disabled', onlineState != '1' || transportUri == '')
					.removeClass("sonoson");
			}
			else {
				if (nbrTracks == '' || nbrTracks == '0') {
					jQuery('#trackLabel').html('');
					jQuery('#track').html('');
					$('button#prevTrack').prop( 'disabled', true );
					$('button#nextTrack').prop( 'disabled', true );
				}
				else {
					jQuery('#trackLabel').html('Track:');
					jQuery('#track').html(currentTrack + '/' + nbrTracks);
					$('button#prevTrack').prop( 'disabled', currentTrack == "1" );
					$('button#nextTrack').prop( 'disabled', currentTrack == nbrTracks );
				}

				if (playing == 'PLAYING' || playing == 'TRANSITIONING') {
					$( 'button#play' ).addClass( 'sonoson' );
					$( 'button#pause,button#stop' ).removeClass( 'sonoson' );
				}
				else if (playing == 'PAUSED_PLAYBACK') {
					$( 'button#pause' ).addClass( 'sonoson' );
					$( 'button#play,button#stop' ).removeClass( 'sonoson' );
				}
				else if (playing == 'STOPPED') {
					$( 'button#stop' ).addClass( 'sonoson' );
					$( 'button#play,button#pause' ).removeClass( 'sonoson' );
				}
				else {
					$( 'button#play,button#pause,button#stop' ).removeClass( 'sonoson' );
				}

				$('button#play').prop( 'disabled', actions.indexOf('play') < 0 );
				$('button#pause').prop( 'disabled', actions.indexOf('pause') < 0 );
				$('button#stop').prop( 'disabled', actions.indexOf('stop') < 0 );
				$('button#prevTrack').prop( 'disabled', actions.indexOf('previous') < 0 );
				$('button#nextTrack').prop( 'disabled', actions.indexOf('next') < 0 );

				if (transportUri.indexOf('x-rincon-stream:', 0) == 0 ||
						transportUri.indexOf('x-rincon-mp3radio:', 0) == 0 ||
						transportUri.indexOf('x-sonosapi-stream:', 0) == 0 ||
						transportUri.indexOf('x-sonosapi-hls:', 0) == 0 ||
						transportUri.indexOf('x-sonosapi-radio:', 0) == 0 ||
						transportUri.indexOf('http:', 0) == 0 ||
						transportUri.indexOf('pndrradio:', 0) == 0) {
					if ((transportUri.indexOf('x-rincon-mp3radio:', 0) == 0 ||
								transportUri.indexOf('http:', 0) == 0 ||
								transportUri.indexOf('x-sonosapi-stream:', 0) == 0) &&
								title != '') {
						jQuery('#titleLabel').html('Stream:');
					}
					else if (transportUri.indexOf('x-sonosapi-hls:', 0) == 0 && title != '') {
						jQuery('#titleLabel').html('Title:');
					}
					else if (transportUri.indexOf('x-rincon-stream:', 0) == 0 && title != '') {
						jQuery('#titleLabel').html('Source:');
					}
					jQuery('#trackLabel').html('');
					jQuery('#track').html('');
					if (transportUri.indexOf('x-rincon-stream:', 0) != 0) {
						jQuery('#pause').get(0).disabled = true;
					}
					if (transportUri.indexOf('x-sonosapi-radio:', 0) != 0 &&
							transportUri.indexOf('pndrradio:', 0) != 0) {
						jQuery('#prevTrack').get(0).disabled = true;
						jQuery('#nextTrack').get(0).disabled = true;
					}
					if (currentService == '' && transportUri.indexOf('x-rincon-mp3radio:', 0) == 0 && currentRadio != '') {
						currentService = 'Web radio:';
					}
				}
				jQuery('#service').html(currentService);
				jQuery('#radio').html(currentRadio);
			}

			$('button#mute').toggleClass( 'sonoson', mute == '1' );

			if (onlineState == '1') {
				jQuery('#mute').prop( 'disabled', false );
				jQuery('#volumeDown').prop( 'disabled', false );
				jQuery('#volumeUp').prop( 'disabled', false );
				jQuery('#volumeSet').prop( 'disabled', false );
				jQuery('#playUri').prop( 'disabled', false );
				jQuery('#playAudioInput').prop( 'disabled', false );
				jQuery('#playSQ').prop( 'disabled', false );
				jQuery('#playFavRadio').prop( 'disabled', false );
				jQuery('#playFavorite').prop( 'disabled', false );
				if (coordinator != uuid) {
					jQuery('#playQueue').prop( 'disabled', true );
					jQuery('#clearQueue').prop( 'disabled', true );
				}
				else {
					jQuery('#playQueue').prop( 'disabled', false );
					jQuery('#clearQueue').prop( 'disabled', false );
				}
			}
			else {
				jQuery('#mute').prop( 'disabled', true );
				jQuery('#volumeDown').prop( 'disabled', true );
				jQuery('#volumeUp').prop( 'disabled', true );
				jQuery('#volumeSet').prop( 'disabled', true );
				jQuery('#playUri').prop( 'disabled', true );
				jQuery('#playAudioInput').prop( 'disabled', true );
				jQuery('#playSQ').prop( 'disabled', true );
				jQuery('#playFavRadio').prop( 'disabled', true );
				jQuery('#playFavorite').prop( 'disabled', true );
				jQuery('#playQueue').prop( 'disabled', true );
				jQuery('#clearQueue').prop( 'disabled', true );
			}

			jQuery('#volume').html(volume);

			prevCoordinator = coordinator;
			prevOnlineState = onlineState;
			prevCurrentAlbumArtUrl = currentAlbumArtUrl;
			prevTitle = title;
			prevAlbum = album;
			prevArtist = artist;
			prevDetails = details;
			prevCurrentTrack = currentTrack;
			prevNbrTracks = nbrTracks;
			prevPlaying = playing;
			prevActions = actions;
			prevTransportUri = transportUri;
			prevCurrentService = currentService;
			prevCurrentRadio = currentRadio;
			prevMute = mute;
			prevVolume = volume;
		}

		timeoutVar = setTimeout(function() { Sonos_refreshPlayer(device); }, 1000);
	}

	function Sonos_refreshTTS(device)
	{
		var onlineState = api.getDeviceState(device, SONOS_SID, "SonosOnline", 1);
		if (onlineState == undefined) {
			onlineState = '1';
		}

		if (onlineState != prevOnlineState3) {

			if (onlineState == '1') {
				jQuery('#say').get(0).disabled = false;
			}
			else {
				jQuery('#say').get(0).disabled = true;
			}

			prevOnlineState3 = onlineState;
		}

		timeoutVar3 = setTimeout( function() { Sonos_refreshTTS(device); }, 1000);
	}

	function Sonos_play(device)
	{
		api.performActionOnDevice(device, MEDIA_NAVIGATION_SID, 'Play', { actionArguments: {} } );
	}

	function Sonos_pause(device)
	{
		api.performActionOnDevice(device, MEDIA_NAVIGATION_SID, 'Pause', { actionArguments: {} } );
	}

	function Sonos_stop(device)
	{
		api.performActionOnDevice(device, MEDIA_NAVIGATION_SID, 'Stop', { actionArguments: {} } );
	}

	function Sonos_prevTrack(device)
	{
		api.performActionOnDevice(device, MEDIA_NAVIGATION_SID, 'SkipUp', { actionArguments: {} } );
	}

	function Sonos_nextTrack(device)
	{
		api.performActionOnDevice(device, MEDIA_NAVIGATION_SID, 'SkipDown', { actionArguments: {} } );
	}

	function Sonos_mute(device)
	{
		api.performActionOnDevice(device, RENDERING_CONTROL_SID, 'SetMute', { actionArguments: {} } );
	}

	function Sonos_setVolume(device, volume)
	{
		if (jQuery('#newVolume option:selected').index() >= 0) {
			var volume = jQuery('#newVolume').val();
			api.performActionOnDevice(device, RENDERING_CONTROL_SID, 'SetVolume', { actionArguments: {'DesiredVolume':volume} } );
		}
	}

	function Sonos_volumeDown(device)
	{
		api.performActionOnDevice(device, VOLUME_SID, 'Down', { actionArguments: {} } );
	}

	function Sonos_volumeUp(device)
	{
		api.performActionOnDevice(device, VOLUME_SID, 'Up', { actionArguments: {} } );
	}

	function Sonos_playAudioInput(device)
	{
		if (jQuery('#audioInputs option:selected').index() >= 0) {
			var uri = encodeURIComponent(jQuery('#audioInputs').val());
			api.performActionOnDevice(device, SONOS_SID, 'PlayURI', { actionArguments: {'URIToPlay':uri} } );
		}
	}

	function Sonos_playSQ(device)
	{
		if (jQuery('#savedQueues option:selected').index() >= 0) {
			var id = encodeURIComponent('ID:' + jQuery('#savedQueues').val());
			api.performActionOnDevice(device, SONOS_SID, 'PlayURI', { actionArguments: {'URIToPlay':id} } );
		}
	}

	function Sonos_clearQueue(device)
	{
		api.performActionOnDevice(device, AVTRANSPORT_SID, 'RemoveAllTracksFromQueue', { actionArguments: {'InstanceID':'0'} } );
	}

	function Sonos_playQueue(device)
	{
		var uri = 'Q:';
		var idx = jQuery('#queue option:selected').index();
		if (idx >= 0) {
			idx += 1;
			uri += idx;
		}
		api.performActionOnDevice(device, SONOS_SID, 'PlayURI', { actionArguments: {'URIToPlay':uri} } );
	}

	function Sonos_playFavRadio(device)
	{
		if (jQuery('#favRadios option:selected').index() >= 0) {
			var id = encodeURIComponent('ID:' + jQuery('#favRadios').val());
			api.performActionOnDevice(device, SONOS_SID, 'PlayURI', { actionArguments: {'URIToPlay':id} } );
		}
	}

	function Sonos_playFavorite(device)
	{
		if (jQuery('#favorites option:selected').index() >= 0) {
			var id = encodeURIComponent('ID:' + jQuery('#favorites').val());
			api.performActionOnDevice(device, SONOS_SID, 'PlayURI', { actionArguments: {'URIToPlay':id} } );
		}
	}

	function Sonos_playUri(device)
	{
		var uri = jQuery('#uri').val();
		var protocol = jQuery('#protocol').val();
		if (protocol != "") {
			uri = protocol+':'+uri;
		}
		uri = encodeURIComponent(uri);
		//jQuery('#debug').html(uri);
		if (uri != "") {
			api.performActionOnDevice(device, SONOS_SID, 'PlayURI', { actionArguments: {'URIToPlay':uri} } );
		}
	}

	function Sonos_selectLang()
	{
		if (jQuery('#language1 option:selected').index() >= 0) {
			jQuery('#language').val(jQuery('#language1').val());
		}
	}

	function Sonos_say(device)
	{
		var text = encodeURIComponent(jQuery('#text').val());
		var language = jQuery('#language').val();
		var engine = jQuery('#engine').val();
		var volume = jQuery('#volumeTTS').val();
		var zones = '';
		if (jQuery('#CurrentGroup').is(':checked')) {
			zones = 'CURRENT';
		}
		else if (jQuery('#GroupAll').is(':checked')) {
			zones = 'ALL';
		}
		var sameVolume = 'false';
		if (jQuery('#GroupVolume').is(':checked')) {
			sameVolume = 'true';
		}
		//jQuery('#debug').html('_' + text + '_ ' + language + ' ' + engine + ' ' + volume + ' ' + zones + ' ' + sameVolume);
		if (text != "") {
			api.performActionOnDevice(device, SONOS_SID, 'Say', { actionArguments: {'Text':text, 'Language':language, 'Engine':engine, 'Volume':volume, 'GroupZones':zones, 'SameVolumeForAll':sameVolume} } );
		}
	}

	function Sonos_selectAllMembers(state)
	{
		var version = parseFloat(jQuery().jquery.substr(0,3));
		var disabled = true;
		var i=0;
		while (jQuery('#GroupMember'+i).length > 0) {
			if (version < 1.6) {
				jQuery('#GroupMember'+i).attr('checked', state);
			}
			else {
				jQuery('#GroupMember'+i).prop('checked', state);
			}
			disabled = ! state;
			i++;
		}
		jQuery('#applyGroup').get(0).disabled = disabled;
	}

	function Sonos_updateGroupSelection(state)
	{
		var disabled = true;
		var i=0;
		while (jQuery('#GroupMember'+i).length > 0) {
			if (jQuery('#GroupMember'+i).is(':checked')) {
				disabled = false;
				break;
			}
			i++;
		}
		jQuery('#applyGroup').get(0).disabled = disabled;
	}

	function Sonos_updateGroup(device)
	{
		var zones = "";
		var i=0;
		while (jQuery('#GroupMember'+i).length > 0) {
			if (jQuery('#GroupMember'+i).is(':checked')) {
				if (zones != "") {
					zones += ',';
				}
				zones += jQuery('#GroupMember'+i).val();
			}
			i++;
		}
		zones = encodeURIComponent(zones);
		api.performActionOnDevice(device, SONOS_SID, 'UpdateGroupMembers', { actionArguments: {'Zones':zones} } );
	}

	function Sonos_checkState(device)
	{
		if (jQuery('#IP').html() != "") {
			var url = encodeURIComponent('http://' + jQuery('#IP').html() + ':1400/xml/device_description.xml');
			api.performActionOnDevice(device, SONOS_SID, 'SelectSonosDevice', { actionArguments: {'URL':url} } );
		}
	}

	function Sonos_updateCheckStateRate(device)
	{
		var rate;
		if (jQuery('#stateAutoCheckOn').is(':checked')) {
			var reg1 = new RegExp('^\\d+$', '');
			if (jQuery('#rate').val() == '' ||
					!jQuery('#rate').val().match(reg1) ||
					jQuery('#rate').val() == 0) {
				jQuery('#rate').val('5');
			}
			jQuery('#setCheckState').get(0).disabled = false;
		}
		else if (jQuery('#stateAutoCheckOff').is(':checked')) {
			jQuery('#rate').val('0');
			jQuery('#setCheckState').get(0).disabled = true;
		}
		var rate = jQuery('#rate').val();
		api.performActionOnDevice(device, SONOS_SID, 'SetCheckStateRate', { actionArguments: { 'rate':rate } } );
	}

/** ***************************************************************************
 *
 * C L O S I N G
 *
 ** **************************************************************************/

	console.log("Initializing Sonos (UI7) module");

	myModule = {
		uuid: uuid,
		//onBeforeCpanelClose: onBeforeCpanelClose,
		//onUIDeviceStatusChanged: onUIDeviceStatusChanged,
		doPlayer: function() { try { doPlayer(api.getCpanelDeviceId()); } catch(e) { console.log(e); } },
		doGroup: function() { try { doGroup(api.getCpanelDeviceId()); } catch(e) { console.log(e); } },
		doTTS: function() { try { doTTS(api.getCpanelDeviceId()); } catch(e) { console.log(e); } },
		doHelp: function() { try { doHelp(api.getCpanelDeviceId()); } catch(e) { console.log(e); } }
	};
	return myModule;
})(api, $ || jQuery);
