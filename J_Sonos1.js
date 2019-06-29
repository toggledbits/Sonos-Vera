//
// $Id$
//
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

function Sonos_showPlayer(device)
{
	if (typeof Sonos.timeoutVar != 'undefined') {
		clearTimeout(Sonos.timeoutVar);
	}

	Sonos_detectBrowser();
	Sonos_defineUIStyle();

	Sonos_initXMLParser();

	var html = '';

	var minVolume = 0;
	var maxVolume = 100;

	html += '<table>';
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
	html += '<DIV>'
	html += '<table>';
	html += '<tr>';
	html += '<td>';
	html += '<button id="prevTrack" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_prevTrack('+device+');">Prev</button>';
	html += '</td>';
	html += '<td>';
	html += '<button id="play" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_play('+device+');">Play</button>';
	html += '</td>';
	html += '<td>';
	html += '<button id="pause" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_pause('+device+');">Pause</button>';
	html += '</td>';
	html += '<td>';
	html += '<button id="stop" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_stop('+device+');">Stop</button>';
	html += '</td>';
	html += '<td>';
	html += '<button id="nextTrack" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_nextTrack('+device+');">Next</button>';
	html += '</td>';
	html += '<td>Volume:</td>';
	html += '<td id="volume"></td>';
	html += '<td>';
	html += '<button id="volumeDown" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 25px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_volumeDown('+device+');">-</button>';
	html += '</td>';
	html += '<td>';
	html += '<button id="volumeUp" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 25px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_volumeUp('+device+');">+</button>';
	html += '</td>';
	html += '<td>';
	html += '<select id="newVolume">';
	for (i=minVolume; i<=maxVolume; i++) {
		html += '<option value="' + i + '">' + i + '</option>';
	}
	html += '</select>';
	html += '</td>';
	html += '<td>';
	html += '<button id="volumeSet" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_setVolume('+device+');">Set</button>';
	html += '</td>';
	html += '<td>';
	html += '<button id="mute" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_mute('+device+');">Mute</button>';
	html += '</td>';
	html += '</tr>';
	html += '</table>';
	html += '</DIV>'
	html += '<DIV>'
	html += '<table>';
	html += '<tr>';
	html += '<td>Audio Input:</td>';
	html += '<td>';
	html += '<select id="audioInputs"/>';
	html += '<button id="playAudioInput" type="button" style="margin-left: 10px; background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_playAudioInput('+device+');">Play</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Sonos playlist:</td>';
	html += '<td>';
	html += '<select id="savedQueues"/>';
	html += '<button id="playSQ" type="button" style="margin-left: 10px; background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_playSQ('+device+');">Play</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Queue:</td>';
	html += '<td>';
	html += '<select id="queue"/>';
	html += '<button id="playQueue" type="button" style="margin-left: 10px; background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_playQueue('+device+');">Play</button>';
	html += '<button id="clearQueue" type="button" style="margin-left: 10px; background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_clearQueue('+device+');">Clear</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Favorites radios:</td>';
	html += '<td>';
	html += '<select id="favRadios"/>';
	html += '<button id="playFavRadio" type="button" style="margin-left: 10px; background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_playFavRadio('+device+');">Play</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Sonos favorites:</td>';
	html += '<td>';
	html += '<select id="favorites"/>';
	html += '<button id="playFavorite" type="button" style="margin-left: 10px; background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_playFavorite('+device+');">Play</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>URI:</td>';
	html += '<td>';
	html += '<select id="protocol" style="margin-right: 5px">';
	html += '<option selected></option>';
	html += '<option>x-file-cifs</option>';
	html += '<option>file</option>';
	html += '<option>x-rincon</option>';
	html += '<option>x-rincon-mp3radio</option>';
	html += '<option>x-rincon-playlist</option>';
	html += '<option>x-rincon-queue</option>';
	html += '<option>x-rincon-stream</option>';
	html += '<option>x-sonosapi-stream</option>';
	html += '<option>x-sonosapi-radio</option>';
	html += '<option value="AI">Audio input</option>';
	html += '<option value="SQ">Sonos playlist</option>';
	html += '<option value="SF">Sonos favorite</option>';
	html += '<option value="FR">Favorite radio</option>';
	html += '<option value="TR">TuneIn radio</option>';
	html += '<option value="SR">Sirius radio</option>';
	html += '<option value="GZ">Group zone</option>';
	html += '</select>';
	html += '<input id="uri" type="text" style="width: 277px"/>';
	html += '<button id="playUri" type="button" style="margin-left: 10px; background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_playUri('+device+');">Play</button>';
	html += '</td>';
	html += '</tr>';
	html += '</table>';
	html += '</DIV>'

	//html += '<p id="debug">';

	set_panel_html(html);

	Sonos.prevGroups = undefined;
	Sonos.prevSavedQueues = undefined;
	Sonos.prevQueue = undefined;
	Sonos.prevFavRadios = undefined;
	Sonos.prevFavorites = undefined;
	Sonos.prevCoordinator = undefined;
	Sonos.prevOnlineState = undefined;
	Sonos.prevCurrentAlbumArtUrl = undefined;
	Sonos.prevTitle = undefined;
	Sonos.prevAlbum = undefined;
	Sonos.prevArtist = undefined;
	Sonos.prevDetails = undefined;
	Sonos.prevCurrentTrack = undefined;
	Sonos.prevNbrTracks = undefined;
	Sonos.prevPlaying = undefined;
	Sonos.prevActions = undefined;
	Sonos.prevTransportUri = undefined;
	Sonos.prevCurrentService = undefined;
	Sonos.prevCurrentRadio = undefined;
	Sonos.prevMute = undefined;
	Sonos.prevVolume = undefined;

	Sonos_refreshPlayer(device);
}

function Sonos_showHelp(device)
{
	Sonos_defineUIStyle();

	Sonos_initXMLParser();

	var zone = get_device_state(device, Sonos.DEVICE_PROPERTIES_SID, "ZoneName", 1);
	var uuid = get_device_state(device, Sonos.DEVICE_PROPERTIES_SID, "SonosID", 1);
	var groups = get_device_state(device, Sonos.ZONEGROUPTOPOLOGY_SID, "ZoneGroupState", 1);

	var members;
	if (groups != undefined && groups != "") {
		var xmlgroups = Sonos.parseXml(groups);
		if (typeof xmlgroups != 'undefined') {
			members = xmlgroups.getElementsByTagName("ZoneGroupMember");
		}
	}

	var version = get_device_state(device, Sonos.SONOS_SID, "PluginVersion", 1);
	if (version == undefined) {
		version = '';
	}

	var html = '';

	html += '<table cellspacing="10">';
	html += '<tr>';
	html += '<td>Plugin version:</td>';
	html += '<td>' + version + '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Wiki:</td>';
	html += '<td><a href="http://code.mios.com/trac/mios_sonos-wireless-music-systems#">link</a></td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Forum:</td>';
	html += '<td><a href="http://forum.micasaverde.com/index.php/board,47.0.html">link</a></td>';
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
	html += '<tr align="center" style="background-color: '+ Sonos.tableTitleBgColor + '; color: white">';
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

	if (typeof members != 'undefined') {
		for (i=0; i<members.length; i++) {
			var zoneUUID = Sonos_extractXmlAttribute(members[i], 'UUID');
			var zoneName = Sonos_extractXmlAttribute(members[i], 'ZoneName');
			var channelMapSet = Sonos_extractXmlAttribute(members[i], 'ChannelMapSet');
			var isZoneBridge = Sonos_extractXmlAttribute(members[i], 'IsZoneBridge');
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
			var zoneUUID = Sonos_extractXmlAttribute(members[i], 'UUID');
			var zoneName = Sonos_extractXmlAttribute(members[i], 'ZoneName');
			var channelMapSet = Sonos_extractXmlAttribute(members[i], 'ChannelMapSet');
			var isZoneBridge = Sonos_extractXmlAttribute(members[i], 'IsZoneBridge');
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

	var favRadios = get_device_state(device, Sonos.CONTENT_DIRECTORY_SID, "FavoritesRadios", 1);
	if (favRadios != undefined && favRadios != "") {
		var pos = favRadios.indexOf('\n', 0); 
		if (pos >= 0) { 
			var line = favRadios.substring(0, pos);
			var pos2 = line.indexOf('@');
			if (pos2 >= 0) {
				var title = line.substr(pos2+1);
				html += '<tr>';
				html += '<td>Favorite radio "' + title + '"</td>';
				html += '<td></td>';
				html += '<td>FR:' + title + '</td>';
				html += '</tr>';
			}
		} 
	}

	var savedQueues = get_device_state(device, Sonos.CONTENT_DIRECTORY_SID, "SavedQueues", 1);
	if (savedQueues != undefined && savedQueues != "") {
		var pos1 = 0;
		var pos2 = savedQueues.indexOf('\n', pos1); 
		while (pos2 >= 0) { 
			var line = savedQueues.substring(pos1, pos2);
			var pos3 = line.indexOf('@');
			if (pos3 >= 0) {
				var value = line.substring(0, pos3);
				var title = line.substr(pos3+1);
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
	html += '<p>* Seek action is then required to select the right item</p>'
	html += '<p>** Meta data have to be provided in addition to the standard URI</p>'

	var variables = [	[ Sonos.AVTRANSPORT_SID, "AVTransportURI" ],
						[ Sonos.AVTRANSPORT_SID, "AVTransportURIMetaData" ],
						[ Sonos.AVTRANSPORT_SID, "CurrentTrackURI" ],
						[ Sonos.AVTRANSPORT_SID, "CurrentTrackMetaData" ],
						[ Sonos.ZONEGROUPTOPOLOGY_SID, "ZoneGroupState" ],
						[ Sonos.SONOS_SID, 'SonosServicesKeys' ] ];
	html += '<table border="1">';
	html += '<tr align="center" style="background-color: '+ Sonos.tableTitleBgColor + '; color: white">';
	html += '<th>Variable</td>';
	html += '<th>Value</td>';
	html += '</tr>';
	for (i=0; i<variables.length; i++) {
		var value = get_device_state(device, variables[i][0], variables[i][1], 1);
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

	set_panel_html(html);
}

function Sonos_showGroup(device)
{
	Sonos_detectBrowser();
	Sonos_defineUIStyle();

	Sonos_initXMLParser();

	var html = '<DIV id="groupSelection"/>';

	html += '<BR>';
	html += '<button type="button" style="background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_refreshGroupSelection('+device+');">Refresh</button>';
	html += '<button type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_selectAllMembers(true);">Select All</button>';
	html += '<button type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_selectAllMembers(false);">Unselect All</button>';
	html += '<button id="applyGroup" type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_updateGroup('+device+');">Apply</button>';

	//html += '<p id="debug">';

	set_panel_html(html);

	Sonos_refreshGroupSelection(device);
}

function Sonos_refreshGroupSelection(device)
{
	var html = '';
	var disabled = true;

	var groupMembers = get_device_state(device, Sonos.ZONEGROUPTOPOLOGY_SID, "ZonePlayerUUIDsInGroup", 1);
	var groups = get_device_state(device, Sonos.ZONEGROUPTOPOLOGY_SID, "ZoneGroupState", 1);
	if (groups != undefined && groups != "") {
		var xmlgroups = Sonos.parseXml(groups);
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
					html += ' value="' + name + '" onchange="Sonos_updateGroupSelection();">' + name + '<BR>';
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
	if (typeof Sonos.timeoutVar3 != 'undefined') {
		clearTimeout(Sonos.timeoutVar3);
	}

	Sonos_detectBrowser();
	Sonos_defineUIStyle();

	var html = '';

	var minVolume = 0;
	var maxVolume = 100;

	var engines = [	[ "GOOGLE", "Google" ],
					[ "OSX_TTS_SERVER", 'OSX TTS server' ],
					[ "MICROSOFT", "Microsoft" ],
					[ "MARY", "Mary" ] ];
	var defaultEngine = get_device_state(device, Sonos.SONOS_SID, "DefaultEngineTTS", 1);
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
	var defaultLanguage = get_device_state(device, Sonos.SONOS_SID, "DefaultLanguageTTS", 1);
	if (defaultLanguage == undefined) {
		defaultLanguage = 'en';
	}

	var GoogleServerURL = get_device_state(device, Sonos.SONOS_SID, "GoogleTTSServerURL", 1);
	if (GoogleServerURL == undefined) {
		GoogleServerURL = '';
	}

	var serverURL = get_device_state(device, Sonos.SONOS_SID, "OSXTTSServerURL", 1);
	if (serverURL == undefined) {
		serverURL = '';
	}

	var MaryServerURL = get_device_state(device, Sonos.SONOS_SID, "MaryTTSServerURL", 1);
	if (MaryServerURL == undefined) {
		MaryServerURL = '';
	}

	var clientId = get_device_state(device, Sonos.SONOS_SID, "MicrosoftClientId", 1);
	if (clientId == undefined) {
		clientId = '';
	}
	var clientSecret = get_device_state(device, Sonos.SONOS_SID, "MicrosoftClientSecret", 1);
	if (clientSecret == undefined) {
		clientSecret = '';
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
	html += 'Apply volume to all zones'
	html += '<input id="GroupVolume" type="checkbox" style="margin-left: 10px" value="GroupVolume"/>';
	html += '</td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>';
	html += '<button id="say" type="button" style="background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_say('+device+');">Say</button>';
	html += '</td>';
	html += '<td></td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>Default language:</td>';
	html += '<td>';
	html += '<input id="defaultLanguage" type="text" value="' + defaultLanguage + '" style="width: 50px"/>';
	html += '</td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>Default engine:</td>';
	html += '<td>';
	html += '<select id="defaultEngine">';
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
	html += '<td>Google TTS server URL:</td>';
	html += '<td>';
	html += '<input id="GoogleTTSserverURL" type="text" value="' + GoogleServerURL + '" style="width: 450px"/>';
	html += '</td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>OSX TTS server URL:</td>';
	html += '<td>';
	html += '<input id="TTSserverURL" type="text" value="' + serverURL + '" style="width: 450px"/>';
	html += '</td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>MaryTTS server URL:</td>';
	html += '<td>';
	html += '<input id="MaryTTSserverURL" type="text" value="' + MaryServerURL + '" style="width: 450px"/>';
	html += '</td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>Microsoft Client Id:</td>';
	html += '<td>';
	html += '<input id="ClientId" type="text" value="' + clientId + '" style="width: 450px"/>';
	html += '</td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>Microsoft Client Secret:</td>';
	html += '<td>';
	html += '<input id="ClientSecret" type="text" value="' + clientSecret + '" style="width: 450px"/>';
	html += '</td>';
	html += '</tr>';

	html += '<tr>';
	html += '<td>';
	html += '<button id="setupTTS" type="button" style="background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_setupTTS('+device+');">Set</button>';
	html += '</td>';
	html += '<td></td>';
	html += '</tr>';

	html += '</table>';

	//html += '<p id="debug">';

	set_panel_html(html);

	Sonos.prevOnlineState3 = undefined;

	Sonos_refreshTTS(device);
}

function Sonos_showSettings(device)
{
	if (typeof Sonos.timeoutVar2 != 'undefined') {
		clearTimeout(Sonos.timeoutVar2);
	}

	Sonos_detectBrowser();
	Sonos_defineUIStyle();

	Sonos_initXMLParser();

	var debugLogs = get_device_state(device, Sonos.SONOS_SID, "DebugLogs", 1);
	var readQueue = get_device_state(device, Sonos.SONOS_SID, "FetchQueue", 1);
	var rate = get_device_state(device, Sonos.SONOS_SID, "CheckStateRate", 1);
	if (rate == undefined) {
		rate = '';
	}

	var html = '';

	html += '<table cellspacing="10">';
	html += '<tr>';
	html += '<td>Discovery patch:</td>';
	html += '<td>';
	html += '<label id="patch"/>';
	html += '<button id="install" type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 75px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_installPatch('+device+');">Install</button>';
	html += '<button id="uninstall" type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 75px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_uninstallPatch('+device+');">Uninstall</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>';
	html += '<button id="discover" type="button" style="background-color: ' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 90px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_startSonosDiscovery('+device+');">Discover</button>';
	html += '</td>';
	html += '<td>';
	html += '<select id="discovery"/>';
	html += '<button id="selectDiscovery" type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 75px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_selectDiscovery('+device+');">Select</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>New IP:</td>';
	html += '<td>';
	html += '<input id="newIP" type="text" style="width: 100px"/>';
	html += '<button id="selectIP" type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 75px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_selectIP('+device+');">Select</button>';
	html += '<label style="margin-left: 10px">Use this in case UPnP discovery did not work.</label>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Selected zone:</td>';
	html += '<td id="zone"></td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>IP:</td>';
	html += '<td id="IP"></td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>State:</td>';
	html += '<td>';
	html += '<label id="state"/>';
	html += '<button id="checkState" type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_checkState('+device+');">Check now</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>State auto check:</td>';
	html += '<td>';
	html += '<input name="stateAutoCheck" id="stateAutoCheckOn" type="radio" onchange="Sonos_updateCheckStateRate('+device+');"';
	if (rate != '0') {
		html += ' checked';
	}
	html += '>ON';
	html += '<input name="stateAutoCheck" id="stateAutoCheckOff" type="radio" onchange="Sonos_updateCheckStateRate('+device+');"';
	if (rate == '0') {
		html += ' checked';
	}
	html += '>OFF';
	html += '<label style="margin-left: 10px">Frequency:</label>';
	html += '<input id="rate" type="text" size="3" maxlength="3" style="margin-left: 10px" value="' + rate + '"/>';
	html += '<label style="margin-left: 10px">minutes</label>';
	html += '<button id="setCheckState" type="button" style="margin-left: 10px; background-color:' + Sonos.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="Sonos_updateCheckStateRate('+device+');"';
	if (rate == '0') {
		html += ' disabled';
	}
	html += '>Set</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>UPnP event proxy:</td>';
	html += '<td id="proxy"></td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Debug logs:</td>';
	html += '<td>';
	html += '<input name="debugLogs" id="debugLogsOn" type="radio" onchange="Sonos_setDebugLogs('+device+');"';
	if (debugLogs == '1') {
		html += ' checked';
	}
	html += '>ON';
	html += '<input name="debugLogs" id="debugLogsOff" type="radio" onchange="Sonos_setDebugLogs('+device+');"';
	if (debugLogs == '0') {
		html += ' checked';
	}
	html += '>OFF';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Read queue:</td>';
	html += '<td>';
	html += '<input name="readQueue" id="readQueueOn" type="radio" onchange="Sonos_setReadQueue('+device+');"';
	if (readQueue == '1') {
		html += ' checked';
	}
	html += '>ON';
	html += '<input name="readQueue" id="readQueueOff" type="radio" onchange="Sonos_setReadQueue('+device+');"';
	if (readQueue == '0') {
		html += ' checked';
	}
	html += '>OFF';
	html += '</td>';
	html += '</tr>';
	html += '</table>';

	//html += '<p id="debug">';

	set_panel_html(html);

	Sonos.prevModelName = undefined;
	Sonos.prevIp = undefined;
	Sonos.prevZone = undefined;
	Sonos.prevOnlineState2 = undefined;
	Sonos.prevProxy = undefined;
	Sonos.prevResultDiscovery = undefined;
	Sonos.prevPatchInstalled = undefined;

	Sonos_refreshDiscovery(device);
}

function Sonos_detectBrowser()
{
	if (navigator.userAgent.toLowerCase().indexOf('msie') >= 0
		|| navigator.userAgent.toLowerCase().indexOf('trident') >= 0) {
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

function Sonos_extractXmlTag(parent, tag)
{
	var value = undefined;
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
	return unsafe
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;");
}

function Sonos_refreshPlayer(device)
{
	var uuid = get_device_state(device, Sonos.DEVICE_PROPERTIES_SID, "SonosID", 1);

	var groups = get_device_state(device, Sonos.ZONEGROUPTOPOLOGY_SID, "ZoneGroupState", 1);
	if (groups != undefined && groups != "" && Sonos.prevGroups != groups) {
		var xmlgroups = Sonos.parseXml(groups);
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
		Sonos.prevGroups = groups;
	}

	var savedQueues = get_device_state(device, Sonos.CONTENT_DIRECTORY_SID, "SavedQueues", 1);
	if (savedQueues != undefined && savedQueues != Sonos.prevSavedQueues) {
		var html = "";
		var pos1 = 0;
		var pos2 = savedQueues.indexOf('\n', pos1); 
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
		Sonos.prevSavedQueues = savedQueues;
	}

	var queue = get_device_state(device, Sonos.CONTENT_DIRECTORY_SID, "Queue", 1);
	if (queue != undefined && queue != Sonos.prevQueue) {
		var html = "";
		var pos1 = 0;
		var pos2 = queue.indexOf('\n', pos1); 
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
		Sonos.prevQueue = queue;
	}

	var favRadios = get_device_state(device, Sonos.CONTENT_DIRECTORY_SID, "FavoritesRadios", 1);
	if (favRadios != undefined && favRadios != Sonos.prevFavRadios) {
		var html = "";
		var pos1 = 0;
		var pos2 = favRadios.indexOf('\n', pos1); 
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
		Sonos.prevFavRadios = favRadios;
	}

	var favorites = get_device_state(device, Sonos.CONTENT_DIRECTORY_SID, "Favorites", 1);
	if (favorites != undefined && favorites != Sonos.prevFavorites) {
		var html = "";
		var pos1 = 0;
		var pos2 = favorites.indexOf('\n', pos1); 
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
		Sonos.prevFavorites = favorites;
	}

	var coordinator = get_device_state(device, Sonos.SONOS_SID, "GroupCoordinator", 1);
	if (coordinator == undefined) {
		coordinator = uuid;
	}
	var onlineState = get_device_state(device, Sonos.SONOS_SID, "SonosOnline", 1);
	if (onlineState == undefined) {
		onlineState = '1';
	}
	var currentAlbumArtUrl = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentAlbumArt", 1);
	if (currentAlbumArtUrl == undefined) {
		currentAlbumArtUrl = '';
	}
	var title = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentTitle", 1);
	if (title == undefined) {
		title = '';
	}
	var album = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentAlbum", 1);
	if (album == undefined) {
		album = '';
	}
	var artist = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentArtist", 1);
	if (artist == undefined) {
		artist = '';
	}
	var details = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentDetails", 1);
	if (details == undefined) {
		details = '';
	}
	var currentTrack = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentTrack", 1);
	if (currentTrack == undefined || currentTrack == "") {
		currentTrack = '1';
	}
	var nbrTracks = get_device_state(device, Sonos.AVTRANSPORT_SID, "NumberOfTracks", 1);
	if (nbrTracks == undefined || nbrTracks == "NOT_IMPLEMENTED") {
		nbrTracks = '';
	}
	var playing = get_device_state(device, Sonos.AVTRANSPORT_SID, "TransportState", 1);
	if (playing == undefined) {
		playing = '';
	}
	var actions = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentTransportActions", 1);
	if (actions == undefined) {
		actions = '';
	}
	actions = actions.toLowerCase();
	var transportUri = get_device_state(device, Sonos.AVTRANSPORT_SID, "AVTransportURI", 1);
	if (transportUri == undefined) {
		transportUri = '';
	}
	var currentService = get_device_state(device, Sonos.SONOS_SID, "CurrentService", 1);
	if (currentService == undefined) {
		currentService = '';
	}
	var currentRadio = get_device_state(device, Sonos.AVTRANSPORT_SID, "CurrentRadio", 1);
	if (currentRadio == undefined) {
		currentRadio = '';
	}
	var mute = get_device_state(device, Sonos.RENDERING_CONTROL_SID, "Mute", 1);
	if (mute == undefined || mute == "") {
		mute = '0';
	}
	var volume = get_device_state(device, Sonos.RENDERING_CONTROL_SID, "Volume", 1);
	if (volume == undefined || volume == "") {
		volume = 0;
	}

	if (coordinator != Sonos.prevCoordinator
		|| onlineState != Sonos.prevOnlineState
		|| currentAlbumArtUrl != Sonos.prevCurrentAlbumArtUrl
		|| title != Sonos.prevTitle
		|| album != Sonos.prevAlbum
		|| artist != Sonos.prevArtist
		|| details != Sonos.prevDetails
		|| currentTrack != Sonos.prevCurrentTrack
		|| nbrTracks != Sonos.prevNbrTracks
		|| playing != Sonos.prevPlaying
		|| actions != Sonos.prevActions
		|| transportUri != Sonos.prevTransportUri
		|| currentService != Sonos.prevCurrentService
		|| currentRadio != Sonos.prevCurrentRadio
		|| mute != Sonos.prevMute
		|| volume != Sonos.prevVolume) {

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
			jQuery('#play').css({'background-color':Sonos.offButtonBgColor});
			jQuery('#pause').css({'background-color':Sonos.offButtonBgColor});
			jQuery('#stop').css({'background-color':Sonos.offButtonBgColor});
			if (onlineState != '1' || transportUri == '') {
				jQuery('#play').get(0).disabled = true;
				jQuery('#pause').get(0).disabled = true;
				jQuery('#stop').get(0).disabled = true;
				jQuery('#prevTrack').get(0).disabled = true;
				jQuery('#nextTrack').get(0).disabled = true;
			}
			else {
				jQuery('#play').get(0).disabled = false;
				jQuery('#pause').get(0).disabled = false;
				jQuery('#stop').get(0).disabled = false;
				jQuery('#prevTrack').get(0).disabled = false;
				jQuery('#nextTrack').get(0).disabled = false;
			}
		}
		else {
			if (nbrTracks == '' || nbrTracks == '0') {
				jQuery('#trackLabel').html('');
				jQuery('#track').html('');
				jQuery('#prevTrack').get(0).disabled = true;
				jQuery('#nextTrack').get(0).disabled = true;
			}
			else {
				jQuery('#trackLabel').html('Track:');
				jQuery('#track').html(currentTrack + '/' + nbrTracks);
				if (currentTrack == "1") {
					jQuery('#prevTrack').get(0).disabled = true;
				}
				else {
					jQuery('#prevTrack').get(0).disabled = false;
				}
				if (nbrTracks == currentTrack) {
					jQuery('#nextTrack').get(0).disabled = true;
				}
				else {
					jQuery('#nextTrack').get(0).disabled = false;
				}
			}

			if (playing == 'PLAYING' || playing == 'TRANSITIONING') {
				jQuery('#play').css({'background-color':Sonos.onButtonBgColor});
				jQuery('#pause').css({'background-color':Sonos.offButtonBgColor});
				jQuery('#stop').css({'background-color':Sonos.offButtonBgColor});
			}
			else if (playing == 'PAUSED_PLAYBACK') {
				jQuery('#play').css({'background-color':Sonos.offButtonBgColor});
				jQuery('#pause').css({'background-color':Sonos.onButtonBgColor});
				jQuery('#stop').css({'background-color':Sonos.offButtonBgColor});
			}
			else if (playing == 'STOPPED') {
				jQuery('#play').css({'background-color':Sonos.offButtonBgColor});
				jQuery('#pause').css({'background-color':Sonos.offButtonBgColor});
				jQuery('#stop').css({'background-color':Sonos.onButtonBgColor});
			}
			else {
				jQuery('#play').css({'background-color':Sonos.offButtonBgColor});
				jQuery('#pause').css({'background-color':Sonos.offButtonBgColor});
				jQuery('#stop').css({'background-color':Sonos.offButtonBgColor});
			}

			if (actions.indexOf('play', 0) >= 0) {
				jQuery('#play').get(0).disabled = false;
			}
			else {
				jQuery('#play').get(0).disabled = true;
			}
			if (actions.indexOf('pause', 0) >= 0) {
				jQuery('#pause').get(0).disabled = false;
			}
			else {
				jQuery('#pause').get(0).disabled = true;
			}
			if (actions.indexOf('stop', 0) >= 0) {
				jQuery('#stop').get(0).disabled = false;
			}
			else {
				jQuery('#stop').get(0).disabled = true;
			}
			if (actions.indexOf('previous', 0) < 0) {
				jQuery('#prevTrack').get(0).disabled = true;
			}
			if (actions.indexOf('next', 0) < 0) {
				jQuery('#nextTrack').get(0).disabled = true;
			}

			if (transportUri.indexOf('x-rincon-stream:', 0) == 0
					|| transportUri.indexOf('x-rincon-mp3radio:', 0) == 0
					|| transportUri.indexOf('x-sonosapi-stream:', 0) == 0
					|| transportUri.indexOf('x-sonosapi-hls:', 0) == 0
					|| transportUri.indexOf('x-sonosapi-radio:', 0) == 0
					|| transportUri.indexOf('http:', 0) == 0
					|| transportUri.indexOf('pndrradio:', 0) == 0) {
				if ((transportUri.indexOf('x-rincon-mp3radio:', 0) == 0
							|| transportUri.indexOf('http:', 0) == 0
							|| transportUri.indexOf('x-sonosapi-stream:', 0) == 0)
						&& title != '') {
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
				if (transportUri.indexOf('x-sonosapi-radio:', 0) != 0
						&& transportUri.indexOf('pndrradio:', 0) != 0) {
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

		if (mute == '1') {
			jQuery('#mute').css({'background-color':Sonos.onButtonBgColor});
		}
		else {
			jQuery('#mute').css({'background-color':Sonos.offButtonBgColor});
		}

		if (onlineState == '1') {
			jQuery('#mute').get(0).disabled = false;
			jQuery('#volumeDown').get(0).disabled = false;
			jQuery('#volumeUp').get(0).disabled = false;
			jQuery('#volumeSet').get(0).disabled = false;
			jQuery('#playUri').get(0).disabled = false;
			jQuery('#playAudioInput').get(0).disabled = false;
			jQuery('#playSQ').get(0).disabled = false;
			jQuery('#playFavRadio').get(0).disabled = false;
			jQuery('#playFavorite').get(0).disabled = false;
			if (coordinator != uuid) {
				jQuery('#playQueue').get(0).disabled = true;
				jQuery('#clearQueue').get(0).disabled = true;
			}
			else {
				jQuery('#playQueue').get(0).disabled = false;
				jQuery('#clearQueue').get(0).disabled = false;
			}
		}
		else {
			jQuery('#mute').get(0).disabled = true;
			jQuery('#volumeDown').get(0).disabled = true;
			jQuery('#volumeUp').get(0).disabled = true;
			jQuery('#volumeSet').get(0).disabled = true;
			jQuery('#playUri').get(0).disabled = true;
			jQuery('#playAudioInput').get(0).disabled = true;
			jQuery('#playSQ').get(0).disabled = true;
			jQuery('#playFavRadio').get(0).disabled = true;
			jQuery('#playFavorite').get(0).disabled = true;
			jQuery('#playQueue').get(0).disabled = true;
			jQuery('#clearQueue').get(0).disabled = true;
		}

		jQuery('#volume').html(volume);

		Sonos.prevCoordinator = coordinator;
		Sonos.prevOnlineState = onlineState;
		Sonos.prevCurrentAlbumArtUrl = currentAlbumArtUrl;
		Sonos.prevTitle = title;
		Sonos.prevAlbum = album;
		Sonos.prevArtist = artist;
		Sonos.prevDetails = details;
		Sonos.prevCurrentTrack = currentTrack;
		Sonos.prevNbrTracks = nbrTracks;
		Sonos.prevPlaying = playing;
		Sonos.prevActions = actions;
		Sonos.prevTransportUri = transportUri;
		Sonos.prevCurrentService = currentService;
		Sonos.prevCurrentRadio = currentRadio;
		Sonos.prevMute = mute;
		Sonos.prevVolume = volume;
	}

	Sonos.timeoutVar = setTimeout("Sonos_refreshPlayer("+device+")", 500);
}

function Sonos_refreshDiscovery(device)
{
	var modelName = get_device_state(device, Sonos.SONOS_SID, "SonosModelName", 1);
	if (modelName == undefined) {
		modelName = '';
	}
	var ip = '';
	for (i=0; i<jsonp.ud.devices.length; i++) {
		if (jsonp.ud.devices[i].id == device) {
			ip = jsonp.ud.devices[i].ip;
			break;
		}
	}
	var zone = get_device_state(device, Sonos.DEVICE_PROPERTIES_SID, "ZoneName", 1);
	if (zone == undefined) {
		zone = '';
	}
	var onlineState = get_device_state(device, Sonos.SONOS_SID, "SonosOnline", 1);
	if (onlineState == '1') {
		onlineState = 'ON';
	}
	else {
		onlineState = 'OFF';
	}
	var proxy = get_device_state(device, Sonos.SONOS_SID, "ProxyUsed", 1);
	if (proxy == undefined) {
		proxy = '';
	}
	var resultDiscovery = get_device_state(device, Sonos.SONOS_SID, "DiscoveryResult", 1);
	if (resultDiscovery == undefined) {
		resultDiscovery = '';
	}
	var patchInstalled = get_device_state(device, Sonos.SONOS_SID, "DiscoveryPatchInstalled", 1);
	if (patchInstalled == "1") {
		patchInstalled = "Installed";
	}
	else {
		patchInstalled = "Not installed";
	}

	if (modelName != Sonos.prevModelName
		|| ip != Sonos.prevIp
		|| zone != Sonos.prevZone
		|| onlineState != Sonos.prevOnlineState2
		|| proxy != Sonos.prevProxy
		|| resultDiscovery != Sonos.prevResultDiscovery
		|| patchInstalled != Sonos.prevPatchInstalled) {

		Sonos.prevModelName = modelName;
		Sonos.prevIp = ip;
		Sonos.prevZone = zone;
		Sonos.prevOnlineState2 = onlineState;
		Sonos.prevProxy = proxy;
		Sonos.prevResultDiscovery = resultDiscovery;
		Sonos.prevPatchInstalled = patchInstalled;

		jQuery('#patch').html(patchInstalled);
		if (patchInstalled == 'Installed') {
			jQuery('#install').get(0).disabled = true;
			jQuery('#uninstall').get(0).disabled = false;
		}
		else {
			jQuery('#install').get(0).disabled = false;
			jQuery('#uninstall').get(0).disabled = true;
		}

		jQuery('#IP').html(ip);
		var zoneText;
		if (zone != '' && modelName != '') {
			zoneText = zone + ' (' + modelName + ')';
		}
		else {
			zoneText = zone;
		}
		jQuery('#zone').html(zoneText);
		jQuery('#state').html(onlineState);
		jQuery('#proxy').html(proxy);

		if (resultDiscovery == 'scanning') {
			jQuery('#discover').get(0).disabled = true;
			jQuery('#discover').html('Scanning ...');
			jQuery('#discovery').html('');
			jQuery('#selectDiscovery').get(0).disabled = true;
		}
		else if (resultDiscovery == "") {
			jQuery('#discover').get(0).disabled = false;
			jQuery('#discover').html('Discover');
			jQuery('#selectDiscovery').get(0).disabled = true;
			jQuery('#discovery').html('');
		}
		else {
			jQuery('#discover').get(0).disabled = false;
			jQuery('#discover').html('Discover');
			jQuery('#selectDiscovery').get(0).disabled = false;

			var html = '';
			var xml = Sonos.parseXml(resultDiscovery);
			if (typeof xml != 'undefined') {
				var items = xml.getElementsByTagName("device");
				for (i=0; i<items.length; i++) {
					var url = Sonos_extractXmlTag(items[i], 'descriptionURL');
					if (url == undefined) {
						url = '';
					}
					var name = Sonos_extractXmlTag(items[i], 'friendlyName');
					if (name == undefined) {
						name = '';
					}
					var adrIP = Sonos_extractXmlTag(items[i], 'ip');
					if (adrIP == undefined) {
						adrIP = '';
					}
					var selected = '';
					if (adrIP == ip) {
						selected = ' selected';
					}
					var room = Sonos_extractXmlTag(items[i], 'roomName');
					if (room == undefined) {
						room = '';
					}
					html += '<option ' + selected + ' value="' + url + '">' + room + ' (' + name + ')</option>';
				}
			}
			jQuery('#discovery').html(html);
		}
	}

	Sonos.timeoutVar2 = setTimeout("Sonos_refreshDiscovery("+device+")", 1000);
}

function Sonos_refreshTTS(device)
{
	var onlineState = get_device_state(device, Sonos.SONOS_SID, "SonosOnline", 1);
	if (onlineState == undefined) {
		onlineState = '1';
	}

	if (onlineState != Sonos.prevOnlineState3) {

		if (onlineState == '1') {
			jQuery('#say').get(0).disabled = false;
		}
		else {
			jQuery('#say').get(0).disabled = true;
		}

		Sonos.prevOnlineState3 = onlineState;
	}

	Sonos.timeoutVar3 = setTimeout("Sonos_refreshTTS("+device+")", 1000);
}

function Sonos_play(device)
{
	Sonos_callAction(device, Sonos.MEDIA_NAVIGATION_SID, 'Play', {} );
}

function Sonos_pause(device)
{
	Sonos_callAction(device, Sonos.MEDIA_NAVIGATION_SID, 'Pause', {} );
}

function Sonos_stop(device)
{
	Sonos_callAction(device, Sonos.MEDIA_NAVIGATION_SID, 'Stop', {} );
}

function Sonos_prevTrack(device)
{
	Sonos_callAction(device, Sonos.MEDIA_NAVIGATION_SID, 'SkipUp', {} );
}

function Sonos_nextTrack(device)
{
	Sonos_callAction(device, Sonos.MEDIA_NAVIGATION_SID, 'SkipDown', {} );
}

function Sonos_mute(device)
{
	Sonos_callAction(device, Sonos.RENDERING_CONTROL_SID, 'SetMute', {} );
}

function Sonos_setVolume(device, volume)
{
	if (jQuery('#newVolume option:selected').index() >= 0) {
		var volume = jQuery('#newVolume').val();
		Sonos_callAction(device, Sonos.RENDERING_CONTROL_SID, 'SetVolume', {'DesiredVolume':volume} );
	}
}

function Sonos_volumeDown(device)
{
	Sonos_callAction(device, Sonos.VOLUME_SID, 'Down', {} );
}

function Sonos_volumeUp(device)
{
	Sonos_callAction(device, Sonos.VOLUME_SID, 'Up', {} );
}

function Sonos_playAudioInput(device)
{
	if (jQuery('#audioInputs option:selected').index() >= 0) {
		var uri = encodeURIComponent(jQuery('#audioInputs').val());
		//jQuery('#debug').html(uri);
		Sonos_callAction(device, Sonos.SONOS_SID, 'PlayURI', {'URIToPlay':uri} );
	}
}

function Sonos_playSQ(device)
{
	if (jQuery('#savedQueues option:selected').index() >= 0) {
		var id = encodeURIComponent('ID:' + jQuery('#savedQueues').val());
		//jQuery('#debug').html(id);
		Sonos_callAction(device, Sonos.SONOS_SID, 'PlayURI', {'URIToPlay':id} );
	}
}


function Sonos_clearQueue(device)
{
	Sonos_callAction(device, Sonos.AVTRANSPORT_SID, 'RemoveAllTracksFromQueue', {'InstanceID':'0'} );
}

function Sonos_playQueue(device)
{
	var uri = 'Q:';
	var idx = jQuery('#queue option:selected').index();
	if (idx >= 0) {
		idx += 1;
		uri += idx;
	}
	//jQuery('#debug').html(uri);
	Sonos_callAction(device, Sonos.SONOS_SID, 'PlayURI', {'URIToPlay':uri} );
}

function Sonos_playFavRadio(device)
{
	if (jQuery('#favRadios option:selected').index() >= 0) {
		var id = encodeURIComponent('ID:' + jQuery('#favRadios').val());
		//jQuery('#debug').html(id);
		Sonos_callAction(device, Sonos.SONOS_SID, 'PlayURI', {'URIToPlay':id} );
	}
}

function Sonos_playFavorite(device)
{
	if (jQuery('#favorites option:selected').index() >= 0) {
		var id = encodeURIComponent('ID:' + jQuery('#favorites').val());
		//jQuery('#debug').html(id);
		Sonos_callAction(device, Sonos.SONOS_SID, 'PlayURI', {'URIToPlay':id} );
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
		Sonos_callAction(device, Sonos.SONOS_SID, 'PlayURI', {'URIToPlay':uri} );
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
		Sonos_callAction(device, Sonos.SONOS_SID, 'Say', {'Text':text, 'Language':language, 'Engine':engine, 'Volume':volume, 'GroupZones':zones, 'SameVolumeForAll':sameVolume} );
	}
}

function Sonos_setupTTS(device)
{
	var language = jQuery('#defaultLanguage').val();
	var engine = jQuery('#defaultEngine').val();
	var url = encodeURIComponent(jQuery('#GoogleTTSserverURL').val());
	var url2 = encodeURIComponent(jQuery('#TTSserverURL').val());
	var url3 = encodeURIComponent(jQuery('#MaryTTSserverURL').val());
	var clientId = encodeURIComponent(jQuery('#ClientId').val());
	var clientSecret = encodeURIComponent(jQuery('#ClientSecret').val());
	Sonos_callAction(device, Sonos.SONOS_SID, 'SetupTTS', {'DefaultLanguage':language, 'DefaultEngine':engine, 'GoogleTTSServerURL':url, 'OSXTTSServerURL':url2, 'MaryTTSServerURL':url3, 'MicrosoftClientId':clientId, 'MicrosoftClientSecret':clientSecret} );
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
	//jQuery('#debug').html(zones);
	Sonos_callAction(device, Sonos.SONOS_SID, 'UpdateGroupMembers', {'Zones':zones} );
}

function Sonos_installPatch(device)
{
	Sonos_callAction(device, Sonos.SONOS_SID, 'InstallDiscoveryPatch', {} );
}

function Sonos_uninstallPatch(device)
{
	Sonos_callAction(device, Sonos.SONOS_SID, 'UninstallDiscoveryPatch', {} );
}

function Sonos_startSonosDiscovery(device)
{
	Sonos_callAction(device, Sonos.SONOS_SID, 'StartSonosDiscovery', {} );
}

function Sonos_selectDiscovery(device)
{
	if (jQuery('#discovery option:selected').index() >= 0) {
		var url = encodeURIComponent(jQuery('#discovery').val());
		//jQuery('#debug').html(url);
		Sonos_callAction(device, Sonos.SONOS_SID, 'SelectSonosDevice', {'URL':url} );
	}
}

function Sonos_selectIP(device)
{
	if (jQuery('#newIP').val() != "") {
		var url = encodeURIComponent('http://' + jQuery('#newIP').val() + ':1400/xml/device_description.xml');
		//jQuery('#debug').html(url);
		Sonos_callAction(device, Sonos.SONOS_SID, 'SelectSonosDevice', {'URL':url} );
	}
}

function Sonos_checkState(device)
{
	if (jQuery('#IP').html() != "") {
		var url = encodeURIComponent('http://' + jQuery('#IP').html() + ':1400/xml/device_description.xml');
		//jQuery('#debug').html(url);
		Sonos_callAction(device, Sonos.SONOS_SID, 'SelectSonosDevice', {'URL':url} );
	}
}

function Sonos_updateCheckStateRate(device)
{
	var rate = undefined;
	if (jQuery('#stateAutoCheckOn').is(':checked')) {
		var reg1 = new RegExp('^\\d+$', '');
		if (jQuery('#rate').val() == ''
				|| !jQuery('#rate').val().match(reg1)
				|| jQuery('#rate').val() == 0) {
			jQuery('#rate').val('5');
		}
		jQuery('#setCheckState').get(0).disabled = false;
	}
	else if (jQuery('#stateAutoCheckOff').is(':checked')) {
		jQuery('#rate').val('0');
		jQuery('#setCheckState').get(0).disabled = true;
	}
	var rate = jQuery('#rate').val();
	Sonos_callAction(device, Sonos.SONOS_SID, 'SetCheckStateRate', { 'rate':rate } );
}

function Sonos_setDebugLogs(device) {
	var enable = undefined;
	if (jQuery('#debugLogsOn').is(':checked')) {
		enable = 'true';
	}
	else if (jQuery('#debugLogsOff').is(':checked')) {
		enable = 'false';
	}
	if (enable != undefined) {
		Sonos_callAction(device, Sonos.SONOS_SID, 'SetDebugLogs', { 'enable':enable } );
	}
}

function Sonos_setReadQueue(device) {
	var enable = undefined;
	if (jQuery('#readQueueOn').is(':checked')) {
		enable = 'true';
	}
	else if (jQuery('#readQueueOff').is(':checked')) {
		enable = 'false';
	}
	if (enable != undefined) {
		Sonos_callAction(device, Sonos.SONOS_SID, 'SetReadQueueContent', { 'enable':enable } );
	}
}

function Sonos_callAction(device, sid, actname, args) {
	var q={
		'id':'lu_action',
		'output_format':'xml',
		'DeviceNum':device,
		'serviceId':sid,
		'action':actname
	};
	var key;
	for (key in args) {
		q[key] = args[key];
	}
    if (Sonos.browserIE) {
    	q['timestamp'] = new Date().getTime(); //we need this to avoid IE caching of the AJAX get
    }
	new Ajax.Request (command_url+'/data_request', {
		method: 'get',
		parameters: q,
		onSuccess: function (response) {
		},
		onFailure: function (response) {
		},
		onComplete: function (response) {
		}
	});
}

