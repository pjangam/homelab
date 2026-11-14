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
| Music is playing | the reply over the music (mixed, not stopped) | same |

## Design

| # | Piece | Where | What |
|---|---|---|---|
| 1 | Reply player | Pi and xero, `systemd --user` unit `voice-reply.service` | `cvlc -I telnet` (already installed on both), output to PipeWire, so it mixes with spotifyd instead of fighting it for the sound card |
| 2 | HA media players | HA, built-in **VLC telnet** integration (UI config flow, no restart) | one entity per room, e.g. `media_player.bedroom_voice_reply` (Pi), `media_player.living_room_voice_reply` (xero) |
| 3 | Satellite firmware | `esphome/voice-satellite-common.yaml` + a `reply_player` substitution per board | `on_tts_end`: play the reply URL on its room's player. `on_error`: speak the error with `tts.speak` (Piper) on the same player |
| 4 | Permission | ESPHome integration options in HA, per satellite | turn on "Allow the device to perform Home Assistant actions" (off by default) |

Flow after the change:

```
satellite --audio--> HA pipeline --> STT --> intent --> Piper reply URL
     ^                                                        |
     |                                       on_tts_end(url) on the satellite
     |                                                        v
     +---- you hear it <---- room speaker <---- VLC <---- media_player.play_media
```

## Steps

| # | Step | Owner | Notes |
|---|---|---|---|
| 1 | Write `voice-reply.service` + install script for Pi and xero; telnet password in a gitignored `.env` | Claude | user units, no sudo; linger already on |
| 2 | Add the two VLC telnet integrations in HA; name entities, set areas (Bedroom / Living Room) | Claude | |
| 3 | Test by hand: `tts.speak` to each player with music playing and stopped | Claude | checks mixing and volume |
| 4 | Firmware change in `voice-satellite-common.yaml`; `reply_player` per board | Claude | |
| 5 | Build and OTA-flash both satellites from the Mac (`build_on_mac.sh`, `build_on_mac.sh living`) | Pramod (Mac) or Claude via the Mac session | not on xero: heavy builds |
| 6 | Enable "allow HA actions" on both satellites in HA | Claude | |
| 7 | Live test in each room: a working command, a song, a nonsense phrase | Together | `watch_assist.sh` running |
| 8 | Docs: README, diagrams, `endpoints.toml` (telnet ports), `docs/hardware.md`, PROJECTS.md | Claude | |

## Traps known in advance

- **Duplicate wake-up:** both satellites often hear "Hey Jarvis"; HA drops one with an error. `on_error` must ignore `duplicate_wake_up_detected`, or the other room says "Sorry" every time.
- **White noise:** it plays from the Pi's speaker. A reply mixes over it at the same volume, which may be loud at night.
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
| Reply volume | same as music / fixed level per room / lower music while speaking (ducking) | fixed level per room |
| Quiet hours | always speak / errors only at night / silent while white noise is on | silent while white noise is on |
| Which replies | all / only errors and songs / only errors | all |
| Error wording | "Sorry, I didn't catch that" / a short tone instead of words | the sentence |
| Dashboard | a volume slider tile per room for replies / none | none (ask per the dashboard rule) |
| Phone app | unchanged (it plays replies itself) | unchanged |

## Your additions

- 
