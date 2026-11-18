# xero's speaker over Bluetooth instead of AUX
**Status:** Done

**Why:** xero's speaker (Portronics Apollo One) kept going silent while spotifyd "played", and the fix each time was reseating its AUX cable by hand. The user wanted no buttons or cables. The speaker boots into Bluetooth mode, and AUX comes back only with its M button or a replug.
**Outcome:** 2026-11-14 - xero plays to it over its own Bluetooth instead. Details and traps: `projects/spotifyd/README.md`.

#### What changed
| Piece | What |
|---|---|
| Pairing | Apollo One `0D:67:1F:80:92:22` paired and trusted on xero's `hci0`; PipeWire default sink |
| Reconnect (cron, every minute) | `projects/spotifyd/bt_speaker_reconnect.sh` |
| Reconnect on voice "play" | `bt-speaker-mqtt.service` on xero + a step in `spotify_library.py`'s generated automation (MQTT `bt_speaker_xero/connect` -> `/state`) |
| HA slider "xero Speaker Volume" | `volume-mqtt` drop-in now `VOLUME_DEVICE=pipewire` (follows the default sink, not USB card 1) |

#### Log
- 2026-11-14: a tone on the AUX line was not heard: the speaker was in Bluetooth mode, and signal does not switch it. Found it advertising over Bluetooth from xero, paired it; tone and Spotify (via spotcast) played on it. Volume 18%.
- 2026-11-14: tested by disconnecting on purpose: the script reconnects in ~4s and restores the default sink; a typed "play sasa to sasa ki kapoos jasa" reconnected and played in ~5s (20s before replacing `bluetoothctl --timeout` with polling). HA slider reads the Bluetooth volume (18).
- 2026-11-18: the speaker "kept disconnecting": WirePlumber 0.4's `with-logind` dropped Bluetooth audio at every ssh logout and brought it back at the next login (the 19:00 voice "play" started music before the speaker was back). Turned it off: `projects/spotifyd/install_wireplumber_bt.sh`. The user plans to replace the Apollo One with a wired speaker soon.
