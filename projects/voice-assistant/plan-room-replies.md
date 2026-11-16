# Plan: spoken replies on the room speakers

**Status:** agreed 2026-11-14; revised 2026-11-15 after an independent review (`architecture-review` agent) and the user's decisions; revised again 2026-11-16 after a second review (15 findings) and a third (14 findings), all applied, see the end. On hold until the user says go. Nothing built yet.

## Why

- Every voice command already gets a spoken reply from Piper ("Playing Faint", "Bedroom fan low"), but the satellites are mic-only (INMP441, no speaker), so the reply is dropped. Only the HA phone app plays it.
- A failed command is silent: "No text recognized" looks exactly like "nothing happened" (bedroom, 2026-11-13).
- Each satellite already has a speaker next to it: the Pi's 3.5mm jack in the bedroom, xero's Bluetooth speaker in the living room.

## Goal

| When | You hear | On |
|---|---|---|
| A command worked | HA's reply ("Playing Faint - Linkin Park", "AC set to 24 degrees") | the speaker in the room of the satellite that heard you |
| You spoke but nothing was recognised | a **short soft tone** (not words; user, 2026-11-16); **none in the bedroom at night** | same |
| A false wake (nothing said) | nothing in most cases; a false wake with speech-like noise can still get the tone (see "The failure tone") | - |
| A command that **starts music** ("play X", "next", "resume", "play X everywhere") | the reply over the new song, at the **music's current level** (no volume change; user, 2026-11-16) | same |
| Music is playing in that room | the music **pauses on "Hey Jarvis"**, you give the command, hear the reply, then the music resumes | same |
| Music is playing in the **other** room | it **keeps playing**, untouched | - |
| White noise is on (bedroom) | bedroom: **no replies at all**; the living room still replies | - |
| Any other reply | at that room's **preset reply volume**; the speaker's own volume is put back afterwards. **Bedroom at night (22:00-07:00): night preset 40** - white noise switches itself off at 23:00-00:00, so it can't be relied on for quiet | same |

## Design

```
satellite --audio--> HA pipeline --> stt-fallback/STT --> intent --> Piper reply URL
     |
     |  firmware events (needs reflash, no "allow actions" permission):
     |  esphome.voice_reply {url} / esphome.voice_tone / esphome.voice_end (only if no reply was sent)
     v
HA automations: room = area_id(trigger.event.data.device_id)
     |
HA script voice_reply(room, url|tone) --MQTT voice_reply/<host>/play {id, ts, ...}--> voice-reply bridge on the host
     ^                                                                                  |  save volume, set preset,
     |                         <--MQTT voice_reply/<host>/done {id}--                   |  VLC plays, restore volume
HA script voice_resume(room): resume Spotify / unmute if this room's flag is on         v
                                                                                 room speaker
```

| # | Piece | Where | What |
|---|---|---|---|
| 1 | **VLC, always running** | Pi and xero, `systemd --user` unit `voice-reply-vlc.service` | `cvlc -I rc` on a local unix socket (`$XDG_RUNTIME_DIR/voice-reply.sock`), started once at boot, `--file-caching=50`. **Pi:** output straight to the card, `--aout=alsa --alsa-audio-device=default:CARD=Headphones`, like spotifyd (the card takes 8 streams at once). **xero:** PipeWire (the Bluetooth speaker only exists there) |
| 2 | **voice-reply bridge** | Pi and xero, `systemd --user` unit `voice-reply.service`, `voice_reply_mqtt.py` as a `uv run --script` (paho is not installed system-wide on the Pi), MQTT login from `~/homelab/.env.mqtt` (pattern of `volume-mqtt` / `bt_speaker_mqtt.py`) | publishes a **retained** `voice_reply/<host>/available` `online`, with an MQTT last will `offline`, plus an MQTT-discovery `binary_sensor.voice_reply_<host>` (connectivity) so HA has an entity for it; checks VLC's socket every 30s and publishes `offline` while VLC is dead. `play` is **QoS 0, clean session** (nothing to replay after a reconnect, so no clock-based drop - the Pi has no RTC). On `voice_reply/<host>/play` `{id, url or sound, volume?}`: (0) **validate**: `url` must start with `http://192.168.1.123:8123/api/tts_proxy/` and end `.mp3`, `sound` must be `tone`; else drop; **Pi:** if `systemctl --user is-active white-noise` is `active`/`activating`, drop (the ground truth; HA's switch lags and goes `unavailable`); (1)-(2) **only if `volume` is given**: save the speaker volume **to a file**, set the preset (`amixer` PCM on the Pi, `wpctl` on xero); (3) xero: make sure the Bluetooth speaker is connected, **waiting at most 5s** - else drop; (4) **download** the MP3 (0.03s) and tell VLC to play the local file (no ~1s network buffer); (5) wait until VLC reports **playing** (max 3s), then until it reports **stopped** (poll every 0.1s, max 20s); xero: 300ms more (Bluetooth lags); (6) restore the volume if it was set; (7) publish `voice_reply/<host>/done` `{id}` - **also for every drop**, so HA never waits out its timeout. Worst case ~5 + 3 + 20s, under HA's 30s wait. A second play while one runs is queued and does **not** re-save the volume. On start: if a saved-volume file is left over (crash, reboot mid-reply), restore it |
| 3 | Satellite firmware | `esphome/voice-satellite-common.yaml` | **events, not actions:** `on_tts_end` fires `esphome.voice_reply` `{url}` and sets a global `reply_sent`; `on_error` with the tone rule below fires `esphome.voice_tone` and sets `reply_sent`; `on_end` fires `esphome.voice_end` **only if `reply_sent` is false** (ESPHome runs `on_end` straight after `on_tts_end`/`on_error`, so an unconditional resume would bring the music back over the reply). `on_wake_word_detected` resets `reply_sent`. No `room` substitution: HA adds `device_id` to every `esphome.*` event |
| 4 | Event automations | `packages/voice_replies.yaml` | `esphome.voice_reply` / `voice_tone` -> `voice_reply(room, ...)`; `esphome.voice_end` -> `voice_resume(room)`; room from `area_id(trigger.event.data.device_id)`, like `voice_play_song` does. The "Allow the device to perform Home Assistant actions" option stays **off** on both boards (it would let a board call any HA service) |
| 5 | Pause on wake word | HA automation `voice_music_pause`, on each `assist_satellite.*` going **listening** | (1) `homeassistant.update_entity` on `media_player.spotify_pramod` (its state can be 30s old); (2) bedroom: remember whether white noise is on **now** (`input_boolean.voice_quiet_bedroom`; `unavailable` counts as on); (3) which device is playing = `state_attr('media_player.spotify_pramod', 'source')` (`raspberrypi`, `xero` or `Everywhere`), not the Spotcast `is_active` entities; (4) **only if the satellite is still `listening`** (a slow refresh must not set a flag after a fast command already ran): if it is **this room's device**: turn on `input_boolean.voice_paused_<room>` **first**, then pause; (5) if it is **"Everywhere"** (`projects/spotifyd/plan-multiroom.md`): don't pause (that would stop both rooms) - turn on `input_boolean.voice_muted_<room>`, then **mute this room's Snapcast client** (`snapcast_clients` map: `bedroom` -> `media_player.snapcast_client_bedroom`, `living_room` -> `media_player.snapcast_client_living_room`, ids confirmed when built) |
| 6 | Reply script | HA script `voice_reply(room, url or sound)`, **`mode: parallel`** (the two rooms must not wait on each other; each bridge queues its own) | skip if `room` is bedroom and white noise is on **at the wake word (`voice_quiet_bedroom`) or now** (`unavailable` counts as on); skip if `binary_sensor.voice_reply_<host>` is not on (no waiting); **bedroom at night (22:00-07:00, `input_datetime` helpers)**: skip the tone, and use the night preset `input_number.voice_reply_volume_bedroom_night` (40); if `input_boolean.voice_music_started_<room>` is on (set by a command that started music): send **no `volume`** (the bridge plays at the current level) and turn the flag off. Else turn on `input_boolean.voice_replying_<room>`, publish `play` with the preset, wait for `done` with that id (max 30s), turn `voice_replying_<room>` off. **Every exit, including each skip, ends with `voice_resume(room)`** |
| 7 | Resume script | HA script `voice_resume(room)`, **`mode: queued`** | does nothing while `voice_replying_<room>` is on, or while this room's `assist_satellite` is `listening` or `processing` (a new command is under way; its own reply or `voice_end` resumes later). If `voice_paused_<room>` is on **and** Spotify (`spotify_pramod`, possibly up to 10s stale - accepted) is still paused on this room's device: resume. If `voice_muted_<room>` is on: unmute this room's Snapcast client (but leave the bedroom muted while white noise is on). Clear both flags. Safe to call twice |
| 8 | Safety net | HA automation, `time_pattern` every minute **and** `homeassistant: start` (+30s) | at start: turn **every `voice_replying_*` off** (input_booleans restore their last state across a restart; defined without `initial:`). Every minute, per room: if `voice_replying_` has been on for more than 60s, turn it off; then if `voice_paused_` or `voice_muted_` has been on for more than 60s (`last_changed`): `voice_resume(room)`. A `for: 60s` state trigger would be lost on an HA restart or the 04:30 automation reload |
| 9 | Flag clearing | `voice_commands.yaml`, and the `voice_play_song` **template in `spotify_library.py`** (the generated `spotify_songs.yaml` is rewritten nightly) | "pause/stop the music", "play \<song\>", "play \<song\> everywhere / in both rooms", "next/previous song", "resume" clear the room's **`voice_paused_` only**, first, then do their media action with `continue_on_error: true`. **`voice_muted_` is never cleared by a command** - only `voice_resume` (after the reply) or the safety net, which also unmute; otherwise "next song" on Everywhere would leave the room muted for good. Commands that **start** music also turn on `voice_music_started_<room>` (Design 6). "Pause the music" skips the pause call when the player is already paused (the wake word paused it) and still answers "Paused" |
| 10 | Presets | `input_number.voice_reply_volume_bedroom` (93), `..._bedroom_night` (40), `..._living_room` (35); night window `input_datetime.voice_night_start` (22:00) / `_end` (07:00) | the volume replies play at |
| 11 | Failure tone | `tone.wav` on each host (a short soft chime, made once at install) | the bridge plays it for `sound: tone`; no TTS call |
| 12 | Health | `projects/healthcheck/healthcheck.sh` (it can't ssh to the Pi) | alerts when `binary_sensor.voice_reply_<host>` is off for more than 15 min - the bridge reports VLC's health in it, so no unit checks over ssh are needed |

Why the satellite state is **not** used to resume: HA sets a satellite back to idle only when the board reports that it finished playing the reply, and a board without a speaker never does. HA's history shows the satellites staying "responding" for hours (5349s to 55755s, 2026-11-13..15). Resume is driven by the reply script and the firmware's `voice_end` event instead.

Why a reflash is needed: HA sends the reply's audio URL only to the satellite that heard the command; automations never see it (no event). Only the firmware can forward it. The no-reflash alternative - polling HA's pipeline debug runs - adds 1-3s per reply and relies on a 10-run debug buffer, so it was rejected (2026-11-14). Pause, resume, the bridge and the presets need no reflash and can be tested before it.

Why the volume dance is safe: for most commands the music is paused while the reply plays (on "Everywhere": muted in this room, still playing in the other), so changing the speaker volume is not heard on it. **Not** for commands that start music - HA builds the reply only after the command's automation has run, so the new song is already playing: those replies skip the volume dance entirely (Design 6, user 2026-11-16); the volume is back before the music resumes, because resume waits for `voice_replying_` to clear. The voice "music volume up/down" commands change **Spotify's own volume** (spotifyd `softvol`, `voice_commands.yaml`), not the speaker volume, so they do not conflict with the save/restore. While the reply plays, the "Pi Speaker Volume" / "xero Speaker Volume" sliders jump to the preset and back - expected.

### Why VLC, and why always running

| Option | Verdict |
|---|---|
| HA's **VLC telnet integration** (the first plan) | dropped: HA checks its state only every 10s, so it cannot tell when a 1-2s reply ends - the volume could be restored mid-reply |
| A player started per reply (`cvlc --play-and-exit`, `ffplay`) | dropped: **~1.1s just to start** on the Pi 3 (measured 2026-11-15, silent output), before every reply |
| **VLC running all the time**, driven locally by the bridge | chosen: start-up paid once; installed on both hosts (3.0.20 xero, 3.0.23 Pi); decodes MP3 itself; reports when playback ends |
| `pw-play` | not chosen: the Pi's audio does not go through PipeWire |
| Speaking the text on the host (like macOS `say`, Piper on each host) | not chosen: HA already made the audio; Piper on the Pi 3 would be slow and a second install |

### The reply audio link (checked 2026-11-15)

| Question | Answer | Evidence |
|---|---|---|
| What does the satellite get in `on_tts_end`? | a **full** URL: `http://192.168.1.123:8123/api/tts_proxy/<token>.mp3` | HA's ESPHome satellite code makes the path absolute with `async_process_play_media_url` (HA 2026.11, `esphome/assist_satellite.py`, TTS_END) |
| Can the Pi fetch it? | yes, no login (the token in the path is the key): HTTP 200, 22.6kB, 0.03s | `curl` from the Pi |
| What is it? | MP3, 22.05kHz mono, ~1.6s for a short reply | `file`, `ffprobe` |

## One command, end to end (music playing in that room)

| # | Event | What happens |
|---|---|---|
| 1 | "Hey Jarvis" / "Dumbledore" | satellite -> listening; `voice_music_pause`: refresh Spotify, it is playing here -> flag on, pause |
| 2 | you speak the command | quieter room, so speech-to-text also does better |
| 3 | HA runs the command, Piper makes the reply | |
| 4 | `on_tts_end` -> event `esphome.voice_reply` -> `voice_reply` | `voice_replying_` on; MQTT play -> bridge: volume saved, preset set, VLC plays, volume restored -> done; `voice_replying_` off |
| 5 | `on_end` straight after step 4 | `reply_sent` is true -> no `voice_end` event (and `voice_resume` would wait anyway, since `voice_replying_` is on) |
| 6 | `voice_reply` -> `voice_resume` | Spotify still paused here and flag on -> resume, flag off |

Other endings:

| Run | What happens |
|---|---|
| false wake (no speech) | no tone; `on_end` -> `voice_end` -> `voice_resume` -> music back within seconds |
| spoke, not recognised | the tone (rule below), then resume |
| duplicate wake-up (the other room) | silent; that room never went "listening", so nothing paused there |
| bedroom, white noise on at the wake word **or when the reply is due** | no reply (covers "stop white noise" and "turn on white noise") |
| "pause the music" / "play \<song\>" / "next" | the command clears the flag first, so resume does nothing |
| reply bridge offline | no reply; `voice_reply` resumes at once; the healthcheck alerts after 15 min |
| bedroom, 22:00-07:00 | replies at 40, no tone |
| "play X" / "next" / "resume" | the music starts inside the command; the reply follows over it at the music's level, no volume change |
| HA restarts mid-command | the bridge still restores the volume on its own; at start the safety net clears `voice_replying_*` and resumes within ~1-2 min |

## The failure tone (replaces "Sorry", user 2026-11-16)

The second review (2026-11-16) found the old three-condition "Sorry" rule did not filter false wakes: all 8 empty runs in HA's debug buffer had `stt-vad-start` and `stt-vad-end` with 1.25-14.7s between them, including the **bedroom at 04:38 IST on 2026-11-16** (9.4s, white noise off). HA's speech detector needs ~0.7s of speech by design, and `stt-vad-end` also fires on its 15s timeout (TV, talking). So a spoken "Sorry" would have been heard at night.

Decision (user, 2026-11-16): a **short soft tone** instead of words. Play it only if **all** hold (firmware):

| # | Condition | Why |
|---|---|---|
| 1 | the error code is exactly `stt-no-text-recognized` | not `duplicate_wake_up_detected` (the other room), not timeouts or connection errors |
| 2 | `on_stt_vad_start` and `on_stt_vad_end` both fired in this run | no speech at all -> no tone |
| 3 | the time between them is **2-12s** (firmware global) | under 2s is mostly noise; ~15s is the detector's timeout (TV, people talking), not a command |

- **Calibrate before the reflash** from HA's own timings, not `stt-fallback` (IndicConformer hears nothing for English, so its log can't tell a failed command from a false wake). HA keeps only the last 10 runs per pipeline, in memory, so a small **cron poller** (every 5 min, ~0 CPU) appends each new run's `stt-vad-start` -> `stt-vad-end` gap, time and result to a file in this folder for a week. Runs carry no label (spoken vs false wake): Pramod notes his real failed tries, or the "debug recording for a day" open item supplies the audio. Set the range from that.
- **Accepted:** a false wake with speech-like noise can still get the tone in the daytime. **Not in the bedroom at night (22:00-07:00):** no tone at all - white noise switches itself off at 23:00-00:00 every night (`white_noise_night_auto_off`), so the 04:38 false wake would otherwise have played it.
- Still happens on a false wake, by design: that room's music pauses and resumes within seconds. If that bothers, a later change can pause on speech start (`on_stt_vad_start`) instead of the wake word, at the cost of the first words being under the music.

## "Stop white noise" (its own track)

The one command that must work while white noise plays (user, 2026-11-15); every other command may fail then. The review found two problems, both independent of the replies:

| Problem | Evidence | Fix |
|---|---|---|
| HA does not understand "stop white noise" | `conversation` debug, 2026-11-15: "stop white noise", "stop the white noise", "stop the noise" -> `HassLawnMowerDock`, no match. "turn off white noise", "white noise off" work | add a sentence trigger to `voice_commands.yaml`: `(stop\|turn off\|switch off) [the] white noise`, `white noise (off\|stop)`, `stop the noise` -> `switch.turn_off switch.white_noise`; restart speech-to-phrase; text-test |
| The wake word is never heard under the hiss | 77 bedroom wake-ups 2026-11-08..15, **0** while white noise was on (2-4h every night) | bench test first: white noise at night level, 10 x "Hey Jarvis" from the bed, count wake-ups (`recent_runs.py`). If it fails, the user picks: quieter white noise, moving/turning the bedroom board away from the speaker, or the physical stop button as the way to stop it |

Also found: `white-noise.service` runs `playerctl -p spotifyd pause` before it starts, but `playerctl` finds no player on the Pi, so starting white noise does **not** pause bedroom music. Nothing here relies on it; worth fixing or removing separately.

## Steps

| # | Step | Owner | Notes |
|---|---|---|---|
| 0 | **Pi audio test** (daytime): VLC to `default:CARD=Headphones` with spotifyd playing, then with white noise playing - both heard? | Claude | 5 minutes. If it fails: the fallback below (spotifyd and white noise through PipeWire) |
| 1 | "Stop white noise" sentences + text test; bench test of the wake word under white noise | Claude (sentences), Together (bench test, at night) | independent of the rest; can be done now |
| 2 | `voice_reply_mqtt.py`, `voice-reply-vlc.service`, `voice-reply.service`, install script for the Pi and xero; `tone.wav` | Claude | user units, no sudo, linger on. Test by publishing from the broker (`docker exec mosquitto mosquitto_pub ...`; xero has no `mosquitto_pub`): time from publish to first sound, volume restored, kill mid-reply -> restored on restart, two plays queued, a bad URL and a white-noise-on play dropped **with** `done`, `available` goes `offline` when VLC is killed, Bluetooth off -> dropped within 5s, xero after 10 min idle (Bluetooth clipping; add ~300ms of silence if needed). VLC's memory on the Pi (`ps -o rss -C vlc`; ~450 MB free, 343 MB in swap) |
| 3 | `packages/voice_replies.yaml`: helpers (`voice_paused_`, `voice_muted_`, `voice_replying_`, `voice_quiet_bedroom`), `voice_reply`, `voice_resume`, `voice_music_pause`, the event automations, the safety net; flag clearing in `voice_commands.yaml` and the `spotify_library.py` template, then `sync_spotify_songs.sh` | Claude | test without the reflash: wake word -> pause -> fire `esphome.voice_reply` by hand -> resume. Check: is "next song" while paused starting playback? Does pausing an already-paused player error (Pramod tests it from Developer Tools, it is a service call)? |
| 4 | Calibrate the tone's 2-12s range: a week of the `pipeline_debug` cron poller, with Pramod's notes of real failed tries | Claude, Pramod (notes) | before the firmware |
| 5 | Firmware: the three events, `reply_sent`, the tone rule | Claude | |
| 6 | Build and OTA-flash both satellites from the Mac (`build_on_mac.sh`, `build_on_mac.sh living`) | Pramod (Mac) or Claude via the Mac session | not on xero: heavy builds. Also brings the bedroom board's `on_client_connected` fix |
| 7 | Healthcheck: `binary_sensor.voice_reply_*` off for 15 min, with tests | Claude | |
| 8 | Live test in each room: a working command, a song, a nonsense phrase (tone), a false wake (no tone), music in the other room, white noise on, "turn on white noise" (no reply), "play X" (reply at the music's level), a bedroom command after 22:00 (40, no tone) | Together | `watch_assist.sh` running; note wrong-room wins |
| 9 | Docs, **part of the build** - see "Docs to update" | Claude | not done until committed |

### Fallback for step 0: Pi audio through PipeWire

Only if VLC cannot play next to spotifyd or white noise on the Pi. The user agreed to move both (2026-11-15).

| # | Change | Notes |
|---|---|---|
| 1 | spotifyd: `backend = pulseaudio`, drop `device` (`~/.config/spotifyd/spotifyd.conf` on the Pi), restart | spotifyd 0.4.2 has it; `pipewire-pulse` installed |
| 2 | White noise through PipeWire: SoX to the pulse device, or `play ... -t raw - \| pw-play` | keep the same loudness (`WHITE_NOISE_LEVEL=91`, fade steps) |
| 3 | PipeWire's sink volume fixed at 100% (today 0.69); the slider keeps setting `PCM` | otherwise replies come out quieter than the preset |
| 4 | VLC in the bridge to PipeWire instead of ALSA | |
| 4b | the bedroom snapclient (if `plan-multiroom.md` is built): `--player pulse` instead of ALSA | same reason; `plan-multiroom.md` says so too |
| 5 | Record in `projects/spotifyd/README.md`, `projects/white-noise/README.md`, `docs/hardware.md` | |

Daytime only (restarts spotifyd and white noise). Rollback: put the old lines back, restart.

## Docs to update

| File | What changes |
|---|---|
| `README.md` | Pieces table (bridge, VLC units, `voice_replies.yaml`); a "Spoken replies" section: flow, pause/resume, presets, white-noise rule, the "Sorry" rule, how to test (`mosquitto_pub`), logs; Files list; Gotchas (duplicate wake-up, wrong room, Bluetooth sleep, satellite stays "responding") |
| `architecture.puml` | step 6 no longer "dropped": satellite -> `voice_reply` -> MQTT -> bridge + VLC on the Pi / xero -> room speaker; pause/resume; reply-volume sliders; legend |
| `sequence_play_song.puml` | pause on "Hey Jarvis", the reply on the Pi's speaker, resume |
| `intent_routing.puml` | end of the flow: bedroom and white noise on -> no reply; the tone rule; resume |
| `render_architecture.sh` | re-run; commit the `.svg`/`.png` with the `.puml` |
| `projects/endpoints/endpoints.toml` | MQTT topics `voice_reply/<host>/play`, `/done` and `/available`; re-render |
| `docs/hardware.md` | `voice-reply-vlc.service` and `voice-reply.service` on the Pi and xero; satellite firmware date |
| `projects/ha-dashboard/dashboards/home.yaml` | the reply-volume tile in each room (`shot_dashboard.sh`) |
| `projects/healthcheck/README.md` | the new checks (bridge availability, units on both hosts) |
| `projects/white-noise/README.md` | PCM is shared with the reply bridge; no replies in the bedroom while white noise is on or starting |
| `PROJECTS.md` | Log, open items; Status of "Voice assistant (HA Assist): Spotify, room replies, wake word" |

## Traps known in advance

- **Duplicate wake-up:** both satellites often hear "Hey Jarvis"; HA drops one with an error. Only `stt-no-text-recognized` can play the tone, so the other room stays silent.
- **Wrong room wins:** HA keeps whichever satellite reported first, so a bedroom command can pause and reply in the living room. Accepted for now (Decisions).
- **Spotify state lag:** HA refreshes Spotify every 30s; without the refresh in Design 5, a pause from the phone in the last 30s would be "resumed" by the voice command.
- **Pause latency:** Spotify takes ~0.5-1s to pause after "Hey Jarvis"; the first words of a fast command may still be under the music.
- **The mic hears the reply:** the speaker is next to the mic. No reply sounds like "Hey Jarvis", so this should be harmless; worth watching.
- **xero's Bluetooth speaker sleeps:** the bridge reconnects it first (`bt_speaker_xero/connect`); if disconnected, PipeWire falls back to the USB adapter and the reply plays to nothing. The start of a reply may be clipped after idle - test.
- **"Everywhere" (multi-room plan):** the bridge's volume change (`amixer` PCM / `wpctl`) also hits that room's Snapcast stream - harmless because the client is muted during the reply. The mute is saved by snapserver, so a crash mid-reply could leave the room muted: the safety net and every "play everywhere" unmute. Only once `plan-multiroom.md` is built; until then the extra branch does nothing.
- **White noise shares the Pi's volume control** (PCM): `white-noise.service` sets PCM to 91 when it starts. No conflict, because the bedroom gets no reply if white noise is on at the wake word **or** when the reply is due - which covers "turn on white noise" said in the bedroom.
- **Satellite firmware is old on the bedroom board** (2026-10-06); the reflash also brings the `on_client_connected` fix (README).

## Alternative already planned: a speaker on each satellite

`PROJECTS.md` "Voice assistant (HA Assist)", Speaker plan (2026-10-15), plans a MAX98357A amp + 40-50mm speaker per board, on the ESP32's second I2S bus. Nothing bought yet.

| | Room speakers (this plan) | Speaker on the satellite |
|---|---|---|
| Cost | free | ~Rs 700-1500 for both (amp, driver, box) |
| Work | software + one reflash | buy, solder, box, reflash |
| Sound quality | good (real speakers) | small 3W driver |
| Mic hears the reply | yes (speaker beside it) | no: ESPHome mutes the mic while it plays |
| Depends on | Pi / xero up, Bluetooth connected (living room) | only the satellite |
| Satellite returns to idle by itself | no (resume is driven by scripts) | yes |

The two can coexist: room speakers now, a satellite speaker later if the dependency bothers you.

## Decisions

| Question | Decision |
|---|---|
| Reply volume | preset per room, set before the reply and restored after (user, 2026-11-14) |
| Pause music on wake word | pause, resume after the reply (user, 2026-11-14) |
| Music in the other room | keeps playing; only the same room's music pauses (user, 2026-11-14/15) |
| Preset values | bedroom 93%, living room 35%; tune later on the sliders (user, 2026-11-14) |
| White noise on | no replies in the bedroom; the living room keeps its replies (user, 2026-11-14/15). Judged at the wake word |
| Commands while white noise plays | may fail, except "stop white noise", which must work (user, 2026-11-15) |
| Wrong room wins the wake word | accepted for now: pause and reply where HA picked; observe, change later (user, 2026-11-15) |
| Which replies | all, as HA already writes them; change individual replies later (user, 2026-11-14) |
| Failed command | a **short soft tone**, not "Sorry" (user, 2026-11-16, after the second review showed false wakes pass any speech-length rule) |
| Tone rule | `stt-no-text-recognized` and 2-12s of speech; calibrated from a week of HA timings |
| "Turn on white noise" in the bedroom | no reply (user, 2026-11-16) |
| Bedroom at night (22:00-07:00) | replies at a night preset of 40, no tone (user, 2026-11-16) |
| Commands that start music | reply at the music's current level, no volume change (user, 2026-11-16) |
| Pause/resume on every false wake | fine for now; recount after the Dumbledore week (user, 2026-11-16; living room had up to 23 no-command wakes a day) |
| Firmware -> HA | `esphome.*` events, not actions; "allow actions" stays off (2026-11-16) |
| Player | VLC always running, driven by an MQTT bridge on each host (user, 2026-11-15) |
| Music on "Everywhere" | mute only this room's Snapcast client during the reply; the other room keeps playing (user, 2026-11-16) |
| Dashboard | a "Reply volume" slider tile in each room's view (user, 2026-11-14) |
| Phone app | unchanged (it plays replies itself) |
| **Open:** "Hey Jarvis" under white noise | after the bench test: quieter white noise, move the board, or the physical button |

## Review findings and what was done with them (2026-11-15)

| Finding | Done |
|---|---|
| Resume on satellite "idle" never fires | resume from `voice_reply` and the firmware's `on_end`, plus a 60s safety net |
| "Stop white noise" unrecognised; wake word never heard under the hiss | own track and step 1 |
| VLC telnet integration polls every 10s | MQTT bridge driving a VLC that is always running |
| Volume can stay at the preset | saved to a file on the host, restored on restart; queued plays don't re-save |
| False wakes would say "Sorry" | the three-condition rule; replaced 2026-11-16 by the tone (it did not filter them) |
| Spotify state up to 30s old | refresh before deciding; flag only after a confirmed pause; recheck before resume |
| Pi audio not through PipeWire | VLC straight to the card on the Pi (8 streams); step 0 tests it; PipeWire move is the fallback |
| "Music volume up" conflict | does not exist (Spotify's own volume) - removed |
| Bluetooth clipping / fallback sink | reconnect first, test after idle |
| Wrong room wins | accepted, observe |
| `playerctl` pause in white noise does nothing | noted; separate fix |
| "Everywhere" not handled (multi-room review, 2026-11-16) | mute this room's Snapcast client instead of pausing; unmute in `voice_resume`, the safety net and every "play everywhere" |

## Second review (2026-11-16) - all applied

| # | Finding | Done |
|---|---|---|
| 1 | `on_end` fires straight after `on_tts_end`, so resume would bring the music back over the reply at the preset volume | `reply_sent` in the firmware; `voice_replying_` blocks resume |
| 2 | the "Sorry" rule passed every false wake (04:38 bedroom) | a soft tone instead, 2-12s rule |
| 3 | calibrating from `stt-fallback` can't tell a failed English command from a false wake | calibrate from `pipeline_debug` timings |
| 4 | the `for: 60s` safety net is lost on HA restart / the 04:30 reload | every-minute check + at start |
| 5 | a dead bridge costs 25s of paused music, unnoticed | retained `available` + last will; skip when offline; healthcheck |
| 6 | "pause the music" pauses an already-paused player; an error leaves the flag set | clear flags first, `continue_on_error`, skip pause when paused |
| 7 | the flag was set >1s after the pause | flag first |
| 8 | the refresh in resume is mostly a no-op; Spotcast `is_active` is a different poller | use `spotify_pramod`'s `source`; staleness accepted |
| 9 | VLC's ~1s network buffer per reply | bridge downloads the MP3, VLC plays the file |
| 10 | "still playing?" could end before playback starts; Bluetooth tail | wait for playing, then stopped; +300ms on xero |
| 11 | "allow actions" lets a board call any service | `esphome.*` events, room from `device_id` |
| 12 | "turn on white noise" reply races the PCM change | quiet if white noise is on at the wake word or when the reply is due |
| 13 | one queue for both rooms; resume `single` drops calls | `voice_reply` parallel, `voice_resume` queued |
| 14 | old plays replay after a broker reconnect | `ts`, drop if older than 10s |
| 15 | flag clearing in the generated `voice_play_song` would be wiped nightly | in the `spotify_library.py` template |
| - | small gaps: MQTT login on the Pi, no `mosquitto_pub` on xero, docs list | `.env.mqtt` + `uv run --script`; `docker exec mosquitto`; healthcheck and white-noise READMEs added |

## Third review (2026-11-16) - all applied

| # | Finding | Done |
|---|---|---|
| 1 | white noise auto-offs at 23:00-00:00, so bedroom nights got replies and the tone at 93 | night window 22:00-07:00: preset 40, no tone |
| 2 | commands that start music reply over the new song; the volume dance is heard | `voice_music_started_`: no `volume`, the bridge skips the dance |
| 3 | the safety net could not clear a stuck `voice_replying_` (restored as on after a restart) | cleared after 60s and at every start |
| 4 | HA's white-noise switch lags and goes `unavailable` | the Pi bridge checks the unit itself; `unavailable` counts as on |
| 5 | a previous reply's resume during the next command | resume waits while the satellite is listening/processing |
| 6 | a slow refresh sets the pause flag after a fast command | only while the satellite is still listening |
| 7 | Bluetooth connect could outlast HA's wait | 5s cap, HA waits 30s |
| 8 | `ts` drop depends on the Pi's clock (no RTC) and guards nothing at QoS 0 | QoS 0, clean session, no `ts`; every drop publishes `done` |
| 9 | the healthcheck can't ssh to the Pi | the bridge reports VLC's health in `available`; healthcheck reads HA |
| 10 | HA keeps 10 runs, so "a week" of timings needs a poller; runs are unlabelled | cron poller + Pramod's notes |
| 11 | the bridge played any URL | only HA's `tts_proxy` URLs and `tone` |
| 12 | the white-noise skip didn't resume | every exit ends with `voice_resume` |
| 13 | the Pi PipeWire fallback didn't cover snapclient | fallback row 4b; multi-room plan says so too |
| 14 | no HA entity for `available`, no room-to-client map, endpoint list short | discovery `binary_sensor`, `snapcast_clients` map, `/available` in endpoints |
