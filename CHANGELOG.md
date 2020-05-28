# Change Log

**NOTAM (NOtice To All Music-lovers):** ResponsiveVoice is no longer supported. They removed the public URL/endpoint that was being used to create speech audio files by the plugin. The suggested alternative to RV is the Microsoft Azure Speech Service, which produces clear speech audio from a large variety of voices, and offers a usable/meaningful free tier level that is likely sufficient for most users.

## Version 2.1 (development, 20148)

* New action `urn:micasaverde-com:serviceId:Sonos1/AcquireGroupControl` to become group controller of a zone's current group.
* New action `urn:micasaverde-com:serviceId:Sonos1/DelegateGroupControl` to delegate group controller authority to another zone (`Zone` parameter must contain a single zone UUID or zone name).
* A device-specific TTS/Alert volume can be specified by placing the volume (0-100) in the `TTSVolume` state variable of any device. If the value has a leading +/-, it is a relative volume adjustment from the current volume, whatever it may be. All of this only works if no volume is passed to the `Say` or `Alert` actions.
* Azure TTS now works for Vera3/Lite. It is necessary to switch the "Requestor" in the TTS settings to "curl," and set "SSL Peer Verification" to "off". Note that these settings are **not secure**, and introduce the (likely remote but not zero) risk of undetected man-in-the-middle and other attacks on the connection/requests, so **you make these settings changes entirely at your own risk**. If cannot accept this risk, your only alternative is to upgrade your Vera to a modern unit that supports the higher levels of encryption and peer verification required, or not use Azure TTS.
* Support extra fields for MaryTTS, in case there's more that needs to be passed on the URL that isn't preconfigured/canned.
* Remove bogus 1.x defaults from TTS initialization, masking real defaults now in effect.
* Soft-wrap text input for TTS tab on Sonos device.
* Improve player display and queue contents accuracy.
* Hotfix 20147-01: Fix for service metadata not being correctly reloaded (affects streaming/radio playback).

## Version 2.0 (released)

**DEPRECATION ANNOUNCEMENT:** The "Language" parameter on `Say` actions is now deprecated; it will be removed in a future release. Since language is closely coupled to engine configuration, it isn't reasonable to allow language selection at the action.

**SUPPORT FOR VERA 3/LITE:** The Sonos plugin 2.0 generally runs well on the Vera3 and Lite, but the SSL library on the device is unable to meet the encryption requirements of the Microsoft Azure services for TTS. As a result, MARY is the only supported TTS for these platforms. This is a limitation of the firmware on these systems, and since they are now off maintenance with Vera/eZLO, it is not expected that these will receive any further updates. Your only option is to move up to the newer Edge/Plus/Secure models.

**OPENLUUP USERS:** If you plan on using TTS on openLuup, please see the README file for the latest instructions on special setup requirements.

* The plugin has been converted to parent-child, which is more memory efficient. It also has the benefit of discovering and configuring all zones once the first zone has been created. Existing standalone zone devices from prior versions of the plugin are converted in-place to children, so their Vera/Luup device IDs *do not change*, thus preserving scenes, Lua, Reactor conditions and activities, etc.
* Since the zone topology, favorites, and saved queues are common to all devices in the system, it isn't necessary for every known zone device to subscribe to their updates and store them individually. These are now stored on the master device. At startup, two zones (the two lowest-numbered zone/child devices, by default) are given the "master role". In this role, they will subscribe to topology and content updates, and updates the SonosSystem master device. All zones used the shared data from the master device. This considerably reduces network traffic and load on the Vera. If the system contains a mix of portable and permanently-installed devices, it may be desirable to specify which zones are preferred as masters; setting `DesignatedMaster` to 1 on these devices will increase their preference. The system chooses two masters at startup for redundancy (if more than two zones are DesignatedMaster=1, only two will actually become masters--which two are selected is not deterministic).
* Satellite devices, those that are slaved to a zone players as surround speakers, subwoofer, etc., are not controllable themselves, so they are hidden on the Vera dashboard.
* `Say` and `Alert` actions now support `Repeat` parameter (value 1-255; default 1) to repeat speech or alert, respectively.
* `Say` and `Alert` actions now support `UnMute` parameter (boolean; default 1) to force unmuting of muted zones before playback.
* TTS now supports Azure (which is very nice quality, BTW); the old Microsoft TTS has been removed. The TTS module has been refactored to be a good bit more modular.
* Handling of TTS engine settings has been modified to conform to the new TTS module interface. This means, among other things, that you are only asked for settings for the TTS engine you are using, and the UI dependencies between the plugin core and the TTS module have been greatly reduced. This makes the addition of future TTS engines easier (no core changes required).
* The TTS cache is automatically pruned of speech audio files older than 90 days by default. This can be modified by setting `TTSCacheMaxAge` on the Sonos master device to the desired maximum age in days. If set to 0, cache cleanup is disabled--you'll need to do it manually. This is handy if you always use fixed strings and want to ensure they are cached and playable during Internet outages.
* The TTS cache can be enabled and disabled system-wide through the use of the `UseTTSCache` boolean on the Sonos master device. The default is 1 (cache enabled). When disabled, the `UseCache` parameter on `Say` actions has no effect.
* Discovery is now run automatically at startup if there are no Sonos devices configured. All Sonos zones found will be created automatically. Combined with the new parent-child structure, this makes initial setup of the system almost completely automated.
* On Luup startup, the zone group configuration is used to inventory the system, and any newly-added zones are created. This further minimizes any requirement on the user to configure new devices.
* When the UPnP proxy is used (always recommended), playing TTS will be more responsive because the status updates from the proxy can be applied to the TTS/alert queue processing. This means that you may also omit the `Duration` parameter on `Alert` actions (as long as the alert sound is less than 30 seconds in length).
* Startup waits for the UPnP Proxy to come up, when installed.
* Fixed an error in the timing of renewal subscriptions. The UPnP module would schedule renewals for exactly the expiration time, which then meant that the subscription expiration at the Sonos device and the renewal operation of the plugin were in a race, and if the plugin lost, updates just stopped happening on the zone devices. The UPnP module now schedules renewals for 80% of the subscription length or length - 60 seconds, whichever is longer, to give the plugin ample time to do the renewals before they expire. In addition, the plugin will now retry (once) if renewals fail. If all renewals fail, a hard check of the proxy is launched.

## Version 1.5 (legacy; not supported)

* Implement TTS caching to reduce traffic to and dependence on remote services. The performance of remote services can vary greatly; for example, ResponsiveVoice has been seen taking up to 30 seconds to respond with an audio result. Since most users likely speak a small number of fixed phrases repeatedly, caching removes repeated remote queries for the same data and allows immediate replay of the previously-played phrase.
* TTS now plays a chime prior to announcement.
* Revamped state variable initialization so that defaults are not written to state, but handled on the fly. This allows future changes in default values to be done without user intervention. Particularly important for TTS, where, for example, the URL used for a remote service may change for all users.
* Clean up of code and logging to a more maintainable form. I find having lots of implementation code in the XML implementation file to be really inconvenient and unnecessarily troublesome. The plugin core now lives in its own module.
* Support for openLuup with the addition of the `LocalIP`, `TTSBasePath` and `TTSBaseURL` variables. For openLuup, the `localIP` variable should be set to the IP address of the openLuup system.
* Support `TTSBasePath` and `TTSBaseURL` variables to move TTS sound files and cache to a directory of the user's chosing. The directory must be accessible by the Sonos system(s) via HTTP. The `TTSBasePath` must contain an absolute filesystem path that refers to the directory accessible at `TTSBaseURL`.
* Update icon handling and various other tweaks for 7.30, which restricts certain directories previously used to read-only. Vera 7.30 and up will now use `/www/sonos`, and below will use the standard `/www/cmh/skins/default/icons` directory accessed via a relative URL to be compatible/consistent with many prior versions. OpenLuup will continue to use the install directory.

## Version 1.4.3 (legacy; not supported)

* rigpapa: Dynamic icon by mashing up static JSON on the fly using device description URL. Should eliminate need to change code when new devices are released just to get the icon right.
* rigpapa: Implement variable polling for when UPnP Event Proxy is not installed to reduce system load and network traffic; configurable: polling rates are controlled by PollDelay, default 15,60; polls every 15 seconds except when player stopped, then every 60 seconds.
* rigpapa: Attempt to incorporate, if not literally at least the intent of, all changes since 1.4 (including a somewhat published 1.4.1 and fractionally available parts of the whole).
* rigpapa: Resolve conflicts between Vera Luup's needs and openLuup's needs for TTS (problem noted below with 1.4.1).
* rigpapa: Fix ResponsiveVoiceTTS (2019).
* rigpapa: Fix small issue with MaryTTS.
* rigpapa: In-place fix for non-working JS UI elements; the JS UI needs an upgrade to the "new" (since UI5) JS API--it's still using the ancient approach, but it's still working at the moment. I suspect some upcoming firmware release will force the upgrade.

## Version 1.4.1 (in the wild; not supported)

* Released by unknown parties and modified by at least three, this version added ResponsiveVoiceTTS and also attempted some fixes/upgrades for openLuup, but the version of code I had would not allow TTS on Vera (at odds with openLuup changes).

## Version 1.4 (in the wild; not supported)

* This is the last version released by lolodomo; original code is (here)[http://code.mios.com/trac/mios_sonos-wireless-music-systems].
