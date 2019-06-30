# Sonos-Vera

This project is the derivation and enhancement of lolodomo's original Sonos plugin for Vera.
The original plugin serviced the Vera community through many versions of firmware and was a
valuable addition to the ecosystem. Unfortunately, lolodomo moved on to another platform
several years ago, but he released his original work into the public domain, so this project
takes that code and continues its support and enhancement.

The project is currently led by Vera Community user [rigpapa](https://community.getvera.com/u/rigpapa).
If you would like to volunteer to be a part of the community support of this project, please drop him
a PM, as more community volunteers are needed for development and testing.

## Installation

Currently, this project is distributed exclusively through its [Github repository](https://github.com/toggledbits/Sonos-Vera/) and the AltAppStore.
Release in the Vera plugin marketplace is planned for later.

**IMPORTANT** Currently, it is *highly* recommended that the "UPnP Event Proxy" plugin be installed on Vera when running this plugin. The event proxy makes it possible for the Sonos plugin to be proactively notified of state changes on the media player(s). If not used, the Sonos plugin will, by default, poll the player frequently, resulting in additional load on your Vera and additional network traffic (when most of time nothing of value is happening/changing). See the "Other Configuration" section below for additional information on controlling polling (TBD???).

### Installation on Vera

1. Go to [the Github repository for the project](https://github.com/toggledbits/Sonos-Vera).
2. Click the green "Clone or download" button and choose "Download ZIP". Save the ZIP file somewhere.
3. Unzip the ZIP file.
4. Select the files (except the `.md` files) as a group and drag them to the upload tool at *Apps > Develop apps > Luup files*. This will upload all the files as a single batch and then restart Luup.
5. After the Luup restart, go to *Apps > Develop apps > Create device*, enter and submit:
  * Description: `Sonos` (or whatever you choose)
  * Device UPnP Filename: `D_Sonos1.xml` (exactly as shown)
  * Device UPnP Filename: `I_Sonos1.xml` (exactly as shown)
    > WARNING: You must enter the filenames exactly as shown above. Any error may cause your system to not restart and require intervention from Vera Support.
  * IP Address: *enter the IP address of your Sonos player, if you know it*
    > NOTE: If you enter the IP address here, you can skip step 8 below. If you do not know the IP address of your player, leave the field blank--step 8 should find it.
  * Hit the "Create device" button.
6. Go to *Apps > Develop apps > Test Luup code (Lua)* and enter/run: `luup.reload()` 
7. After Luup finishes reloading, [hard-refresh your browser](https://www.getfilecloud.com/blog/2015/03/tech-tip-how-to-do-hard-refresh-in-browsers/). This is a vital step that cannot be skipped!
8. You can then go into the "Settings" tab of the Sonos device and use discovery to find your first Sonos media player. 
9. Repeat steps 5-8 for each additional zone player.

## State Variables

### urn:micasaverde-com:serviceId:Sonos1

* CurrentService - name of the current service, for example "TuneIn"
* CheckStateRate - number of minutes between each automatic online check, "0" to disable the automatic check
* DebugLogs - "1" when the debug logs are enabled or "0" when disabled
* DefaultLanguageTTS - default language for TTS, for example "en" or "en-US"
* DefaultEngineTTS - default engine for TTS, either "GOOGLE" or "MICROSOFT" or "OSX_TTS_SERVER" or "MARY"
* DiscoveryPatchInstalled - "1" when the !UPnP discovery patch is installed or "0" when not installed
* DiscoveryResult - for plugin internal usage
* FetchQueue - "1" when the Sonos queue is read by the plugin or "0" when not
* GoogleTTSServerURL - the Google URL to be used for TTS
* GroupCoordinator - UUID of the group coordinator
* MaryTTSServerURL - URL of the MaryTTS server
* ResponseVoiceTTSServerURL - URL of the ResponsiveVoice TTS service
* MicrosoftClientId - Client ID you got when you regisered your application on the Microsoft Azure Marketplace
* MicrosoftClientSecret - Client Secret you got when you regisered your application on the Microsoft Azure Marketplace
* OSXTTSServerURL - URL of the TTS server
* PluginVersion - plugin version
* ProxyUsed - "proxy is in use" or "proxy is not in use" to indicate if the UPnP event proxy is in use
* RouterIp - router/firewall IP when the Sonos unit can access the Vera only with a port forwarding rule
* RouterPort - router/firewall port when the Sonos unit can access the Vera only with a port forwarding rule
* SonosModel - for plugin internal usage (icon management)
* SonosModelName - model of the Sonos unit, for example "Sonos PLAY:5" or "Sonos CONNECT:AMP"
* SonosOnline - "1" when the Sonos is online or "0" when it is offline
* SonosServicesKeys - for plugin internal usage
* TTSBasePath - Local directory path where TTS sound files will be written (must be retrievable at `TTSBaseURL` below)
* TTSBaseURL - URL to TTS sound files (default: `http://vera-ip-addr/port_3480`)

> Note: See "Special TTS Configuration for openLuup" below for instructions on setting `TTSBasePath` and `TTSBaseURL` under openLuup.
 
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

Language is either a string of 2 characters, like en, fr ... or a string of 5 characters like en-US, en-GB, fr-FR, fr-CA, ...

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

### Making a Sonos play an alert message
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

## Configuring TTS

As of this writing, the only reliably-working TTS services are [MaryTTS](http://mary.dfki.de/) and ResponsiveVoice, and the latter is potentially going away. 

GoogleTTS, which has long been the default, is now being limited by Google and attempts to use it result in "suspicious activity" blocks from their servers pretty quickly--this is why it works for a while and then quietly stops working. It's possible we may reconnect this service to Google's newer "official" TTS cloud service at some point (requires account registration), but at the moment, the GoogleTTS engine is basically dead and should not be used.

We also believe Microsoft TTS is dead, but we haven't removed it from the code yet.

Status of OSX TTS is unknown as of this writing. Can anybody test?

### Special TTS Configuration for openLuup

If you are using the plugin on openLuup, you will need to configure the `TTSBaseURL` and `TTSBasePath` state variables. The TTS services require that sound files be written somewhere where they can retrieved by an HTTP request from the Sonos players in your network. This may be within the openLuup directory tree, but not necessarily; configuration will depend on how your openLuup is installed and where, and what if any additional services (e.g. Apache) may be running on the same host. As a result, local knowledge is required.

Set the `TTSBasePath` to the full pathname of a directory in your openLuup installation where the sound files should be written, and set `TTSBaseURL` to the full URL (e.g. `http://192.168.0.2:80`) that can be used to retrieve files written in the `TTSBasePath` directory.

If you're not sure, try setting `TTSBasePath` to the full directory path of the openLuup subdirectory containing the installed Sonos plugin files, and setting `TTSBaseURL` to `http://openluup-ip-addr:3480` (e.g. `http://192.168.0.120:3480`).

## Other Configuration

TBD

## User Support

Support for this project is offered through the Vera Community Forums [Sonos category](https://community.getvera.com/c/plugins-and-plugin-development/sonos-plugin). Please post your questions/problems/suggestions there.

## License

This work is licensed under the Creative Commons Attribution-ShareAlike 2.0 Generic License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/ or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.