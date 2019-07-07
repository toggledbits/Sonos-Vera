# Change Log

## Version 1.4.3 (development)

* rigpapa: Dynamic icon by mashing up static JSON on the fly using device description URL. Should eliminate need to change code when new devices are released just to get the icon right.
* rigpapa: Implement variable polling for when UPnP Event Proxy is not installed to reduce system load and network traffic; configurable: polling rates are controlled by PollDelay, default 15,60; polls every 15 seconds except when player stopped, then every 60 seconds.
* rigpapa: Attempt to incorporate, if not literally at least the intent of, all changes since 1.4 (including a somewhat published 1.4.1 and fractionally available parts of the whole).
* rigpapa: Resolve conflicts between Vera Luup's needs and openLuup's needs for TTS (problem noted below with 1.4.1).
* rigpapa: Fix ResponsiveVoiceTTS (2019).
* rigpapa: Fix small issue with MaryTTS.
* rigpapa: In-place fix for non-working JS UI elements; the JS UI needs an upgrade to the "new" (since UI5) JS API--it's still using the ancient approach, but it's still working at the moment. I suspect some upcoming firmware release will force the upgrade.

## Version 1.4.1 (in the wild)

* Released by unknown parties and modified by at least three, this version added ResponsiveVoiceTTS and also attempted some fixes/upgrades for openLuup, but the version of code I had would not allow TTS on Vera (at odds with openLuup changes).

## Version 1.4 (released)

* This is the last version released by lolodomo; original code is (here)[http://code.mios.com/trac/mios_sonos-wireless-music-systems].