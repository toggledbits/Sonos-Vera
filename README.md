# Sonos-Vera

This project is the derivation and enhancement of lolodomo's original Sonos plugin for Vera.
The original plugin serviced the Vera community through many versions of firmware and was a
valuable addition to the ecosystem. Unfortunately, lolodomo moved on to another platform
several years ago, but he released his original work into the public domain, so this project
takes that code and continues its support and enhancement.

The project is currently led by Vera Community user (rigpapa)[https://community.getvera.com/u/rigpapa].
If you would like to volunteer to be a part of the community support of this project, please drop him
a PM, as more community volunteers are needed for development and testing.

## Installation

Currently, this project is distributed exclusively through its Github repository and the AltAppStore.
Release in the Vera plugin marketplace is planned for later.

> CAUTION! Currently, it is recommended that the "UPnP Event Proxy" plugin be installed on Vera when running this plugin. The event proxy makes it possible for the Sonos plugin to be proactively notified of state changes on the media player(s). If not used, the Sonos plugin will, by default, poll the player frequently, resulting in additional load on your Vera and additional network traffic (when most of time nothing of value is happening/changing). See the "Other Configuration" section below for additional information on controlling polling (TBD???).

### Installation on Vera

1. Go to (the Github repository for the project)[https://github.com/toggledbits/Sonos-Vera].
2. Click the green "Clone or download" button and choose "Download ZIP". Save the ZIP file somewhere.
3. Unzip the ZIP file.
4. Select the files (except the `.md` files) as a group and drag them to the upload tool at *Apps > Develop apps > Luup files*. This will upload all the files as a single batch and then restart Luup.
5. After the Luup restart, go to *Apps > Develop apps > Create device*, enter and submit:
  * Description: `Sonos` (or whatever you choose)
  * Device UPnP Filename: `D_Sonos1.xml` (exactly as shown)
  * Device UPnP Filename: `I_Sonos1.xml` (exactly as shown)
  > WARNING: You must enter the filenames exactly as shown above. Any error may cause your system to not restart and require intervention from Vera Support.
6. Go to *Apps > Develop apps > Test Luup code (Lua)* and enter/run: `luup.reload()` 
7. After Luup finishes reloading, (hard-refresh your browser)[https://www.getfilecloud.com/blog/2015/03/tech-tip-how-to-do-hard-refresh-in-browsers/]. This is a vital step that cannot be skipped!
8. You can then go into the "Settings" tab of the Sonos device and use discovery to find your first Sonos media player. 
9. Repeat steps 5-8 for each additional zone player.

## Configuring TTS

As of this writing, the only reliably-working TTS services are MaryTTS and ResponsiveVoice, and the latter is potentially going away. 

GoogleTTS, which has long been the default, is now being limited by Google and attempts to use it result in "suspicious activity" blocks pretty quickly--it works for a while and then quietly stops working. It's possible we may reconnect this service to Google's newer TTS cloud service at some point, but at the moment, it's basically dead and should not be used.

We also believe Microsoft TTS is dead, but we haven't removed it from the code yet.

### TTS Configuration for openLuup

If you are using the plugin on openLuup, you will need to configure the `TTSBaseURL` and `TTSBasePath` state variables. The TTS services require that sound files be written somewhere in the openLuup directory tree where they can retrieved by an HTTP request from the Sonos players in your network. Set the `TTSBasePath` to the full pathname of a directory in your openLuup installation where the sound files should be written, and set `TTSBaseURL` to the full URL (e.g. `http://192.168.0.2:80`) that can be used to retrieve files written in the `TTSBasePath` directory.

## Other Configuration

TBD

## User Support

Support for this project is offered through the Vera Community Forums (Sonos category)[https://community.getvera.com/c/plugins-and-plugin-development/sonos-plugin]. Please post your questions/problems/suggestions there.

## License

This work is licensed under the Creative Commons Attribution-ShareAlike 2.0 Generic License. To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/ or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.