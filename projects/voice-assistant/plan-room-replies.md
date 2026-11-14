# Plan: spoken replies on the room speakers

**Status:** draft for review (2026-11-14). Nothing built yet. Edit freely, or tell Claude what to change.

## Why

- Every voice command already gets a spoken reply from Piper ("Playing Faint", "Bedroom fan low"), but the satellites are mic-only (INMP441, no speaker), so the reply is dropped. Only the HA phone app plays it.
- A failed command is silent: "No text recognized" looks exactly like "nothing happened" (bedroom, 2026-11-13).
- Each satellite already has a speaker next to it: the Pi's 3.5mm jack in the bedroom, xero's Bluetooth speaker in the living room.

## Goal

| When | You hear | On |
|---|---|---|
| A command worked | HA's reply ("Playing Faint - Linkin Park", "AC set to 24 degrees") | the speaker in the room of the satellite that heard you |
| Nothing recognised | a short error ("Sorry, I didn't catch that") | same |
| Music is playing in that room | the music **pauses on "Hey Jarvis"**, you give the command, hear the reply, then the music resumes | same |
| Any reply | at that room's **preset reply volume**; the speaker's own volume is put back afterwards | same |

## Design

| # | Piece | Where | What |
|---|---|---|---|
| 1 | Reply player | Pi and xero, `systemd --user` unit `voice-reply.service` | `cvlc -I telnet` (already installed on both), output to PipeWire, so it mixes with spotifyd instead of fighting it for the sound card |
| 2 | HA media players | HA, built-in **VLC telnet** integration (UI config flow, no restart) | one entity per room, e.g. `media_player.bedroom_voice_reply` (Pi), `media_player.living_room_voice_reply` (xero) |
| 3 | Satellite firmware | `esphome/voice-satellite-common.yaml` + a `reply_player` substitution per board | `on_tts_end`: play the reply URL on its room's player. `on_error`: speak the error with `tts.speak` (Piper) on the same player |
| 4 | Permission | ESPHome integration options in HA, per satellite | turn on "Allow the device to perform Home Assistant actions" (off by default) |
| 5 | Pause on wake word | HA automation `voice_music_pause`, on each `assist_satellite.*` going **listening** | if Spotify is playing **on that room's device**: pause it and remember that per room (`input_boolean.voice_paused_<room>`). No firmware needed |
| 6 | Reply script | HA script `voice_reply(room, url or message)`, called by the firmware hook in 3 | save the room speaker's volume -> set the room's preset -> play the reply -> wait until the player is idle (max 20s) -> put the volume back |
| 7 | Resume | HA automation `voice_music_resume`, on the satellite going back to **idle** | wait until `voice_reply` is not running, then resume Spotify if this room's flag is on; clear the flag |
| 8 | Presets | `input_number.voice_reply_volume_bedroom`, `..._living_room` (0-100) | the volume replies play at, per room |

Why the volume dance works: the music is paused while the reply plays, so changing the speaker's volume (`number.server_volume` on the Pi, `number.xero_speaker_volume` on xero - the existing sliders) is not heard on the music, and it is restored before the music resumes.

Flow after the change:

```
satellite --audio--> HA pipeline --> STT --> intent --> Piper reply URL
     ^                                                        |
     |                                       on_tts_end(url) on the satellite
     |                                                        v
     +---- you hear it <---- room speaker <---- VLC <---- script voice_reply
```

One command with music playing in that room:

| # | Event | What happens |
|---|---|---|
| 1 | "Hey Jarvis" | satellite -> listening; `voice_music_pause` pauses Spotify, flag on |
| 2 | you speak the command | quieter room, so speech-to-text also does better (music beside the mic caused misses on 2026-11-13) |
| 3 | HA runs the command, Piper makes the reply | |
| 4 | `on_tts_end` -> `voice_reply` | volume saved, set to the preset, reply plays, volume restored |
| 5 | satellite -> idle, `voice_reply` done | `voice_music_resume` resumes Spotify, flag off |

Commands that change the music themselves:

| Command | After it |
|---|---|
| "pause / stop the music" | stays paused: the pause command clears the flag |
| "play \<song\>" | the new song plays; resume is a no-op |
| "next / previous song" | plays the next/previous track (Spotify starts playback) |
| "music volume up/down" | needs care: the music volume is the speaker volume the reply script saves and restores, so the change must be made **after** the restore (or to the saved value) - decide in the build |
| nothing recognised / duplicate wake-up | the error reply plays (not for duplicates), then resume |

## Steps

| # | Step | Owner | Notes |
|---|---|---|---|
| 1 | Write `voice-reply.service` + install script for Pi and xero; telnet password in a gitignored `.env` | Claude | user units, no sudo; linger already on |
| 2 | Add the two VLC telnet integrations in HA; name entities, set areas (Bedroom / Living Room) | Claude | |
| 3 | Test by hand: `tts.speak` to each player with music playing and stopped | Claude | checks mixing and volume |
| 3b | `input_boolean`/`input_number` helpers, `voice_reply` script, pause and resume automations (a new package `packages/voice_replies.yaml`) | Claude | pause/resume works before the reflash (it only needs the satellites' states, which change today); the reply part needs the reflash |
| 4 | Firmware change in `voice-satellite-common.yaml`; `reply_player` per board | Claude | |
| 5 | Build and OTA-flash both satellites from the Mac (`build_on_mac.sh`, `build_on_mac.sh living`) | Pramod (Mac) or Claude via the Mac session | not on xero: heavy builds |
| 6 | Enable "allow HA actions" on both satellites in HA | Claude | |
| 7 | Live test in each room: a working command, a song, a nonsense phrase | Together | `watch_assist.sh` running |
| 8 | Docs: README, diagrams, `endpoints.toml` (telnet ports), `docs/hardware.md`, PROJECTS.md | Claude | |

## Traps known in advance

- **Duplicate wake-up:** both satellites often hear "Hey Jarvis"; HA drops one with an error. `on_error` must ignore `duplicate_wake_up_detected`, or the other room says "Sorry" every time.
- **White noise:** it plays from the Pi's speaker, through the same volume control (`number.server_volume`, PCM). The volume dance would change the white noise level mid-reply; while white noise is on, either skip the reply or leave the volume alone.
- **Pausing only the room's own device:** Spotify is one account-wide player, playing on one device at a time. Music in the living room is not paused by a bedroom command (decision below).
- **Pause latency:** Spotify takes ~0.5-1s to pause after "Hey Jarvis"; the first words of a fast command may still be under the music.
- **Stuck paused:** if HA restarts or the satellite drops mid-command, the resume never runs and the flag stays on. The pause automation should clear stale flags (older than ~1 min).
- **The mic hears the reply:** the speaker is next to the mic. The reply ends before the next wake word, and no reply sounds like "Hey Jarvis", so this should be harmless; worth watching.
- **xero's Bluetooth speaker sleeps:** when disconnected, the first reply may be lost or late (~5s reconnect). The song automation already reconnects it first (`bt_speaker_xero/connect`); replies may need the same.
- **Satellite firmware is old on the bedroom board** (2026-10-06); the reflash also brings the `on_client_connected` fix (README).

## Alternative already planned: a speaker on each satellite

`PROJECTS.md` "Voice satellites: speakers and wake word" (2026-10-15) plans a MAX98357A amp + 40-50mm speaker per board, on the ESP32's second I2S bus. Nothing bought yet.

| | Room speakers (this plan) | Speaker on the satellite |
|---|---|---|
| Cost | free | ~Rs 700-1500 for both (amp, driver, box) |
| Work | software + one reflash | buy, solder, box, reflash |
| Sound quality | good (real speakers) | small 3W driver |
| Mic hears the reply | yes (speaker beside it) | no: ESPHome mutes the mic while it plays |
| Depends on | Pi / xero up, Bluetooth connected (living room) | only the satellite |
| Confirmation tones, timers ringing | through HA, possible | built in |

The two can coexist: room speakers now, a satellite speaker later if the dependency bothers you.

## Decisions for you

| Question | Options | Default if no answer |
|---|---|---|
| Reply volume | ~~same as music / ducking~~ **preset per room, volume set before and restored after (user, 2026-11-14)** | decided |
| Pause music on wake word | ~~mix over music~~ **pause, resume after the reply (user, 2026-11-14)** | decided |
| Pause when the music is in another room | yes / only if it is the same room | only the same room |
| Preset values | bedroom __ %, living room __ % | bedroom 40%, living room 50%, then tune |
| Quiet hours | always speak / errors only at night / silent while white noise is on | silent while white noise is on |
| Which replies | **all, as HA already writes them (user, 2026-11-14)**; changed later per reply as needed | decided |
| Error wording | "Sorry, I didn't catch that" / a short tone instead of words | the sentence |
| Dashboard | a "Reply volume" slider tile per room (the presets) / none | a tile in each room's view |
| Phone app | unchanged (it plays replies itself) | unchanged |

## Your additions

- **Pause music on wake word, resume after the reply** (2026-11-14) - in Goal and Design 5-7.
- **Reply volume preset per room, set before the reply and restored after** (2026-11-14) - Design 6, 8.
- **Which replies:** all, as already built; adjust individual replies later (2026-11-14).
- 
