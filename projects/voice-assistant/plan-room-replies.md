# Plan: spoken replies on the room speakers

**Status:** agreed 2026-11-14; revised 2026-11-15 after an independent review (`architecture-review` agent) and the user's decisions. On hold until the user says go. Nothing built yet.

## Why

- Every voice command already gets a spoken reply from Piper ("Playing Faint", "Bedroom fan low"), but the satellites are mic-only (INMP441, no speaker), so the reply is dropped. Only the HA phone app plays it.
- A failed command is silent: "No text recognized" looks exactly like "nothing happened" (bedroom, 2026-11-13).
- Each satellite already has a speaker next to it: the Pi's 3.5mm jack in the bedroom, xero's Bluetooth speaker in the living room.

## Goal

| When | You hear | On |
|---|---|---|
| A command worked | HA's reply ("Playing Faint - Linkin Park", "AC set to 24 degrees") | the speaker in the room of the satellite that heard you |
| You spoke but nothing was recognised | "Sorry, I didn't catch that" | same |
| A false wake (nothing said) | **nothing** | - |
| Music is playing in that room | the music **pauses on "Hey Jarvis"**, you give the command, hear the reply, then the music resumes | same |
| Music is playing in the **other** room | it **keeps playing**, untouched | - |
| White noise is on (bedroom) | bedroom: **no replies at all**; the living room still replies | - |
| Any reply | at that room's **preset reply volume**; the speaker's own volume is put back afterwards | same |

## Design

```
satellite --audio--> HA pipeline --> stt-fallback/STT --> intent --> Piper reply URL
     |                                                                    |
     |  on_tts_end(url) / on_error / on_end  (firmware, needs reflash)    |
     v                                                                    v
HA script voice_reply(room, url)  --MQTT voice_reply/<host>/play-->  voice-reply bridge on the host
     ^                                                                    |  save volume, set preset,
     |                         <--MQTT voice_reply/<host>/done--          |  VLC plays, restore volume
HA script voice_resume(room): resume Spotify if this room's flag is on    v
                                                                   room speaker
```

| # | Piece | Where | What |
|---|---|---|---|
| 1 | **VLC, always running** | Pi and xero, `systemd --user` unit `voice-reply-vlc.service` | `cvlc -I rc` on a local unix socket (`$XDG_RUNTIME_DIR/voice-reply.sock`), started once at boot. **Pi:** output straight to the card, `--aout=alsa --alsa-audio-device=default:CARD=Headphones`, like spotifyd (the card takes 8 streams at once). **xero:** PipeWire (the Bluetooth speaker only exists there) |
| 2 | **voice-reply bridge** | Pi and xero, `systemd --user` unit `voice-reply.service`, `voice_reply_mqtt.py` (pattern of `volume-mqtt` / `bt_speaker_mqtt.py`) | on MQTT `voice_reply/<host>/play` `{id, url or sound, volume}`: (1) save the speaker volume **to a file**; (2) set the preset (`amixer` PCM on the Pi, `wpctl` on xero); (3) xero: make sure the Bluetooth speaker is connected first; (4) tell VLC to play; (5) ask VLC "still playing?" every 0.1s, max 20s; (6) restore the volume; (7) publish `voice_reply/<host>/done` `{id}`. A second play while one runs is queued and does **not** re-save the volume. On start: if a saved-volume file is left over (crash, reboot mid-reply), restore it |
| 3 | Satellite firmware | `esphome/voice-satellite-common.yaml`, `room` substitution per board | `on_tts_end`: `homeassistant.action: script.voice_reply` with `room`, `url`. `on_error`: the "Sorry" rule below -> `script.voice_reply` with `sound: sorry`. `on_end`: `script.voice_resume` with `room` (covers runs with no reply) |
| 4 | Permission | ESPHome integration options in HA, per satellite | turn on "Allow the device to perform Home Assistant actions" (off on both today - checked 2026-11-15) |
| 5 | Pause on wake word | HA automation `voice_music_pause`, on each `assist_satellite.*` going **listening** | (1) `homeassistant.update_entity` on the Spotify player (its state can be 30s old); (2) bedroom: remember whether white noise is on **now** (`input_boolean.voice_quiet_bedroom`); (3) if Spotify is playing **on this room's device** (Spotcast `is_active`): pause it, and only if it is then paused, turn on `input_boolean.voice_paused_<room>` |
| 6 | Reply script | HA script `voice_reply(room, url or sound)`, `mode: queued` | skip if `room` is bedroom and `voice_quiet_bedroom` is on; else publish `play` with the room's preset, wait for `done` with that id (max 25s), then `voice_resume(room)` |
| 7 | Resume script | HA script `voice_resume(room)` | refresh the Spotify state; if this room's flag is on **and** Spotify is still paused on this room's device: resume. Clear the flag. Safe to call twice |
| 8 | Safety net | HA automation, a room's flag on for 60s | call `voice_resume(room)`: covers HA restarts, a satellite dropping mid-command, a lost `done` |
| 9 | Flag clearing | in `voice_commands.yaml` and `voice_play_song` | "pause/stop the music", "play \<song\>", "next/previous song" clear the room's flag, so resume does not undo them |
| 10 | Presets | `input_number.voice_reply_volume_bedroom` (93), `..._living_room` (35) | the volume replies play at |
| 11 | "Sorry" sound | `sorry.mp3` on each host, made once at install from HA's Piper ("Sorry, I didn't catch that") | the bridge plays it for `sound: sorry`; no TTS call at error time |

Why the satellite state is **not** used to resume: HA sets a satellite back to idle only when the board reports that it finished playing the reply, and a board without a speaker never does. HA's history shows the satellites staying "responding" for hours (5349s to 55755s, 2026-11-13..15). Resume is driven by the reply script and the firmware's `on_end` instead.

Why a reflash is needed: HA sends the reply's audio URL only to the satellite that heard the command; automations never see it (no event). Only the firmware can forward it. The no-reflash alternative - polling HA's pipeline debug runs - adds 1-3s per reply and relies on a 10-run debug buffer, so it was rejected (2026-11-14). Pause, resume, the bridge and the presets need no reflash and can be tested before it.

Why the volume dance is safe: the music is paused while the reply plays, so changing the speaker volume is not heard on it; the volume is back before the music resumes. The voice "music volume up/down" commands change **Spotify's own volume** (spotifyd `softvol`, `voice_commands.yaml`), not the speaker volume, so they do not conflict with the save/restore. While the reply plays, the "Pi Speaker Volume" / "xero Speaker Volume" sliders jump to the preset and back - expected.

### Why VLC, and why always running

| Option | Verdict |
|---|---|
| HA's **VLC telnet integration** (the first plan) | dropped: HA checks its state only every 10s, so it cannot tell when a 1-2s reply ends - the volume could be restored mid-reply |
| A player started per reply (`cvlc --play-and-exit`, `ffplay`) | dropped: **~1.1s just to start** on the Pi 3 (measured 2026-11-15, silent output), before every reply |
| **VLC running all the time**, driven locally by the bridge | chosen: start-up paid once; installed on both hosts; fetches the URL and decodes MP3 itself; reports when playback ends |
| `pw-play` | not chosen: cannot fetch a URL; the Pi's audio does not go through PipeWire |
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
| 1 | "Hey Jarvis" | satellite -> listening; `voice_music_pause`: refresh Spotify, it is playing here -> pause, flag on |
| 2 | you speak the command | quieter room, so speech-to-text also does better |
| 3 | HA runs the command, Piper makes the reply | |
| 4 | `on_tts_end` -> `voice_reply` | MQTT play -> bridge: volume saved, preset set, VLC plays, volume restored -> done |
| 5 | `voice_reply` -> `voice_resume` | Spotify still paused here and flag on -> resume, flag off |
| 6 | `on_end` -> `voice_resume` | flag already off -> nothing |

Other endings:

| Run | What happens |
|---|---|
| false wake (no speech) | `on_error` stays silent; `on_end` -> `voice_resume` -> music back within seconds |
| spoke, not recognised | "Sorry" (rule below), then resume |
| duplicate wake-up (the other room) | silent; resume if that room had paused |
| bedroom, white noise on at the wake word | no reply, including the "white noise off" after "stop white noise" |
| "pause the music" / "play \<song\>" / "next" | the command clears the flag, so resume does nothing |
| HA restarts mid-command | the bridge still restores the volume on its own; the safety net resumes after 60s |

## No "Sorry" on false wakes

The review (2026-11-15) found ~6-10 wake-ups per room per day that end in "No text recognized" - mostly false wakes with nothing said after. Each would say "Sorry" out loud, at night too (user: fix this).

Say "Sorry, I didn't catch that" only if **all** of these hold (firmware):

| # | Condition | Why |
|---|---|---|
| 1 | the error code is exactly `stt-no-text-recognized` | not `duplicate_wake_up_detected` (the other room), not timeouts or connection errors |
| 2 | HA's voice detector saw speech start **and** end in this run (`on_stt_vad_start` and `on_stt_vad_end` both fired; the firmware already has `on_stt_vad_end`) | a false wake usually has no speech after it |
| 3 | the speech lasted at least **1.0s** (time between the two, in a firmware global) | a cough or a door is shorter than a command. Start value: real failed commands on 2026-11-15 had 3-6s of speech |

Calibrate before the reflash: `stt-fallback` logs every empty run with its audio length and what IndicConformer heard (`docker logs stt-fallback`). After a week, compare runs where it heard words (you spoke) with runs where it heard nothing (false wake) and set the threshold between them; aim for no "Sorry" on nights with nobody speaking.

Still happens on a false wake, by design: that room's music pauses and resumes within seconds. If that bothers, a later change can pause on speech start (`on_stt_vad_start`) instead of the wake word, at the cost of the first words being under the music.

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
| 2 | `voice_reply_mqtt.py`, `voice-reply-vlc.service`, `voice-reply.service`, install script for the Pi and xero; `sorry.mp3` | Claude | user units, no sudo, linger on. Test with `mosquitto_pub`: timing, volume restored, kill mid-reply -> restored on restart, two plays queued, xero after 10 min idle (Bluetooth clipping; add ~300ms of silence if needed) |
| 3 | `packages/voice_replies.yaml`: helpers, `voice_reply`, `voice_resume`, `voice_music_pause`, the safety net; flag clearing in `voice_commands.yaml` / `voice_play_song` | Claude | test without the reflash: wake word -> pause -> call `voice_reply` by hand -> resume. Check: is "next song" while paused starting playback? |
| 4 | Calibrate the "Sorry" threshold from a week of `stt-fallback` logs | Claude | before the firmware |
| 5 | Firmware: `on_tts_end`, `on_error` rule, `on_end`, `room` per board | Claude | |
| 6 | Build and OTA-flash both satellites from the Mac (`build_on_mac.sh`, `build_on_mac.sh living`) | Pramod (Mac) or Claude via the Mac session | not on xero: heavy builds. Also brings the bedroom board's `on_client_connected` fix |
| 7 | Enable "allow HA actions" on both satellites | Claude | |
| 8 | Live test in each room: a working command, a song, a nonsense phrase, a false wake, music in the other room, white noise on | Together | `watch_assist.sh` running; note wrong-room wins |
| 9 | Docs, **part of the build** - see "Docs to update" | Claude | not done until committed |

### Fallback for step 0: Pi audio through PipeWire

Only if VLC cannot play next to spotifyd or white noise on the Pi. The user agreed to move both (2026-11-15).

| # | Change | Notes |
|---|---|---|
| 1 | spotifyd: `backend = pulseaudio`, drop `device` (`~/.config/spotifyd/spotifyd.conf` on the Pi), restart | spotifyd 0.4.2 has it; `pipewire-pulse` installed |
| 2 | White noise through PipeWire: SoX to the pulse device, or `play ... -t raw - \| pw-play` | keep the same loudness (`WHITE_NOISE_LEVEL=91`, fade steps) |
| 3 | PipeWire's sink volume fixed at 100% (today 0.69); the slider keeps setting `PCM` | otherwise replies come out quieter than the preset |
| 4 | VLC in the bridge to PipeWire instead of ALSA | |
| 5 | Record in `projects/spotifyd/README.md`, `projects/white-noise/README.md`, `docs/hardware.md` | |

Daytime only (restarts spotifyd and white noise). Rollback: put the old lines back, restart.

## Docs to update

| File | What changes |
|---|---|
| `README.md` | Pieces table (bridge, VLC units, `voice_replies.yaml`); a "Spoken replies" section: flow, pause/resume, presets, white-noise rule, the "Sorry" rule, how to test (`mosquitto_pub`), logs; Files list; Gotchas (duplicate wake-up, wrong room, Bluetooth sleep, satellite stays "responding") |
| `architecture.puml` | step 6 no longer "dropped": satellite -> `voice_reply` -> MQTT -> bridge + VLC on the Pi / xero -> room speaker; pause/resume; reply-volume sliders; legend |
| `sequence_play_song.puml` | pause on "Hey Jarvis", the reply on the Pi's speaker, resume |
| `intent_routing.puml` | end of the flow: bedroom and white noise on -> no reply; "Sorry" rule; resume |
| `render_architecture.sh` | re-run; commit the `.svg`/`.png` with the `.puml` |
| `projects/endpoints/endpoints.toml` | MQTT topics `voice_reply/<host>/play` and `/done`; re-render |
| `docs/hardware.md` | `voice-reply-vlc.service` and `voice-reply.service` on the Pi and xero; satellite firmware date |
| `projects/ha-dashboard/dashboards/home.yaml` | the reply-volume tile in each room (`shot_dashboard.sh`) |
| `PROJECTS.md` | Log, open items; Status of "Voice assistant (HA Assist): Spotify, room replies, wake word" |

## Traps known in advance

- **Duplicate wake-up:** both satellites often hear "Hey Jarvis"; HA drops one with an error. Only `stt-no-text-recognized` can say "Sorry", so the other room stays silent.
- **Wrong room wins:** HA keeps whichever satellite reported first, so a bedroom command can pause and reply in the living room. Accepted for now (Decisions).
- **Spotify state lag:** HA refreshes Spotify every 30s; without the refresh in Design 5, a pause from the phone in the last 30s would be "resumed" by the voice command.
- **Pause latency:** Spotify takes ~0.5-1s to pause after "Hey Jarvis"; the first words of a fast command may still be under the music.
- **The mic hears the reply:** the speaker is next to the mic. No reply sounds like "Hey Jarvis", so this should be harmless; worth watching.
- **xero's Bluetooth speaker sleeps:** the bridge reconnects it first (`bt_speaker_xero/connect`); if disconnected, PipeWire falls back to the USB adapter and the reply plays to nothing. The start of a reply may be clipped after idle - test.
- **White noise shares the Pi's volume control** (PCM): no conflict, because the bedroom gets no replies while white noise is on.
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
| Error wording | "Sorry, I didn't catch that" (user, 2026-11-14) |
| "Sorry" on false wakes | must not happen: only when you clearly spoke (user, 2026-11-15) |
| Player | VLC always running, driven by an MQTT bridge on each host (user, 2026-11-15) |
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
| False wakes would say "Sorry" | the three-condition rule |
| Spotify state up to 30s old | refresh before deciding; flag only after a confirmed pause; recheck before resume |
| Pi audio not through PipeWire | VLC straight to the card on the Pi (8 streams); step 0 tests it; PipeWire move is the fallback |
| "Music volume up" conflict | does not exist (Spotify's own volume) - removed |
| Bluetooth clipping / fallback sink | reconnect first, test after idle |
| Wrong room wins | accepted, observe |
| `playerctl` pause in white noise does nothing | noted; separate fix |
