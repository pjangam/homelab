# Plan: the same music in the bedroom and the living room, in sync

**Status:** proposed 2026-11-16, feasible. To be built later (user, 2026-11-16). Needs **no ESP32 flashing** (the satellites are untouched), so it does not have to wait for the room-replies reflash. Separate from `projects/voice-assistant/plan-room-replies.md`; where they touch, see "Interactions".

## Why

- Today each room is its own Spotify Connect device: `raspberrypi` (bedroom, Pi 3.5mm jack) and `xero` (living room, Bluetooth Apollo One). Spotify plays on **one device per account at a time**, so both rooms can't play together.
- Wanted: one choice, "Everywhere", that plays the same song in both rooms with no audible echo between them.

## Feasibility (checked 2026-11-16)

| Question | Answer | Seen where |
|---|---|---|
| Free, local software that keeps two rooms in sync? | **Snapcast** (GPL): one server sends timestamped audio, each client plays it on a shared clock, typically within 1 ms of each other | snapcast docs |
| Packaged? | xero: `snapserver`/`snapclient` 0.27.0 (Ubuntu apt). Pi: `snapclient` 0.31.0 (Raspberry Pi OS apt) | `apt-cache policy` |
| Can spotifyd feed it? | Yes: spotifyd 0.4.2 has a `pipe` backend (raw 44.1 kHz 16-bit stereo to a FIFO) | `spotifyd --help` on xero |
| Can the Pi 3B take it? | snapclient is a few % CPU and ~10 MB of RAM. The Pi: load 0.24, 51°C, 435 MB available | `/proc/loadavg`, `free` |
| Can the Pi play it next to spotifyd and white noise? | Yes: the headphone card takes 8 streams at once | earlier review, `aplay -l` |
| Can the Bluetooth speaker stay in sync? | Bluetooth adds a fixed delay (~150-300 ms). snapclient on xero gets a matching `--latency` offset, tuned by ear once | unverified until step 3 |

**The catch:** pressing play or pause in "Everywhere" takes ~0.5-1s to be heard (Snapcast's buffer). The single-room devices stay as they are.

## Design

```
Spotify app / HA Spotcast
   | picks the Connect device "Everywhere"
   v
xero: spotifyd #2 "Everywhere" --pipe--> /tmp/snapfifo --> snapserver (:1704 audio, :1705 control, :1780 web)
                                                              |                      |
                                                    LAN, timestamped audio    localhost/LAN
                                                              v                      v
                                       Pi: snapclient -> ALSA Headphones   xero: snapclient -> PipeWire -> Bluetooth
                                          (bedroom)                         (living room, --latency offset)
```

| # | Piece | Where | What |
|---|---|---|---|
| 1 | **spotifyd "Everywhere"** | xero, `systemd --user` unit `spotifyd-snapcast.service`, config `~/.config/spotifyd-snapcast/spotifyd.conf` | A second spotifyd: `device_name = "Everywhere"`, `backend = "pipe"`, `device = "/tmp/snapfifo"`, its own `cache_path` and `zeroconf_port`, the same `ExecStartPre` network wait as the existing unit |
| 2 | **snapserver** | xero, apt package, system unit `snapserver.service` | `/etc/snapserver.conf`: `source = pipe:///tmp/snapfifo?name=Spotify&sampleformat=44100:16:2`, `buffer = 600` |
| 3 | **snapclient, bedroom** | Pi, apt package | `--host 192.168.1.123 --player alsa --soundcard default:CARD=Headphones` |
| 4 | **snapclient, living room** | xero, `systemd --user` (needs the user's PipeWire session) | `--host 127.0.0.1 --player pulse --latency <tuned>` |
| 5 | **HA Snapcast integration** (core, free) | HA | one media player per room client + the group: per-room volume and mute for "Everywhere" |
| 6 | **Voice** | `projects/voice-assistant` | "play {song} everywhere" / "in both rooms": Spotcast to "Everywhere", reconnecting the Bluetooth speaker first (as for the living room today) |

- **Unchanged:** the `raspberrypi` and `xero` Connect devices, their units, watchdogs and voice routing. Picking a single room still works exactly as now.
- **Why a second spotifyd and not snapserver's built-in librespot source:** librespot isn't installed; spotifyd already is, with the house's network-wait fix.

## Interactions with what already runs

| What | Effect | Plan |
|---|---|---|
| Spotify's one-device rule | starting "Everywhere" stops whichever room was playing, and the reverse | expected; document it |
| spotifyd watchdogs (`watchdog_spotifyd.sh`, `watchdog_spotify_listed.sh`) | they know two devices | add "Everywhere", or leave it out deliberately and say so |
| Bluetooth speaker off or disconnected | the living-room client has nowhere to play; the bedroom keeps playing | reconnect before playing (`bt_speaker_xero/connect`), same as the voice path |
| Both rooms' volume | set by the Spotify volume **and** each snapclient's volume | Spotify volume as the master; per-room levels via the HA Snapcast players |
| White noise in the bedroom | mixes with the music on the card, like spotifyd does today | none |
| `plan-room-replies.md` "pause music in this room only" | pausing "Everywhere" pauses both rooms | for "Everywhere", **mute that room's snapclient** during the reply instead of pausing Spotify |
| xero heat | snapserver and two clients are tiny | none |
| Ports | 1704/1705/1780 new on xero, LAN only | `endpoints.toml`; not exposed on the tailnet |

## Steps

0. **Install and test with no Spotify:** apt-install snapserver and snapclient on xero, snapclient on the Pi; pipe a test WAV into the FIFO; check both rooms play. Also confirms the Pi's 0.31 client works with xero's 0.27 server (unverified).
1. **spotifyd "Everywhere"** unit and config; check it shows in the Spotify app and plays through Snapcast.
2. **Sync the Bluetooth speaker:** play a click track, stand where both rooms are audible, adjust xero's `--latency` until the echo is gone; write the value in the README.
3. **HA:** add the Snapcast integration; name the players; dashboard tiles (ask which view).
4. **Voice:** "everywhere / both rooms" sentences and the Spotcast route; update `intent_routing.puml`.
5. **Watchdogs and the healthcheck:** cover the new units (or note why not).
6. **Docs:** `projects/spotifyd/README.md` (Both rooms, the latency value, the traps), the voice-assistant README and diagrams, `endpoints.toml` (+ re-render), `docs/hardware.md` (xero and the Pi), PROJECTS.md.

## Rollback

- Stop and disable `spotifyd-snapcast`, `snapserver` and both `snapclient`s. The single-room devices never depended on them.

## Decisions (user, 2026-11-16)

| Question | Answer |
|---|---|
| Connect device name | **Everywhere** |
| Voice phrases | **both**: "play X everywhere" and "play X in both rooms" |
| When | later; flash the satellites together with room replies only if this ever needs flashing (it does not) |

## Still open

- **Dashboard:** which view gets the "Everywhere" tiles (per-room volume, mute)?
