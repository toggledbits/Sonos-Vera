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

**IMPORTANT** Currently, it is *highly* recommended that the "UPnP Event Proxy" plugin be installed on Vera when running this plugin. The event proxy makes it possible for the Sonos plugin to be proactively notified of state changes on the media player(s). If not used, the Sonos plugin will, by default, poll the player frequently, resulting in additional load on your Vera and additional network traffic (when most of time nothing of value is happening/changing). See the "Other Configuration" section below for additional information on controlling polling rate.

Please see CHANGELOG.md for release notes.

## Installation (New and Existing Users)

![Caution: Read Instructions First](https://www.toggledbits.com/assets/rtfm.png)

Please read the installation instructions through completely to get an idea of what you're going to be doing before you start doing it.

## Uninstalling Sonos 1.4.x

**This section only applies to those users that are currently running any 1.4.x (or earlier) version of the Sonos Plugin.** If you are not sure, you can run this part of the procedure safely anyway--it will not harm anything.

Before installing 2.0, you **must** uninstall the existing Sonos plugin using the procedure described below. This procedure will decouple your Sonos devices, so that when you uninstall the plugin, your existing Sonos devices are preserved. They will be adopted by 2.0 as children, keeping their current device numbers, which will keep your scenes, Lua, Reactor, PLEG, etc. intact.

1. Run the following Lua in *Apps > Develop apps > Test Luup code*.
   ```
   for n,d in pairs( luup.devices ) do
       if d.device_type == "urn:schemas-micasaverde-com:device:Sonos:1" then
           luup.attr_set( "plugin", "", n )
       end
   end
   luup.reload()
   ```
2. When Luup finishes reloading, go to *Apps > My apps* and uninstall the existing Sonos plugin (if it's not listed there, no problem, just move on to the next step).
3. Reload luup. I usually just to go *Apps > Develop apps > Test Luup code* and run `luup.reload()`

## Install Sonos Plugin 2.0 (all users)

1. Open the Github develop branch repository: https://github.com/toggledbits/Sonos-Vera/tree/develop
2. Click the green "Clone or download" button and choose "Download ZIP"
3. Save the ZIP file.
4. Unzip the ZIP file
5. In the Vera UI, go to *Apps > Develop apps > Luup files*
6. Multi-select the files (not folders--ignore any folders) you unzipped and drag them as a group to the "Upload" button.
7. When the upload completes, Luup will reload.
8. When the reload completes, create the Sonos System master device:

   1. Go to *Apps > Develop apps > Create device*
   2. In the "Description" field, enter `Sonos System`
   3. In the "UPnP Device Filename" field, enter `D_SonosSystem1.xml`
   4. In the "UPnP Implementation Filename" field, enter `I_SonosSystem1.xml`
   5. You may choose a room assignment if you wish.
   6. Click "Create device"
9. Go to *Apps > Develop apps > Test luup code* and reload luup by running `luup.reload()`
10. Wait about five minutes. Your Vera may reload several times during this time.
11. [Hard refresh your browser](https://www.getfilecloud.com/blog/2015/03/tech-tip-how-to-do-hard-refresh-in-browsers/). Do not skip this step. You should now see your Sonos devices, and the Sonos System master device should report the number of zone players it is managing.

If anything appears out of whack and it doesn't resolve in 5-10 minutes, repeat steps 9-11. Sometimes it takes a couple of reloads and hard refreshes to get everything sorted.

The new Sonos System master device will adopt your previous/existing Sonos devices as its children (with the same device number they've always had), and create new child devices for any other zone players discovered on the network. There is usually no need to run discovery manually in this version.

### Installation using AltAppStore

Once published to the AltAppStore, you'll be able to install this plugin on Vera or openLuup from the AltAppStore in the usual way. Working on it...

**openLuup Users:** Please note that additional configuration is required to use TTS. Please see "Special TTS Configuration for openLuup" below.

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

If you are using the plugin on openLuup, you will first need to configure the `TTSBaseURL` and `TTSBasePath` state variables. The TTS services require that sound files be written somewhere where they can retrieved by an HTTP request from the Sonos players in your network. This may be within the openLuup directory tree, but not necessarily; configuration will depend on how your openLuup is installed and where, and what if any additional services (e.g. Apache) may be running on the same host. As a result, local knowledge is required.

Set the `TTSBasePath` to the full pathname of a directory in your openLuup installation where the sound files should be written, and set `TTSBaseURL` to the full URL (e.g. `http://192.168.0.2:80`) that can be used to retrieve files written in the `TTSBasePath` directory.

If you're not sure, try setting `TTSBasePath` to the full directory path of the openLuup subdirectory containing the installed Sonos plugin files, and setting `TTSBaseURL` to `http://openluup-ip-addr:3480` (e.g. `http://192.168.0.120:3480`).

## Other Configuration

### `PollDelays`

If the UPnP Event Proxy is not installed or cannot be contacted, the Sonos plugin will poll players for status. As of 1.4.3-19188, the `PollDelays` state variable contains a pair of numbers, which are the delays to be used for polling when active and inactive (player stopped), respectively. The default is 15 seconds for active players, and 60 seconds on stopped players. This reduces network traffic somewhat, but it's still not as good as using the UPnP Event Proxy, so the proxy remains the recommended solution.

## Uninstalling the Last Released Version

These instructions are only to be used to uninstall the plugin if it was previously installed from the Vera App/Plugin Marketplace. If you are not sure, go to *Apps > My apps* and page through your officially-installed plugins. If Sonos is listed there, **you must uninstall it using the instructions below** before installing the Github version of the plugin.

1. Copy-paste the following into *Apps > Develop apps > Test Luup code (Lua)*:
```
for n,d in pairs( luup.devices ) do
    if luup.attr_get( 'plugin', n ) == "4226" then
        luup.attr_set( "plugin", "", n )
    end
end
luup.reload()
```
2. Run the above code by hitting the "GO" button (if you've already hit GO in the previous step, fine, but once is enough and a second click might generate a harmless error). The code performs a Luup reload, so wait a minute before continuing.
3. Uninstall the Sonos plugin by going to *Apps > My apps*, locating the plugin, going into "Details", and hitting "Uninstall".
4. Install the Github version of the plugin per the instructions above. 

The first two steps detach your existing Sonos devices from the plugin, so that they are not deleted when the Sonos plugin is uninstalled. They will become invisible, but should re-appear after you install the Github version.

## User Support

Support for this project is offered through the Vera Community Forums [Sonos category](https://community.getvera.com/c/plugins-and-plugin-development/sonos-plugin). Please post your questions/problems/suggestions there.

## Donations

Donations in support of this and other projects are greatly appreciated: https://www.toggledbits.com/donate

## License

This work is licensed under the Creative Commons Attribution-ShareAlike 2.0 Generic License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/ or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.
