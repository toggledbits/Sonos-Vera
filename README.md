# Sonos-Vera

This project is the derivation and enhancement of lolodomo's original Sonos plugin for Vera.
The original plugin serviced the Vera community through many versions of firmware and was a
valuable addition to the ecosystem. Unfortunately, lolodomo moved on to another platform
several years ago, but he released his original work into the public domain, so this project
takes that code and continues its support and enhancement.

The project is currently led by Vera Community user [rigpapa](https://community.getvera.com/u/rigpapa).
If you would like to volunteer to be a part of the community support of this project, please drop him
a PM, as more community volunteers are needed for development and testing.

This project is distributed exclusively through its [Github repository](https://github.com/toggledbits/Sonos-Vera/) and the AltAppStore.
Release in the Vera plugin marketplace is planned for later.

**IMPORTANT** Currently, it is *highly* recommended that the "UPnP Event Proxy" plugin be installed on Vera when running this plugin; installing the UPnP Event Proxy can be done from the Settings page of the Sonos plugin. The event proxy makes it possible for the plugin to be proactively notified of state changes on the media player(s). If not used, the Sonos plugin will, by default, poll the player frequently, resulting in additional load on your Vera and additional network traffic (when most of time nothing of value is happening/changing). See the "Other Configuration" section below for additional information on controlling polling rate.

Please see CHANGELOG.md for release notes.

## Installation (New and Existing Users)

Currently, the Vera App Marketplace version of the Sonos plugin is out of date and will not be updated. Installation of the latest version must be done from Github as follows.

**openLuup Users:** Please note that additional configuration is required to use TTS. Please see "Special TTS Configuration for openLuup" below.

1. Download the desired release ZIP package from here: https://github.com/toggledbits/Sonos-Vera/releases
2. Unzip the downloaded file;
3. In the Vera UI, go to *Apps > Develop apps > Luup files*;
4. Open the unzipped folder;
5. Group-select the files in the folder (not the folder itself) and drag them as a group to the *Upload* button in the Vera UI;
6. The files will be uploaded and your Vera will reload Luup;
7. When the reload completes, [hard-refresh your browser](https://www.howtogeek.com/672607/how-to-hard-refresh-your-web-browser-to-bypass-your-cache/) (important step, do not skip it!).

## State Variables

### urn:micasaverde-com:serviceId:SonosSystem1

* DebugLogs - 0 - logs disabled; non-zero, logging bits: 1 - plugin, 2 - UPnP, 4 - TTS (e.g. setting to 5 turns on debug logging for the plugin and TTS)
* DefaultLanguageTTS - default language for TTS, for example "en" or "en-US"
* DefaultEngineTTS - default engine for TTS, either "GOOGLE" or "MICROSOFT" or "OSX_TTS_SERVER" or "MARY"
* DiscoveryPatchInstalled - "1" when the !UPnP discovery patch is installed or "0" when not installed
* DiscoveryResult - for plugin internal usage
* FetchQueue - "1" when the Sonos queue is read by the plugin or "0" when not
* GoogleTTSServerURL - the Google URL to be used for TTS
* MaryTTSServerURL - URL of the MaryTTS server
* ResponseVoiceTTSServerURL - URL of the ResponsiveVoice TTS service
* MicrosoftClientId - Client ID you got when you regisered your application on the Microsoft Azure Marketplace
* MicrosoftClientSecret - Client Secret you got when you regisered your application on the Microsoft Azure Marketplace
* OSXTTSServerURL - URL of the TTS server
* PluginVersion - plugin version
* ProxyUsed - "proxy is in use" or "proxy is not in use" to indicate if the UPnP event proxy is in use
* RouterIp - router/firewall IP when the Sonos unit can access the Vera only with a port forwarding rule
* RouterPort - router/firewall port when the Sonos unit can access the Vera only with a port forwarding rule
* TTSBasePath - Local directory path where TTS sound files will be written (must be retrievable at `TTSBaseURL` below)
* TTSBaseURL - URL to TTS sound files (default: `http://vera-ip-addr/port_3480`)
* TTSChime - Comma-separated WAV filename and duration (seconds) of chime file (set to "," to disable chime)

> Note: See "Special TTS Configuration for openLuup" below for instructions on setting `TTSBasePath` and `TTSBaseURL` under openLuup.
 

### urn:micasaverde-com:serviceId:Sonos1

* CurrentService - name of the current service, for example "TuneIn"
* CheckStateRate - number of minutes between each automatic online check, "0" to disable the automatic check
* GroupCoordinator - UUID of the group coordinator
* SonosModel - for plugin internal usage (icon management; legacy, not used after 1.4.3)
* SonosModelName - model of the Sonos unit, for example "Sonos PLAY:5" or "Sonos CONNECT:AMP"
* SonosModelNumber - model number as reported by Sonos unit (e.g. ZP100, S1, S12, etc.)
* SonosOnline - "1" when the Sonos is online or "0" when it is offline
* SonosServicesKeys - for plugin internal usage

### urn:upnp-org:serviceId:DeviceProperties

* SonosID - UUID of the Sonos unit
* ZoneName - name of the Sonos unit

### urn:upnp-org:serviceId:AVTransport

* AVTransportURI -
* AVTransportURIMetaData -
* CurrentAlbum -
* CurrentAlbumArt -
* CurrentArtist -
* CurrentCrossfadeMode -
* CurrentDetails -
* CurrentMediaDuration -
* CurrentPlayMode -
* CurrentRadio -
* CurrentStatus -
* CurrentTitle -
* CurrentTrack -
* CurrentTrackDuration -
* CurrentTrackMetaData -
* CurrentTrackURI -
* CurrentTransportActions -
* NumberOfTracks -
* RelativeTimePosition
* TransportPlaySpeed - not updated when the UPnP event proxy is used
* TransportState -
* TransportStatus -
 
### urn:upnp-org:serviceId:ContentDirectory

* Favorites - data describing all the Sonos favorites (used by plugin UI)
* FavoritesRadios - data describing all the favorites radio stations (used by plugin UI)
* Queue - data describing the content of the Sonos queue (used by plugin UI)
* SavedQueues - data describing all the Sonos playlists (used by plugin UI)

### urn:upnp-org:serviceId:RenderingControl

* Mute - "1" if volume muted or "0" if unmuted
* Volume - general volume, value from 0 to 100

### urn:upnp-org:serviceId:ZoneGroupTopology

* ZonePlayerUUIDsInGroup - comma-separated list of UUIDs identifying the group members
* ZoneGroupState - XML data describing the Sonos network and the current state of all groups

## Actions

### Making a Sonos play something
This functionality is exposed declaratively through the PlayURI action under Advanced Scenes. The functionality is also exposed programmatically via Lua code:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", "PlayURI",
                 {URIToPlay="x-file-cifs:...", Volume=50},
                 666)
```

This action will play what is defined by the URIToPlay parameter. To know how to set this parameter, you can open the Help tab of the Vera Sonos device, you will discover a list of example usages with your current own context. Here are examples:

* `x-file-cifs:path` - Play the music file defined by "path"
* `x-rincon-mp3radio:url` - Play the MP3 WEB radio defined by "url"
* `Q:` - Play what is in the Sonos queue, starting at first item
* `Q:3` - Play what is in the Sonos queue, starting at third item
* `AI:` - Play the local line-in audio input
* `AI:name` - Play the line-in audio input of the Sonos unit with name "name"
* `TR:id` - Play the tunein radio station having "id" (a number) as id
* `SR:id` - Play the Sirius radio station having "id" as id
* `FR:radio` - Play the favorite radio station having "radio" as name
* `SF:title` - Play the Sonos favorite having "title" as title
* `SQ:name` - Play the Sonos playlist having "name" as name
* `GZ:name` - Group the Sonos to Sonos with name "name"

Notes:
* Parameters not specified will default internally. (Volume=nil) By default, the volume is not set.

### Making a Sonos say something
The Sonos plugin exposes Text to Speech capability through Google's service. The functionality is exposed declaratively through the Say action under Advanced Scenes. The functionality is also exposed programmatically via Lua code.

Suppose you have 4 Sonos zones named Bedroom, Bathroom, Living-room and Kitchen. Your bedroom Sonos is linked to device 666 in your Vera.

To play a message only in the bedroom, use this lua code:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", "Say",
                 {Text="The sun shines outside", Language="en"},
                 666)
```

This action will pause the current playback, say the text, and then the playback will be resumed.

Language is either a string of 2 characters, like en, fr ... or a string of 5 characters like en-US, en-GB, fr-FR, fr-CA, ... You will need to determine which works for the TTS engine you are using. Generally speaking, the most common TTS engine, ResponsiveVoice, requires the two-part language codes (e.g. en-US).

To play a message in the bedroom setting the volume for the message at level 60:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", "Say",
                 {Text="The sun shines outside", Language="en", Volume=60},
                 666)
```

The volume will be adjusted to play the message, and finally restored to its previous level. When the Volume parameter is not used, the volume is not adjusted and the message is played with the current volume.

To play a synchronized message in the bedroom, the bathroom and the kitchen:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", "Say",
                 {Text="The sun shines outside", Language="en", GroupZones="Bathroom,Kitchen"},
                 666)
```

After the text is said, the playback will be resumed on the 3 zones.

To play a synchronized message in all rooms setting the volume for the message at level 60 in all rooms:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", "Say",
                 {Text="The sun shines outside", Language="en", GroupZones="ALL",
                  Volume=60, SameVolumeForAll="true"},
                 666)
```

When the parameter SameVolumeForAll is set to false or not set, the volume is adjusted only on the main zone, that is the bedroom in our example.

To play a message in the bedroom using your personal OSX TTS server rather than using Google Internet service:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", "Say",
                 {Text="The sun shines outside", Language="en", Engine="OSX_TTS_SERVER"},
                 666)
```

Accepted values for the engine:

* `GOOGLE` for the Google TTS Internet service
* `MICROSOFT` for the Microsoft Translator Internet service
* `OSX_TTS_SERVER` for a personal OSX TTS server
* `MARY` for a personal MaryTTS server
* `RV` for ResponsiveVoice.org

In addition, the Text to Speech capability can be setup with the following variables (use the TTS tab to adjust the values):

* `DefaultLanguageTTS` - default language used when calling the Say action; must be either a string of 2 characters like "en" for example or a string of 5 characters like "en-US" or "en-GB" for example. Generally, the two-element (five character) is preferred, and some TTS engines require it.
* `DefaultEngineTTS` - default engine used when calling the Say action; must be either GOOGLE, MICROSOFT, OSX_TTS_SERVER or MARY
* `GoogleTTSServerURL` - the Google URL to be used (default: `http://translate.google.com`) **see Configuring TTS below**
* `OSXTTSServerURL` - defines the location of your OSX TTS server; something like ​http://www.mypersonaltts.org:80
* `MaryTTSServerURL` - defines the location of your MaryTTS server; something like ​http://192.168.0.50:59125 assuming 192.168.0.50 is the IP address of your server running MaryTTS
* `ResponsiveVoiceTTSServerURL` - URL for ResponsiveVoice (default: `https://code.responsivevoice.org`)
* `MicrosoftClientId` - Client ID you got when you regisered your application on the Microsoft Azure Marketplace
* `MicrosoftClientSecret` - Client Secret you got when you regisered your application on the Microsoft Azure Marketplace

Notes:
* Explanations on how to get Microsoft Translator credentials: ​https://msdn.microsoft.com/en-us/library/mt146806.aspx ; don't forget to get the free 2 Million characters per month subscription; finally set your Client ID and Client Secret in the TTS tab of the plugin (and push the Set button to save)
* Explanations on how to setup the OSX TTS server: ​http://wolfpaulus.com/jounal/mac/ttsserver/
* For GroupZones, you have to use room names (zone names defined with your Sonos application), not the name of your Vera device
* It is possible to use the parameter named GroupDevices in place of GroupZones. In this case, you must have a device in the Vera for all the Sonos zones you want to address. The value is a CSV list of device ids. For example, if your living-room and kitchen Sonos are linked respectively to devices 667 and 668 in your Vera, you will use GroupDevices="667,668". The GroupDevices has been kept for compatibility reasons with old versions but the use of GroupZones is now recommended.
* Parameters not specified will default internally. (Language=en, Engine=GOOGLE, GroupDevices="", GroupZones="", Volume=nil, SameVolumeForAll=false)

### TTS Caching

Version 1.5 introduced TTS caching--the first time a phrase is spoken, its audio is saved; when that phrase is spoken again, the saved audio file is used rather hitting the TTS Engine again to generate a new audio file. This makes TTS quicker and more reliable (e.g. when using ResponsiveVoice, a phrase that is spoken once no longer requires Internet access to be spoken again).

This has some side-effects. Among them:
1. Any changes in pronunciation as a result of upgrades to the TTS Engine will not be picked up, because the Engine is not being hit for the repeated phrase.
1. The matching of phrases is cached by engine, language, and text. If any of these changes, however trivially (e.g. addition of punctuation to speech text), the speech audio is regenerated.
1. Since only engine, language, and text are used as keys in the cache, other changes affecting TTS, such as rate and pitch, do not invalidate cache entries and cause regeneration of the audio. Thus a `Say` action with the phrase "Hello there" spoken first at rate 1.0 and then at rate 0.5 will both play the rate 1.0 audio.

The TTS cache is flushed any time the TTS default settings are saved. If you need to flush the cache, go the Sonos plugin device's Settings tab and hit the "Save Changes" button. Flushing the cache discards all previously-generated audio.

### Changing the TTS Chime

Version 2.0 introduced a chime prior to TTS announcements, with a default sound. The chime can be disabled on individual `Say` actions by including the `Chime` parameter in the action arguments, set to zero (0). The chime can be changed by setting the `TTSChime` state variable on the Sonos plugin device to a two-part, comma-separated value: the name of the chime WAV file, and its duration in seconds (e.g. the default is "Sonos_chime.wav,3"). Setting `TTSChime` to simply "," disables the chime for all `Say` actions. The chime file is located in the same directory as the plugin install/runtime files (e.g. `/etc/cmh-ludl` for Vera). If you wish to change the chime sound, the correct procedure is to upload a new WAV file that is *not* named `Sonos_chime.wav` (this is a plugin file that should not be modified), and modify the `TTSChime` variable to specify that name and the file's play duration.

### Making a Sonos play an alert sound
This functionality is exposed declaratively through the Alert action under Advanced Scenes. The functionality is also exposed programmatically via Lua code:

```
luup.call_action("urn:micasaverde-com:serviceId:Sonos1", "Alert",
                 {URI="x-file-cifs:...", Duration=15},
                 666)
```

If Duration parameter is set to a greater value than 0, this action will pause the current playback, play the alert, and the previous playback will be resumed when the delay defined by Duration expires. If Duration parameter is unset or set to 0, this action will pause the current playback, play the alert, but then the previous playback will not be resumed.

You can use the optional parameters Volume, SameVolumeForAll, GroupZones and GroupDevices. The usage is exactly the same as for the Say action.

Notes:
* For URI parameter, you can use the same syntax as for the !URIToPlay parameter of the action !PlayURI
* For GroupZones, you have to use room names (zone names defined with your Sonos application), not the name of your Vera device
* It is possible to use the parameter named GroupDevices in place of GroupZones. In this case, you must have a device in the Vera for all the Sonos zones you want to address. The value is a CSV list of device ids. For example, if your living-room and kitchen Sonos are linked respectively to devices 667 and 668 in your Vera, you will use GroupDevices="667,668". The GroupDevices has been kept for compatibility reasons with old versions but the use of GroupZones is now recommended.
* Parameters not specified will default internally. (Duration=0, GroupDevices="", GroupZones="", Volume=nil, SameVolumeForAll=false) By default, the volume is not set.

## Configuring TTS (Text-to-Speech)

As of this writing, the only reliably-working TTS services are [MaryTTS](http://mary.dfki.de/) and ResponsiveVoice, and the latter is potentially going away. 

If you are using any of the other services *successfully*, [please let us know](https://community.getvera.com/c/plugins-and-plugin-development/sonos-plugin):
* GoogleTTS, which has long been the default, is now being restricted by Google and attempts to use it result in "suspicious activity" blocks from their servers pretty quickly--this is why it works for a while and then suddenly stops working. To be fair to Google, it's because this "service" is actually borrowing a subfeature of Google Translate that was probably never intended to be used in this way (by us and many others, I'm sure), and Google has gotten wise to it. It's possible we may provide a replacement engine/service to Google's newer "official" TTS cloud service at some point (requires account/API registration), but at the moment, this GoogleTTS engine is basically dead and should not be used.
* Both OSX and Microsoft engines are unknown, rumored to be dead.

### Special TTS Configuration for openLuup

TTS on openLuup presents a small challenge in that the Sonos zones use the openLuup system to source the speech audio files. For technical reasons deeper than this document warrants (contact the author if you care to know), you must install Apache or a similar web server to serve the speech files. Instructions for Apache follow; if you intend to use a different server (nginx, lighttpd, etc.), then read these instructions and follow their spirit with the specifics of your server of choice.

1. Install the Apache web server. This is often as simple as `apt-get apache2` or `yum install apache2` depending on your Linux distribution.
2. Alias a path to your openLuup runtime directory, which is where the plugin keeps the TTS resource files that the zone players need to access. Add the following lines to the configuration of the default server instance (e.g. in many cases `/etc/apache2/sites-enabled/000-default.conf`). In the example below, change `/path/to/...etc...` to the full path of your openLuup runtime directory--the same directory in which the Sonos plugin's files are installed:

```
    Alias "/openluup/" "/path/to/your/openluup/directory/"
	<Directory "/path/to/your/openluup/directory/">
		Require all granted
	</Directory>
```

3. Make sure that either the Apache user/group or all users have directory traversal permissions (`rx`) on every directory on the path to your openLuup runtime directory.
3. Restart Apache, and then test by requesting `http://system-ip-address/openluup/Sonos_chime.mp3` in a browser. You should hear the Sonos TTS chime play in your browser.
3. Make sure the state variable `LocalIP` on the Sonos master device is correctly configured to the IP address of the openLuup system; it *must not* be blank, `localhost` or `127.0.0.1`.
3. If (and only if) you have used any directory alias other than "/openluup/", set the `TTSBaseURL` state variable on your Sonos plugin master device to the same value. For example, if you configured "/house/" as the directory alias, set `TTSBaseURL` to `/house/` as well.
4. Reload openLuup.

Be sure to check the Apache error log for errors, in addition the LuaUPnP.log file, if TTS isn't working.

## Other Configuration

### `PollDelays`

If the UPnP Event Proxy is not installed or cannot be contacted, the Sonos plugin will poll players for status. As of 1.4.3-19188, the `PollDelays` state variable contains a pair of numbers, which are the delays to be used for polling when active and inactive (player stopped), respectively. The default is 15 seconds for active players, and 60 seconds on stopped players. This reduces network traffic somewhat, but it's still not as good as using the UPnP Event Proxy, so the proxy remains the recommended solution.

## User Support

Support for this project is offered through the Vera Community Forums [Sonos category](https://community.getvera.com/c/plugins-and-plugin-development/sonos-plugin). Please post your questions/problems/suggestions there.

## Donations

Donations in support of this and other projects are greatly appreciated: https://www.toggledbits.com/donate

## License

This work is licensed under the Creative Commons Attribution-ShareAlike 2.0 Generic License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/ or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.
