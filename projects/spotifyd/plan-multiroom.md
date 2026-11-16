# Plan: the same music in the bedroom and the living room, in sync

**Status:** proposed 2026-11-16, feasible; revised the same day after two independent reviews (`architecture-review`, 13 + 9 findings, all applied). To be built later (user, 2026-11-16). Needs **no ESP32 flashing** (the satellites are untouched), so it does not wait for the room-replies reflash. Where it touches `projects/voice-assistant/plan-room-replies.md`, both plans say so.

## Why

- Today each room is its own Spotify Connect device: `raspberrypi` (bedroom, Pi 3.5mm jack) and `xero` (living room, Bluetooth Apollo One). Spotify plays on **one device per account at a time**, so both rooms can't play together.
- Spotify has no multi-room of its own (a years-old request on its ideas forum). Speaker groups (Google Cast, Sonos, Alexa) work by showing Spotify **one** device and splitting the audio themselves. Jam is a shared queue across accounts, not room sync.
- Wanted: one choice, **"Everywhere"**, that plays the same song in both rooms with no audible echo.

## Feasibility (checked 2026-11-16)

| Question | Answer | Seen where |
|---|---|---|
| Free, local software that keeps rooms in sync? | **Snapcast** (GPL): one server stamps each audio chunk with a play time; each client keeps its clock matched to the server's and plays on time, typically within 1 ms of each other | snapcast docs |
| Packaged? | xero: `snapserver`/`snapclient` 0.27.0 (Ubuntu apt). Pi: `snapclient` 0.31.0 (Raspberry Pi OS apt) | `apt-cache policy` |
| Can spotifyd feed it? | yes: spotifyd 0.4.2 has a `pipe` backend (raw 44.1 kHz 16-bit stereo to a FIFO) and `--zeroconf-port` | `spotifyd --help` on xero |
| Can the Pi 3B take it? | snapclient is a few % CPU, ~10 MB RAM. Pi: load 0.24, ~50°C, ~450 MB available (347 MB in swap) | `/proc/loadavg`, `free` |
| Can the Pi play it next to spotifyd and white noise? | yes: the headphone card has 8 streams, 7 free | `aplay -l` |
| Does it need satellite flashing? | no: HA picks the room from the satellite's area (`spotify_songs.yaml`) | review |
| Can the Bluetooth speaker stay in sync? | Bluetooth adds ~150-300 ms. snapclient's PulseAudio output already asks PipeWire for the stream's latency and plays that much earlier, so part of it is covered; the rest is a `--latency` tuned by ear from 0 | unverified until step 2 |

**The catch:** play and pause on "Everywhere" take ~0.5-1s to be heard (Snapcast's buffer). The single-room devices are unchanged.

## How the sync works

1. Spotify plays to one device, "Everywhere" (a second spotifyd on xero), which writes raw audio into a FIFO instead of a speaker.
2. snapserver reads the FIFO, cuts it into chunks and stamps each "play at T", ~0.6s ahead.
3. Each snapclient keeps measuring its clock against the server's and holds each chunk until T; it nudges playback speed slightly if it drifts.
4. Bluetooth: PipeWire reports most of the speaker's delay to snapclient, which plays that much earlier; whatever is left is tuned by ear with `--latency`.

## Design

```
Spotify app / HA Spotcast
   | picks the Connect device "Everywhere"
   v
xero (all systemd --user, pramod):
  spotifyd-snapcast "Everywhere" --pipe--> /run/user/1000/snapfifo --> snapserver (waits for 192.168.1.123)
                                                                     :1704 audio  -> 192.168.1.123 + 127.0.0.1
                                                                     :1705 control -> 127.0.0.1 only (HA)
                                                                     :1780 web     -> off
                       ┌──────────────── LAN ────────────────┐                 │ loopback
                       v                                                       v
  Pi: snapclient (user unit) -> ALSA Headphones              xero: snapclient (user unit) -> PipeWire -> Bluetooth
      bedroom                                                      living room, --latency <tuned>
```

| # | Piece | Where | What |
|---|---|---|---|
| 1 | **spotifyd "Everywhere"** | xero, `systemd --user` `spotifyd-snapcast.service`, config `~/.config/spotifyd-snapcast/spotifyd.conf` (templates in this folder) | `device_name = "Everywhere"`, `backend = "pipe"`, `device = "/run/user/1000/snapfifo"`, own `cache_path` (`~/.cache/spotifyd-snapcast`), `max_cache_size = 1000000000`, own `zeroconf_port`. Unit: `BindsTo=` + `After=snapserver.service`; `ExecStartPre=test -p /run/user/1000/snapfifo` (fail loudly, never write a plain file). **Login:** a new spotifyd has no saved credentials; choose "Everywhere" once from the phone on home Wi-Fi and it saves them in `zeroconf/credentials.json` under its cache (as xero's did 2026-10-27); until then it is not listed and voice can't target it |
| 2 | **snapserver** | xero, `systemd --user` `snapserver.service` (the packaged **system** unit disabled and masked), config `snapserver.conf` in this folder | `ExecStart=snapserver -c %h/code/homelab/projects/spotifyd/snapserver.conf --server.datadir=%h/.local/share/snapserver` (explicit, or it reads the package's `/etc/snapserver.conf`: FIFO in `/tmp`, all ports on 0.0.0.0, web on). **Waits for the LAN address** (user, 2026-11-16): `ExecStartPre=/bin/sh -c 'for i in $(seq 60); do ip -4 addr show enp1s0 \| grep -q 192.168.1.123 && exit 0; sleep 1; done; exit 1'` (no `-`), `Restart=on-failure` - otherwise at boot it starts before enp1s0 has its address (seen: spotifyd's wait passed 2s early on docker/tailscale addresses), fails the LAN bind, logs it and keeps running on loopback only. `Upholds=spotifyd-snapcast.service`, so a snapserver crash and restart brings "Everywhere" back too (`BindsTo=` alone stops it and nothing starts it again). Runs as pramod, so spotifyd can open its FIFO (xero has `fs.protected_fifos=1`; a FIFO made by `_snapserver` in `/tmp` can't be opened by pramod). `--server.datadir=%h/.local/share/snapserver`. `source = pipe:///run/user/1000/snapfifo?name=Spotify&sampleformat=44100:16:2`, `buffer = 600`. `[stream] bind_to_address` 192.168.1.123 and 127.0.0.1; `[tcp] bind_to_address = 127.0.0.1`; `[http] enabled = false` |
| 3 | **snapclient, bedroom** | Pi, `systemd --user` `snapclient.service` (packaged system unit disabled) | `--host 192.168.1.123 --hostID bedroom --player alsa --soundcard default:CARD=Headphones`, `Restart=always` |
| 4 | **snapclient, living room** | xero, `systemd --user` `snapclient.service` (packaged system unit disabled; it would join as a stray third client with no PipeWire session) | `--host 127.0.0.1 --hostID living-room --player pulse --soundcard <Apollo One sink name> --latency <tuned>`, `Restart=always`, `RestartSec=10`. snapclient 0.27 does not follow a moved stream and throws if the speaker is missing at start, so the restart loop waits for the speaker, and the everywhere route restarts it after reconnecting the speaker if step 2 shows it sticking on the USB adapter |
| 5 | **HA Snapcast integration** (core, free) | HA, `127.0.0.1:1705` | **two** media players, one per client (HA 2026.11 has no group entity): per-room volume and mute. Area: bedroom / living room; a tile on each room's view |
| 6 | **Voice** | `spotify_library.py` (it **generates** `packages/spotify_songs.yaml` nightly - never hand-edit that) | "play {song} everywhere" and "play {song} in both rooms" templates; an `everywhere` speaker: Bluetooth connect, unmute clients (rule below), Spotcast to "Everywhere" |
| 7 | **White noise rule** | HA automation `everywhere_bedroom_quiet` | while `switch.white_noise` is on, the bedroom Snapcast client is **muted**; **always** unmuted when it goes off, even if it was muted by hand (user, 2026-11-16). "play X everywhere" with white noise on plays in the living room only |

- **Unchanged:** the `raspberrypi` and `xero` Connect devices, their units and voice routing.
- **Why a second spotifyd, not snapserver's librespot source:** librespot isn't installed; spotifyd is, with the house's network-wait fix and watchdogs.
- **Unmute at start:** every "play everywhere" unmutes both clients except the bedroom while white noise is on, so a mute left by a crash (snapserver saves mute in its `server.json`) never sticks. It also clears the room-replies `voice_muted_<room>` flag first (that plan's Design 9), and unmutes the room that heard the command only after its reply has finished (`voice_replying_<room>` off), so the reply never plays over the new song at the reply volume.

## Interactions with what already runs

| What | Effect | Plan |
|---|---|---|
| Spotify's one-device rule | starting "Everywhere" stops whichever room was playing, and the reverse | expected; README |
| Stale Connect devices (~weekly here, still look "active") | "Everywhere" idles most of the time, so it would be stale when asked for | **required:** `watchdog_spotify_listed.sh` gets `Everywhere` in `HOSTS` -> `systemctl --user restart spotifyd-snapcast`; `test_watchdog_spotify_listed.sh` extended. `watchdog_spotifyd.sh` takes the unit name, keeps **state per unit** (`down-since-<unit>`, `restarts-<unit>.log`), and `healthcheck.sh` (lines ~152-175) reads both; a second cron line. README's watchdog row fixed (it runs on xero too, not only the Pi). A restart can't fix a missing login - the healthcheck says so when credentials are missing |
| Healthcheck | new units could die unnoticed; snapserver can be "active" while serving loopback only | `systemctl --user is-active snapserver spotifyd-snapcast snapclient` on xero, `snapclient` on the Pi over ssh, **and** `ss -ltn 'sport = :1704' \| grep -q 192.168.1.123` |
| snapserver down | spotifyd's FIFO open would block forever: "playing", silent | `BindsTo=` stops spotifyd with it, `Upholds=` starts it again when snapserver is back; the healthcheck flags it |
| Bluetooth speaker off / dropped | living room silent, bedroom keeps playing; after a drop PipeWire may leave the client on the USB adapter | reconnect before playing (`bt_speaker_xero/connect`); client pinned to the sink by name; step 2 tests a drop |
| Volume | Spotify volume **and** each client's volume | Spotify volume is the master; per-room levels on the HA Snapcast players |
| White noise in the bedroom | would mix with the music | the bedroom client is muted while it is on (piece 7) |
| `plan-room-replies.md` | pausing "Everywhere" pauses both rooms; neither room's own device is active, so its pause step finds nothing | that plan now mutes **this room's** Snapcast client during a reply when "Everywhere" is the active device, and unmutes in `voice_resume` and the 60s safety net |
| Speech-to-Phrase | ~1095 titles x 2 new templates make its closed vocabulary bigger: longer retrain, more chances to mishear | step 4 times the retrain and checks CPU (`tools/host-stats/host_stats.py`) and existing commands |
| Marathi fallback (`stt-fallback`) | only returns "play \<song\>" | "everywhere" with a Marathi title won't work; README |
| xero heat | snapserver and a client are tiny | step 2: `host_stats.py` p95/max over 10 min playing vs idle |
| xero disk (71% used) | a second spotifyd cache | capped at 1 GB |
| Ports | 1704 home network + loopback, 1705 loopback, 1780 off; **never on tailscale0** | `endpoints.toml`; check with `ss -lntp \| grep -E ':170[45]\|:1780'` |

## Steps

| # | Step | Owner | Notes |
|---|---|---|---|
| 0 | **Install, no Spotify yet.** Pramod, from a real terminal (sudo over ssh fails silently): xero `sudo apt install --no-install-recommends snapserver snapclient && sudo systemctl disable --now snapserver snapclient && sudo systemctl mask snapserver snapclient`; Pi the same for `snapclient`. Claude: user units + configs, a test WAV into the FIFO, both rooms heard | Pramod (sudo), Claude | copy-paste commands go in the README first. Checks: `ss` shows no port on 100.70.x; the Pi's 0.31 client works with the 0.27 server - if not, the upstream `snapserver_0.31.x_amd64` deb from GitHub releases |
| 1 | **spotifyd "Everywhere"**: unit, config; **Pramod chooses "Everywhere" once from the phone on home Wi-Fi** (saves its login); check `~/.cache/spotifyd-snapcast/zeroconf/credentials.json` exists, restart, `check_spotify_listed.sh Everywhere` returns 0; note the Spotcast entity id (`media_player.everywhere_..._spotcast`) for the voice route; plays in both rooms | Claude, Pramod (phone) | `check_spotifyd_advertising.sh 8 Everywhere` and `... 8 xero`, also after a reboot: two spotifyd on one host both advertise. `systemctl --user kill -s KILL snapserver`: both back within ~10s |
| 2 | **Tune the Bluetooth delay** | Together | click track, stand where both rooms are audible, start at `--latency 0` and move in 25 ms steps until no echo; start snapclient with the speaker **off** (`journalctl --user -u snapclient`: clean retry?); a mid-play drop: does audio stay on the USB jack until a pause?; reconnect the speaker twice and listen again; turn it off and on mid-play, check where the stream lands (`wpctl status`); 30 min of play for dropouts at `buffer = 600` (else 1000); heat p95/max |
| 3 | **HA**: Snapcast integration, two players named and in their areas, tiles on the Bedroom and Living Room views (`shot_dashboard.sh`); `everywhere_bedroom_quiet` | Claude | |
| 4 | **Voice**: templates and the `everywhere` speaker in `spotify_library.py`; `sync_spotify_songs.sh`; time the Speech-to-Phrase retrain; text-test "play X", "play X everywhere", "play X in both rooms" and a few existing commands | Claude | |
| 5 | **Watchdogs and healthcheck** as in the table | Claude | with tests |
| 6 | **Docs** (below) | Claude | not done until committed |

## Docs to update

| File | What changes |
|---|---|
| `projects/spotifyd/README.md` | "Everywhere": how it works, units and configs, the latency value and how it was measured (re-check by ear after PipeWire or snapcast upgrades), the sudo install commands, traps (FIFO owner, LAN-address wait, one-device rule, stale device, first login from the phone - again if the cache is wiped, Bluetooth drop); watchdog row fixed |
| `projects/healthcheck/README.md` | the new checks |
| `projects/voice-assistant/README.md` | Pieces table rows, the phrases, the Marathi limitation |
| `architecture.puml`, `sequence_play_song.puml`, `intent_routing.puml` | the everywhere route; re-render with `render_architecture.sh` |
| `projects/endpoints/endpoints.toml` | snapserver 1704 (home network), 1705 (loopback); re-render |
| `docs/hardware.md` | xero: snapserver, spotifyd-snapcast, snapclient; Pi: snapclient |
| `projects/ha-dashboard/dashboards/home.yaml` | the two client tiles |
| `PROJECTS.md` | Log, open items |

## Rollback

- `systemctl --user disable --now spotifyd-snapcast snapserver snapclient` on xero and `snapclient` on the Pi; `sudo apt remove snapserver snapclient`. The single-room devices never depended on them.

## Decisions (user, 2026-11-16)

| Question | Answer |
|---|---|
| Connect device name | **Everywhere** |
| Voice phrases | **both**: "play X everywhere" and "play X in both rooms" |
| When | later; no flashing needed, so it does not wait for the room-replies reflash |
| White noise on during "Everywhere" | **mute the bedroom** client while white noise is on; always unmute when it goes off, even after a manual mute |
| snapserver at boot | **wait for the LAN address** (not: audio port on all interfaces incl. the tailnet) |
| Dashboard | each room's Snapcast client tile on **its own room's view** |
| Snapcast web page (1780) | **off** |

## Review findings and what was done with them (2026-11-16)

| # | Finding | Done |
|---|---|---|
| 1 | spotifyd can't open a FIFO made by `_snapserver` in `/tmp` (`protected_fifos=1`) | snapserver as a user unit; FIFO in `/run/user/1000` |
| 2 | snapserver would listen on the tailnet; 1705/1780 have no login | bound to the home network / loopback; web off; `ss` check |
| 3 | "Everywhere" would be stale when asked for | listed-watchdog and healthcheck required |
| 4 | spotifyd hangs if snapserver is down; writes a plain file into RAM if the FIFO is gone | `BindsTo=`, `test -p` before start, FIFO off `/tmp` |
| 5 | the packages start system units, a stray third client | disabled and masked in step 0 |
| 6 | room replies don't know "Everywhere"; a mute can stick | both plans: mute this room's client during a reply; unmute on resume, safety net and every "play everywhere" |
| 7 | the living-room client may stay on the USB adapter after a Bluetooth drop | pinned to the sink by name; tested in step 2 |
| 8 | the voice templates would be wiped nightly; bigger vocabulary | added in `spotify_library.py`; retrain timed; Marathi limitation noted |
| 9 | HA has no group entity | two client players |
| 10 | uncapped cache | 1 GB cap |
| 11 | server 0.27 / client 0.31 | step 0 checks; upstream deb if needed |
| 12 | Pi sudo over ssh fails silently | Pramod runs the sudo lines from a real terminal |
| 13 | docs list incomplete | "Docs to update" |

## Second review (2026-11-16) - all applied

| # | Finding | Done |
|---|---|---|
| 1 | snapserver starts before enp1s0 has its address, binds loopback only, still "active" | waits for 192.168.1.123, `Restart=on-failure`; healthcheck checks the 1704 bind |
| 2 | after a snapserver crash, "Everywhere" stays down (`BindsTo=` stops it, nothing restarts it) | `Upholds=` on snapserver; kill test in step 1 |
| 3 | no login for the new spotifyd until a phone picks it once | step 1 by phone; credentials check; README trap |
| 4 | snapclient 0.27 does not follow a moved stream, throws if the speaker is missing | `Restart=always`; two tests in step 2; restart after reconnect if needed |
| 5 | PipeWire already reports part of the Bluetooth delay | tune from 0 in 25 ms steps |
| 6 | no fixed client ids | `--hostID bedroom` / `living-room` |
| 7 | snapserver would read the package's config | explicit `-c` in `ExecStart` |
| 8 | `watchdog_spotifyd.sh` has one set of state files; README wrong about where it runs | state per unit, healthcheck reads both, README fixed |
| 9 | "play X everywhere" during a reply would unmute mid-reply | clears `voice_muted_` first; unmutes the speaking room after its reply |
