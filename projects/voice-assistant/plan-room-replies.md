# Plan: spoken replies on the room speakers

**Status:** **live since 2026-11-18** - both boards flashed, replies on, living room tested by the user (replies, "Done" for same-room commands, play button). Left: step 0 and the bedroom night level by ear (together, an evening), the bedroom button (part to buy). Found while testing: HA's same-room acknowledge chime (swapped for "Done." in the bridge), xero's Bluetooth drops and clipped starts (WirePlumber fix + lead-in). "Everywhere" branches left out (multi-room paused). Agreed 2026-11-14, nine reviews (tables at the end).

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
| A command that **starts music** and succeeds ("play X", "play X everywhere", "next", "previous", "resume") | **no spoken reply** - the music is the answer (user, 2026-11-18); the text still shows in the phone app. A failure ("X is not in your liked songs", a Spotify error) is spoken as usual | same |
| Music on **"Everywhere"** audible in that room | **this room's Snapcast player is muted** from the wake word until the reply ends; the other room keeps playing (user, 2026-11-17) | same |
| Music is playing in that room | the music **pauses on "Hey Jarvis"**, you give the command, hear the reply, then the music resumes | same |
| Music is playing in the **other** room | it **keeps playing**, untouched | - |
| White noise is on (bedroom) | bedroom: **no replies at all**, and white noise is never paused or muted for anything; the living room still replies | - |
| Any other reply | at that room's **preset reply volume**; the speaker's own volume is put back afterwards. **Bedroom at night (22:00-07:00): a quiet night preset**, set by ear at build time (ninth review: 40 on the Pi is ~-60 dB, inaudible) - white noise switches itself off at 23:00-02:00, so it can't be relied on for quiet | same |

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
HA script voice_resume(room): resume Spotify / re-apply the Snapcast mute rule         v
                                                                                 room speaker
```

| # | Piece | Where | What |
|---|---|---|---|
| 1 | **VLC, always running** | Pi and xero, `systemd --user` unit `voice-reply-vlc.service` | `cvlc -I rc` on a local unix socket (`$XDG_RUNTIME_DIR/voice-reply.sock`), started once at boot, `--file-caching=50`. **Pi:** output straight to the card, `--aout=alsa --alsa-audio-device=default:CARD=Headphones`, like spotifyd (the card takes 8 streams at once). **xero:** PipeWire (the Bluetooth speaker only exists there) |
| 2 | **voice-reply bridge** | Pi and xero, `systemd --user` unit `voice-reply.service`, `voice_reply_mqtt.py` as a `uv run --script` (paho is not installed system-wide on the Pi), MQTT login from the repo's `.env.mqtt` (Pi `~/homelab/.env.mqtt`, xero `~/code/homelab/.env.mqtt`; the unit calls `%h/.local/bin/uv`, which is not on the Pi's PATH) (pattern of `volume-mqtt` / `bt_speaker_mqtt.py`) | publishes a **retained** `voice_reply/<host>/available` (`online` only if VLC's socket answers), with an MQTT last will `offline`, plus an MQTT-discovery `binary_sensor.voice_reply_<host>` (connectivity) so HA has an entity for it - **both republished in `on_connect`, with the result of the VLC check, not a fixed `online`**, so a broker restart or reconnect can't leave HA with the last will's `offline`; checks VLC's socket every 30s and publishes `offline` while VLC is dead. `play` is **QoS 0, clean session** (nothing to replay after a reconnect, so no clock-based drop - the Pi has no RTC). On `voice_reply/<host>/play` `{id, url or sound, volume?}`: (0) **validate**: `url` must start with `http://192.168.1.123:8123/api/tts_proxy/` and end `.mp3`, `sound` must be `tone`; else drop; **Pi:** if `systemctl --user is-active white-noise` is `active`, `activating` or `deactivating`, drop (the ground truth; HA's switch lags and goes `unavailable`; `deactivating` is the fade-out, PCM still changing); **queue age:** a play that waited more than 10s in the bridge's own queue (monotonic clock, not wall time) is dropped - HA's 30s wait would have given up on it; (1) xero: **if the Bluetooth speaker is not connected, or the default sink is not it (`wpctl inspect @DEFAULT_AUDIO_SINK@` `node.name` starting with `bluez_output.0D_67_1F_80_92_22`; the live name ends `.1`), drop the reply at once** - no reconnect, no waiting (user, 2026-11-18: Bluetooth errors are ignored); checked **before** the volume, since otherwise `wpctl` and VLC would use the USB adapter; (2)-(3) **only if `volume` is given**: save the speaker volume **and its mute state to a file**, set the preset **with `unmute`** (a hand-muted jack would otherwise play nothing) (`amixer -c Headphones sset PCM <n>% unmute` on the Pi - the default card there is HDMI, which has no PCM control; `wpctl` on xero); (4) **download** the MP3 (0.03s) and tell VLC to play the local file (no ~1s network buffer); (5) wait until VLC reports **playing** (max 3s), then until it reports **stopped** (poll every 0.1s, max 20s); xero: 300ms more (Bluetooth lags); (6) restore the volume and mute state if they were set - **Pi: if `white-noise` is active, activating or deactivating by then, set PCM to its `WHITE_NOISE_LEVEL` (91, from `systemctl --user show white-noise -p Environment`) instead** (white noise's own `amixer` may have run before the preset and would otherwise be left at the reply level); (7) publish `voice_reply/<host>/done` `{id}` - **also for every drop**, so HA never waits out its timeout, and **never sooner than 1.0s after the `play` arrived** (sleep the difference): HA's MQTT client subscribes to `done` 0.1-0.5s after the script asks (`SUBSCRIBE_COOLDOWN`), so a fast drop would be missed and HA would wait 30s - the same race `bt_speaker_mqtt.py` already sleeps around. Worst case ~3 + 20s, under HA's 30s wait. A second play while one runs is queued and does **not** re-save the volume. When the restore is skipped for white noise, the saved-volume file is **deleted**. On start: if a saved-volume file is left over (crash, reboot mid-reply), restore it **only if `white-noise` is inactive**, else delete it (a Pi reboot at night must not overwrite white noise's 91) |
| 3 | Satellite firmware | `esphome/voice-satellite-common.yaml` | **events, not actions:** `on_tts_end` fires `esphome.voice_reply` `{url}` and sets a global `reply_sent`; `on_error` with the tone rule below fires `esphome.voice_tone` and sets `reply_sent`; `on_end` fires `esphome.voice_end` **only if `reply_sent` is false** (ESPHome runs `on_end` straight after `on_tts_end`/`on_error`, so an unconditional resume would bring the music back over the reply). `on_wake_word_detected` resets `reply_sent`. No `room` substitution: HA adds `device_id` to every `esphome.*` event |
| 4 | Event automations | `packages/voice_replies.yaml` | `esphome.voice_reply` / `voice_tone` -> `voice_reply(room, ...)`; `esphome.voice_end` -> `voice_resume(room)`; room from `area_id(trigger.event.data.device_id)`, like `voice_play_song` does. The "Allow the device to perform Home Assistant actions" option stays **off** on both boards (it would let a board call any HA service) |
| 5 | Pause on wake word | HA automation `voice_music_pause`, on each `assist_satellite.*` going **listening**, `mode: queued` (one automation, two satellites) | (0) **does nothing while `input_boolean.voice_replies_enabled` is off** - off until the reflash (step 6), since before it nothing fires the resume and every wake word, false ones too, would mean 60-120s of silence (user, 2026-11-17); turn off `voice_music_started_<room>` (a leftover from a run that never replied) - **only while this satellite is still `listening`**, so a queued run behind the other room's can't wipe a flag this room's command already set; (1) `homeassistant.update_entity` on `media_player.spotify_pramod` (its state can be 30s old); (2) bedroom: remember whether white noise is on **now** (`input_boolean.voice_quiet_bedroom`; `unavailable` counts as on); (3) which device is playing: the **local record** `input_text.voice_music_device` + `input_datetime.voice_music_started_at` (set by `voice_start_music` and `play_room_playlist` on success, cleared by "pause the music") when it is newer than `spotify_pramod`'s `last_updated` - HA skips a second refresh within 10s and Spotcast never refreshes, so after "play X" a quick second command would see idle (ninth review) - else `state_attr('media_player.spotify_pramod', 'source')` (`raspberrypi`, `xero` or `Everywhere`); not the Spotcast `is_active` entities; (4) **only if the satellite is still `listening`** (a slow refresh must not set a flag after a fast command already ran): **this room's device** playing -> turn on `input_boolean.voice_paused_<room>` **first**, then pause; **"Everywhere"** playing -> don't pause (it would stop both rooms): turn on `input_boolean.voice_muted_<room>`, then start `snapcast_apply_mute` with `script.turn_on` (fire-and-forget: a hung snapserver must not stall this queued automation) (owned by `plan-multiroom.md` piece 7: a room is muted while its `voice_muted_` is on, so the other room keeps playing and the bedroom's night/white-noise rule is never undone by a reply) |
| 6 | Reply script | HA script `voice_reply(room, url or sound)`, **`mode: parallel`** (the two rooms must not wait on each other; each bridge queues its own) | skip if `room` is bedroom and white noise is on **at the wake word (`voice_quiet_bedroom`) or now** (`unavailable` counts as on); skip if `binary_sensor.voice_reply_<host>` is not on (no waiting); **bedroom at night** (`input_datetime.night_quiet_start` 22:00 / `_end` 07:00, shared with `plan-multiroom.md`; the window crosses midnight: `now >= start or now < end`): skip the tone, and use the night preset `input_number.voice_reply_volume_bedroom_night` (set by ear at build time, ~75-82). **Skip** (no sound) if `voice_music_started_<room>` is on: a command just started music **audible in this room**, and that needs no reply (user, 2026-11-18); turn the flag off. **Skip** if `input_boolean.voice_replies_enabled` is off - checked here, not as an automation condition, so even a gated run ends with `voice_resume`. Any music in the room is already silent here: paused or muted at the wake word (Design 5). Then turn on `input_boolean.voice_replying_<room>`, publish `play` **always with the preset**, wait for `done` with that id (max 30s), turn `voice_replying_<room>` off. **Every exit, including each skip, ends with `voice_resume(room)`** |
| 7 | Resume script | HA script `voice_resume(room)`, **`mode: queued`** | does nothing while `voice_replying_<room>` is on, or while this room's `assist_satellite` is `listening` or `processing` (a new command is under way; its own reply or `voice_end` resumes later). If `voice_paused_<room>` is on **and** Spotify (`spotify_pramod`, possibly up to 10s stale - accepted) is still paused on this room's device: resume. If `voice_muted_<room>` is on: turn it off and start `snapcast_apply_mute` with `script.turn_on` (fire-and-forget, so a hung snapserver can't hold this script; the rule unmutes the bedroom only if `everywhere_bedroom_wanted` is on and the night/white-noise rule allows). Clear `voice_paused_<room>` and `voice_music_started_<room>`. Safe to call twice |
| 8 | Safety net | HA automation, `time_pattern` every minute **and** `homeassistant: start` (+30s) | at start: turn **every `voice_replying_*` and `voice_music_started_*` off** (input_booleans restore their last state across a restart; defined without `initial:`). Every minute, per room: if `voice_replying_` has been on for more than 60s, turn it off; then if `voice_paused_` or `voice_muted_` has been on for more than 60s (`last_changed`): `voice_resume(room)`. A `for: 60s` state trigger would be lost on an HA restart or the 04:30 automation reload |
| 9 | Music commands and short forms | `voice_commands.yaml`, and the `voice_play_song` **template in `spotify_library.py`** (the generated `spotify_songs.yaml` is rewritten nightly; `plan-multiroom.md` piece 6 adds its everywhere branch to the same template) | **Commands that start music** ("play \<song\>" when found, "play \<song\> everywhere", "next/previous song", "resume the music") call a small script `voice_start_music` (`mode: parallel`) that does the media call and ends with `stop` + `response_variable` `{ok: true}`; the command calls it with `continue_on_error: true` and `response_variable: started`, tested as `(started | default({})).get('ok', false)` (HA catches a failing call inside the automation and would otherwise answer a plain "Done" - seventh review, `conversation/default_agent.py`; e.g. a stale Spotcast player; a few non-HA errors - spotcast's `LowRatioError`, raw spotipy/requests errors - still abort and answer "Done": README Gotchas). **If ok:** clear the room's `voice_paused_` - except after "next/previous", which keep it on, because librespot loads the next track paused when the player was paused (`spirc.rs` `handle_next`), so `voice_resume` must resume it; if `voice_paused_` was **off** and the player was already `paused` before the call (paused earlier by hand or from the phone), `voice_start_music` follows the skip with `media_player.media_play`; turn on `voice_music_started_<room>` **only if the new music is audible in this room** (this room's device; or Everywhere and the room is allowed on it: living room always, bedroom per `binary_sensor.everywhere_bedroom_allowed` from `plan-multiroom.md` - night window, white noise, "wanted", and deliberately **not** `voice_muted_`, which is on during the speaker's own command; before multi-room is built, Everywhere never appears) and answer "Playing ..." (not spoken then); not audible here ("play X everywhere" from the bedroom at night) -> answer "Playing in the living room", spoken at the night preset (user, 2026-11-18). **Else** answer "Couldn't play ..." and leave the flags alone, so the paused music comes back. "Play \<unknown title\>" answers "... is not in your liked songs". **Room guard** (user, 2026-11-18) for "resume/next/previous" **and** "pause the music" and "music volume up/down": act only if the playing device (the local record when newer, else `source`, as in Design 5) is this room's device, or `Everywhere` with this room allowed on it (same test); otherwise they answer "The music is in the bedroom/living room", "The music is on {{ source }}" (a laptop or phone) or "Nothing is playing" (idle, no `source`), and do nothing; they never act on `raspberrypi` while white noise is on. **Bedroom + white noise on** (user, 2026-11-18): "play X" is refused too - nothing plays, "White noise is on" (phone-app text only; the bedroom gets no replies then), like "play X everywhere". **Phone app** (no satellite, `area` empty): no flag steps, no room guard - acts on `spotify_pramod` as today. **"Pause the music"** (after the guard): clear `voice_paused_` and the local record, pause with `continue_on_error: true`, skipping the call when already paused; answers "Paused". **Short forms are multi-word only** - they already exist in `voice_spotify_control`; the work is reworking that automation with the guard and flags ("pause the music", "next song", "skip song", "previous song", "resume the music") until a day of debug recordings from **both** boards (the existing open item; none saved since 2026-10-09, and `replay_recordings.sh` has the bedroom device id hard-coded) shows the bare words ("pause", "next", "resume") don't turn up in false wakes; no bare "play" or "stop" ever (night false wakes; "stop" is the nearest word to "stop white noise"). **Spotify is hidden from Assist** (user, 2026-11-18): `media_player.spotify_pramod` and the Spotcast players unexposed (`homeassistant/expose_entity`), so HA's built-in media commands - a bare "resume" picks the bedroom's player regardless of room or white noise - can't reach it; our sentences cover pause, resume, next, previous and volume |
| 10 | Presets and gate | `input_number.voice_reply_volume_bedroom` (93), `..._bedroom_night` (40), `..._living_room` (35); night window `input_datetime.night_quiet_start` (22:00) / `_end` (07:00), shared with `plan-multiroom.md` (whichever plan is built first creates them); `input_boolean.voice_replies_enabled` | the volume replies play at. The gate turns off the pause on the wake word **and** the replies (a skip inside `voice_reply`, which still ends with `voice_resume`; `voice_end`, resume and the safety net keep running, so nothing is left paused); a tile on the dashboard |
| 11 | Failure tone | `tone.wav` on each host (a short soft chime, made once at install) | the bridge plays it for `sound: tone`; no TTS call |
| 12 | Health | `projects/healthcheck/healthcheck.sh` (cron on xero) | alerts when `binary_sensor.voice_reply_<host>` is off for more than 15 min - the bridge reports VLC's health in it, so no per-unit checks are needed (the healthcheck could ssh to the Pi, as `check_pi_spotifyd.sh` does, but doesn't have to) |

Why the satellite state is **not** used to resume: HA sets a satellite back to idle only when the board reports that it finished playing the reply, and a board without a speaker never does. HA's history shows the satellites staying "responding" for hours (5349s to 55755s, 2026-11-13..15). Resume is driven by the reply script and the firmware's `voice_end` event instead.

Why a reflash is needed: HA sends the reply's audio URL only to the satellite that heard the command; automations never see it (no event). Only the firmware can forward it. The no-reflash alternative - polling HA's pipeline debug runs - adds 1-3s per reply and relies on a 10-run debug buffer, so it was rejected (2026-11-14). Pause, resume, the bridge and the presets need no reflash and can be tested before it.

Why the volume dance is safe: the music in that room is always silent while a reply plays (user, 2026-11-17) - paused at the wake word, or muted on "Everywhere". Commands that start music get no reply (user, 2026-11-18), so a reply never plays over a new song. The volume is back before the music resumes, because resume waits for `voice_replying_` to clear. The voice "music volume up/down" commands change **Spotify's own volume** (spotifyd `softvol`, `voice_commands.yaml`), not the speaker volume, so they do not conflict with the save/restore. While the reply plays, the "Pi Speaker Volume" / "xero Speaker Volume" sliders jump to the preset and back - expected.

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
| "pause" / "play \<song\>" (found) / "next" | the command clears the flag, so resume does nothing |
| "play \<unknown title\>" | flag left on: "... is not in your liked songs", then the music resumes |
| "Everywhere" playing | this room's Snapcast player muted from the wake word to the end of the reply; the other room keeps playing |
| reply bridge offline | no reply; `voice_reply` resumes at once; the healthcheck alerts after 15 min |
| bedroom, 22:00-07:00 | replies at the night preset, no tone |
| "play X" / "next" / "resume" (success) | the music starts inside the command; **no spoken reply**; `voice_resume` clears the flags (Everywhere: unmutes this room via the rule) |
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
- **Accepted:** a false wake with speech-like noise can still get the tone in the daytime. **Not in the bedroom at night (22:00-07:00):** no tone at all - white noise switches itself off at 23:00-02:00 every night (`white_noise_night_auto_off`: 23:00, 23:30, 00:00, 00:30, 02:00), so the 04:38 false wake would otherwise have played it.
- Still happens on a false wake, by design: that room's music pauses and resumes within seconds. If that bothers, a later change can pause on speech start (`on_stt_vad_start`) instead of the wake word, at the cost of the first words being under the music.

## Physical play button (added 2026-11-17, same reflash)

Wanted (user, 2026-11-17): a push button on **each** satellite that plays the playlist in **that room**, like the dashboard's "Play Bedroom Track" tile does for the bedroom.

| Piece | Where | What |
|---|---|---|
| Button | each satellite board, **GPIO23** to **GND** (free on both: the boards use 2, 4, 25, 32, 33; GPIO27 is kept for the satellite-speaker plan's amplifier BCLK); not a strapping pin, internal pull-up, no resistor | a 12mm momentary panel button in the satellite's box (to buy, `PROJECTS.md` parts block); wiring diagram from the `circuit-diagram` agent at build time |
| Firmware | `voice-satellite-common.yaml` | `binary_sensor` `gpio` GPIO23, `INPUT_PULLUP`, `inverted`, `delayed_on: 50ms` (debounce), named "Play button"; `on_press` fires `esphome.play_button` (an event: no "allow actions" needed, `device_id` comes with it, same as the reply events) |
| HA automations | `projects/voice-assistant/packages/play_button.yaml` (its own file, so the replies' rollback leaves the button working) `play_button_bedroom`, `play_button_living_room` | **one per board** (condition on `device_id`; one shared `mode: single` would drop a bedroom press while a living-room press waits up to 25s for Bluetooth): on `esphome.play_button` -> `script.play_room_playlist(room)`; `mode: single`, `max_exceeded: silent`, 3s delay at the end, so a bounce or a double press is one play. The script itself is `mode: parallel`, so the two rooms never drop each other's press |
| HA script | `play_room_playlist(room)` in `packages/play_button.yaml` (tracked in git; `HOMEASSISTANT_CONFIG/` is gitignored); `play_bedroom_track` stays in `scripts.yaml` as a one-line wrapper calling it with `room: bedroom` (its callers: the tiles in `home.yaml`, `test_white_noise_pauses_spotify.sh`, `tools/ha-diag/`); `room` is required, missing -> stop with an error | **always starts the playlist** from the top (user, 2026-11-17), even if music plays: `data: {offset: 0}` in `spotcast.play_media` (inside `data:` - spotcast rejects it as a top-level field; without it Spotify may start anywhere when shuffle is on). Bedroom: `spotcast.play_media` playlist `63uNCHuVgqNqXOUPoujY5Q` on `media_player.raspberrypi_..._spotcast`. Living room: the Bluetooth connect step the voice `living_room` speaker already uses (`spotify_library.py`), then the same playlist on `media_player.xero_..._spotcast` - **Bluetooth errors are ignored** (user, 2026-11-18): no check, no notification. Playlist URI in one place (the script's variables). After a successful play: set the local record (`voice_music_device`, `voice_music_started_at`); and **only if this room's satellite went `listening` less than 30s ago and is still `listening`, `processing` or `responding`** (a voice command is under way - `responding` alone sticks for hours on a board without a speaker): clear `voice_paused_<room>` and set `voice_music_started_<room>`, so that command's reply doesn't play over the new music; otherwise touch no flags (a stale flag would swallow the next unrelated reply) |
| Dashboard | `home.yaml` | the bedroom tile now calls `play_room_playlist`; a matching tile on the Living Room view |

- **Before the reflash:** the script and automation can go live and be tested by firing `esphome.play_button` from Developer Tools with each board's `device_id`.
- **Bedroom at night or with white noise on:** the button **plays anyway**, at the current volume, like the dashboard tile (user, 2026-11-17, asked about a bumped button and the speaker at 91 after white noise). Room replies stay silent then (Design 6).
- **Not tied to `voice_replies_enabled`:** the button works from the moment the board is flashed.
- **Wrong-room risk:** none; the board's own area decides the room.
- **Mic:** the button is on another pin and core; it does not touch the audio stream.

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
| 1 | "Stop white noise" sentences + text test (including "stop the noise" against the existing "stop the song"; drop "stop the noise" if they get confused); bench test of the wake word under white noise | Claude (sentences), Together (bench test, at night) | independent of the rest; can be done now |
| 2 | `voice_reply_mqtt.py`, `voice-reply-vlc.service`, `voice-reply.service`, install script for the Pi and xero; `tone.wav` | Claude | user units, no sudo, linger on. Test by publishing from the broker (`docker exec mosquitto mosquitto_pub ...`; xero has no `mosquitto_pub`): time from publish to first sound, volume restored, kill mid-reply -> restored on restart, two plays queued, a bad URL and a white-noise-on play dropped **with** `done` (HA's `voice_replying_` off within 2s, not 30s), `available` goes `offline` when VLC is killed, Bluetooth off -> dropped at once with `done`, xero after 10 min idle (Bluetooth clipping; add ~300ms of silence if needed). VLC's memory on the Pi (`ps -o rss -C vlc`; ~450 MB free, 343 MB in swap) |
| 3 | `packages/voice_replies.yaml`: helpers (`voice_replies_enabled` **off**, `voice_music_device`, `voice_music_started_at`, `voice_paused_`, `voice_replying_`, `voice_music_started_`, `voice_quiet_bedroom`; no `initial:`, so **right after the first load** set them once - 93 / the night value chosen by ear / 35 with `input_number.set_value`, 22:00/07:00 with `input_datetime.set_datetime` - and check them in the test: unset, the presets would be silent and the night window 00:00-00:00 "always night"). **Shared helpers** - `input_datetime.night_quiet_start/_end`, `input_boolean.voice_muted_bedroom/_living_room` - live in one package, `projects/voice-assistant/packages/night_quiet.yaml` (the folder HA mounts as `packages/`), which neither plan's rollback removes (a second definition in another package is a duplicate-key error), `voice_reply`, `voice_resume`, `voice_music_pause`, the event automations, the safety net; flag clearing and the short-command sentences in `voice_commands.yaml` and the `spotify_library.py` template, then `sync_spotify_songs.sh` | Claude | goes live with the gate **off**: only the short commands and flag clearing act. Test by turning the gate on for a few minutes: wake word -> pause -> fire `esphome.voice_reply` by hand -> resume; then off again. **Assist exposure:** list exposed `media_player.*` (`homeassistant/expose_entity/list`) and expect none - HA exposes new entities automatically (`expose_new` is on), so every new media player is unexposed when created, and this check runs again in step 8. "Play X" then "next song" within 5s acts on the new song (local record). Text-test "pause the music", "next song", "resume the music" with the player paused ("next" while paused stays paused - librespot - so the resume must bring it back); "play \<nonsense\>" leaves the flag on; `voice_start_music` pointed at a bad Spotcast id answers "Couldn't play" (Pramod tests from Developer Tools whether the error reaches `continue_on_error` with `started` undefined); "resume the music" from the living room with the bedroom paused answers "The music is in the bedroom"; does pausing an already-paused player error? |
| 4 | Calibrate the tone's 2-12s range: a week of the `pipeline_debug` cron poller, with Pramod's notes of real failed tries | Claude, Pramod (notes) | before the firmware |
| 5 | Firmware: the three events, `reply_sent`, the tone rule, the play button (GPIO23 -> `esphome.play_button`); HA: `play_room_playlist`, `play_button` automation, living-room tile | Claude | button bought and wired first (Pramod, with the `circuit-diagram` guide); HA side tested by firing the event by hand |
| 6 | Build and OTA-flash both satellites from the Mac (`build_on_mac.sh`, `build_on_mac.sh living`); then turn `input_boolean.voice_replies_enabled` **on** | Pramod (Mac) or Claude via the Mac session | not on xero: heavy builds. Also brings the bedroom board's `on_client_connected` fix. Gate on only once **both** boards send `voice_end` |
| 7 | Healthcheck: `binary_sensor.voice_reply_*` off for 15 min, with tests | Claude | |
| 8 | Live test in each room: the play button (playlist starts in that room at its first track, also with shuffle on; a double press plays once; living room with the speaker asleep; a bedroom press during a living-room press), a working command, a song, a nonsense phrase (tone), a false wake (no tone), music in the other room, white noise on, "turn on white noise" (no reply), "play X" (music starts, no reply), "play \<nonsense title\>" (spoken "not in your liked songs", music resumes), Everywhere playing (only this room muted for the reply; bedroom at night stays muted), a bedroom command after 22:00 (night preset, no tone); "play X" then "next song" within 5s; no `media_player.*` exposed to Assist | Together | `watch_assist.sh` running; note wrong-room wins |
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

## Rollback

1. `input_boolean.voice_replies_enabled` off (the pause and the replies stop at once); turn every `voice_muted_*` and `voice_paused_*` off and run `snapcast_apply_mute` once, so nothing is left muted or paused.
2. Pi and xero: stop and start `voice-reply` once (it restores any saved volume), then `systemctl --user disable --now voice-reply voice-reply-vlc`; remove the units.
3. Delete `packages/voice_replies.yaml`; take `voice_start_music`, the room guard and the short forms out of `voice_commands.yaml` and the `spotify_library.py` template; `sync_spotify_songs.sh`. `packages/night_quiet.yaml` stays (the multi-room plan may use it).
4. Firmware stays: its events go nowhere and are harmless. The play button keeps working: `play_button.yaml` and `play_room_playlist` don't depend on the rest. Re-expose Spotify to Assist only if the built-in commands are wanted back.

## Docs to update

| File | What changes |
|---|---|
| `README.md` | Pieces table (bridge, VLC units, `voice_replies.yaml`); a "Spoken replies" section: flow, pause/resume, presets, white-noise rule, the tone rule, how to test (`mosquitto_pub`), logs; Files list; Gotchas (duplicate wake-up, wrong room, Bluetooth sleep, satellite stays "responding") |
| `architecture.puml` | step 6 no longer "dropped": satellite -> `voice_reply` -> MQTT -> bridge + VLC on the Pi / xero -> room speaker; pause/resume; reply-volume sliders; legend |
| `sequence_play_song.puml` | pause on "Hey Jarvis", the reply on the Pi's speaker, resume |
| `intent_routing.puml` | end of the flow: bedroom and white noise on -> no reply; the tone rule; resume |
| `render_architecture.sh` | re-run; commit the `.svg`/`.png` with the `.puml` |
| `projects/endpoints/endpoints.toml` | MQTT topics `voice_reply/<host>/play`, `/done` and `/available`; re-render |
| `docs/hardware.md` | `voice-reply-vlc.service` and `voice-reply.service` on the Pi and xero; satellite firmware date; play button on GPIO23 of each board |
| `wiring.html`, `wiring.svg` (`make_wiring_svg.py`) | the button on GPIO23 (from `circuit-diagram`) |
| `projects/voice-assistant/README.md` | which files in `packages/` each plan owns (`voice_replies.yaml`, `play_button.yaml`, shared `night_quiet.yaml`; multi-room's `everywhere.yaml`) |
| `projects/ha-dashboard/dashboards/home.yaml` | the reply-volume tile in each room, the bedroom night-preset slider, the "Voice replies" switch (`voice_replies_enabled`), the Living Room play tile (`shot_dashboard.sh`) |
| `HOMEASSISTANT_CONFIG/scripts.yaml` | `play_bedroom_track` as a wrapper of `play_room_playlist` |
| `docs/hardware.md`, README | the tone-calibration `pipeline_debug` poller cron line on xero while it runs (one week; removed after) |
| `projects/healthcheck/README.md` | the new checks (bridge availability, units on both hosts) |
| `projects/white-noise/README.md` | PCM is shared with the reply bridge; no replies in the bedroom while white noise is on or starting |
| `PROJECTS.md` | Log, open items; Status of "Voice assistant (HA Assist): Spotify, room replies, wake word" |

## Traps known in advance

- **Duplicate wake-up:** both satellites often hear "Hey Jarvis"; HA drops one with an error. Only `stt-no-text-recognized` can play the tone, so the other room stays silent.
- **Wrong room wins:** HA keeps whichever satellite reported first, so a bedroom command can pause and reply in the living room. Accepted for now (Decisions).
- **Spotify state lag:** HA refreshes Spotify every 30s; without the refresh in Design 5, a pause from the phone in the last 30s would be "resumed" by the voice command.
- **Pause latency:** Spotify takes ~0.5-1s to pause after "Hey Jarvis"; the first words of a fast command may still be under the music.
- **The mic hears the reply:** the speaker is next to the mic. No reply sounds like "Hey Jarvis", so this should be harmless; worth watching.
- **xero's Bluetooth speaker sleeps:** the bridge does **not** reconnect it; not connected -> the reply is dropped at once (user, 2026-11-18). The start of a reply may be clipped after idle - test.
- **"Everywhere" (multi-room plan):** this room's Snapcast player is muted from the wake word to the end of the reply (`voice_muted_`), through `plan-multiroom.md`'s single mute rule, so the bedroom's night/white-noise mute is never undone by a reply and a mute left by a crash is re-evaluated by the safety net. Only once `plan-multiroom.md` is built; until then the extra branch does nothing.
- **No reply for music that started:** the phone app still shows the text; on a satellite, the music starting is the only confirmation (user, 2026-11-18).
- **Before the reflash** `voice_replies_enabled` stays off, so the wake word does not pause anything (Design 5).
- **White noise shares the Pi's volume control** (PCM): `white-noise.service` sets PCM to 91 when it starts. No conflict, because the bedroom gets no reply if white noise is on at the wake word **or** when the reply is due - which covers "turn on white noise" said in the bedroom.
- **Satellite firmware is old on the bedroom board** (2026-10-06); the reflash also brings the `on_client_connected` fix (README).

## Alternative already planned: a speaker on each satellite

`tracker/voice-assistant.md` "Voice assistant (HA Assist)", Speaker plan (2026-10-15), plans a MAX98357A amp + 40-50mm speaker per board, on the ESP32's second I2S bus. Nothing bought yet.

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
| Bedroom at night (22:00-07:00) | replies at a night preset, no tone (user, 2026-11-16); the value set by ear at build time, ~75-82, not 40 (user, 2026-11-18) |
| Commands that start music | **no spoken reply when they succeed**; failures are spoken (user, 2026-11-18; replaced pause-for-the-reply from 2026-11-17 and reply-at-the-music's-level from 2026-11-16) |
| Pause/resume on every false wake | fine for now; recount after the Dumbledore week (user, 2026-11-16; living room had up to 23 no-command wakes a day) |
| Firmware -> HA | `esphome.*` events, not actions; "allow actions" stays off (2026-11-16) |
| Player | VLC always running, driven by an MQTT bridge on each host (user, 2026-11-15) |
| Music on "Everywhere" | mute this room's Snapcast player from the wake word to the end of the reply, through the multi-room plan's one mute rule (user, 2026-11-17: music is silenced for every reply; white noise never is) |
| Short commands ("pause", "next", "resume") | multi-word sentences of our own; no bare "play" or "stop"; Spotify hidden from Assist (user, 2026-11-17/18) |
| Pause on wake word before the reflash | off (`voice_replies_enabled`) until both boards are flashed (user, 2026-11-17) |
| Dashboard | a "Reply volume" slider tile in each room's view (user, 2026-11-14) |
| Phone app | unchanged (it plays replies itself) |
| Physical play button | one per satellite on GPIO23, plays the playlist in that room; every press starts it from the top; bedroom plays at night too; to buy (user, 2026-11-17) |
| Bluetooth speaker not connected | drop the living-room reply; no reconnect wait, no notifications - Bluetooth errors are ignored (user, 2026-11-18) |
| Spotify in HA's built-in voice commands | hidden; only our room-aware sentences (user, 2026-11-18) |
| "Play X" in the bedroom with white noise on | refused, like "play X everywhere" (user, 2026-11-18) |
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
| Bluetooth clipping / fallback sink | reconnect first, test after idle (reconnect superseded 2026-11-18: dropped instead) |
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
| 7 | Bluetooth connect could outlast HA's wait | 5s cap, HA waits 30s (superseded 2026-11-18: no wait, drop when not connected) |
| 8 | `ts` drop depends on the Pi's clock (no RTC) and guards nothing at QoS 0 | QoS 0, clean session, no `ts`; every drop publishes `done` |
| 9 | the healthcheck can't ssh to the Pi | the bridge reports VLC's health in `available`; healthcheck reads HA |
| 10 | HA keeps 10 runs, so "a week" of timings needs a poller; runs are unlabelled | cron poller + Pramod's notes |
| 11 | the bridge played any URL | only HA's `tts_proxy` URLs and `tone` |
| 12 | the white-noise skip didn't resume | every exit ends with `voice_resume` |
| 13 | the Pi PipeWire fallback didn't cover snapclient | fallback row 4b; multi-room plan says so too |
| 14 | no HA entity for `available`, no room-to-client map, endpoint list short | discovery `binary_sensor`, `snapcast_clients` map, `/available` in endpoints |

## Fourth review (2026-11-17) - all applied

| # | Finding | Done |
|---|---|---|
| 1 | short "pause/next/resume" go to HA's built-ins, which need a **playing** player - the wake word has just paused it | our own sentences for the short forms (Design 9) |
| 2 | built in step order, pause-on-wake-word is live a week+ before the reflash, with nothing to resume it | `voice_replies_enabled` off until step 6 |
| 3 | a night bedroom wake word could unmute "Everywhere" there | first: no mute on Everywhere; then (fifth round, user) the mute is back but goes through the multi-room plan's one desired-state rule, which never unmutes the bedroom at night |
| 4 | "play \<unknown\>" cleared the pause flag first, so the music stayed paused | flag cleared only in the branch that starts a song |
| 5 | `voice_music_started_` can stick (no reply came), so the next night reply plays at 91 | cleared at the wake word, in resume and at start |
| 6 | xero set the volume before Bluetooth was connected (USB adapter is default) | connect and wait for the sink first |
| 7 | volume dance while music is still audible (failed pause, Everywhere) | fifth round: the music is silenced before every reply |
| 8 | `softvol`: "music's level" replies are louder than the music | moot since the fifth round: replies always at the preset over silence |
| 9 | the two plans disagreed on "play everywhere" unmute | resolved by #3; the multi-room plan owns all Snapcast mutes |
| 10 | white noise `deactivating` (fade-out) not dropped | dropped too |
| 11 | after a broker reconnect HA kept the last will's `offline` | republish `available` and discovery in `on_connect` |
| 12 | a queued play could outlive HA's 30s wait | dropped after 10s in the bridge's queue |
| 13 | stale text (auto-off 23:00-00:00; "can't ssh to the Pi") | 23:00-02:00; healthcheck row corrected |
| 14 | (multi-room) the "Everywhere" config template must not hold a username/password | in `plan-multiroom.md` |

## Fifth review (2026-11-17) - all applied

User decision the same day: **the music is silenced for every reply** (paused, or this room muted on Everywhere), **white noise never is** (the bedroom just gets no reply).

| # | Finding | Done |
|---|---|---|
| 1 | `voice_music_started_` was set for a room that couldn't hear the new music (everywhere at night, "next" on the other room's device) -> bedroom reply at 91 (superseded by the sixth review, then back in the seventh as "only if audible") | set only when the new music is audible in that room; and the reply now silences the music and always uses the preset |
| 2 | HA subscribes to `done` 0.1-0.5s after publishing; a fast drop is missed and HA waits 30s | bridge never answers sooner than 1.0s; step-2 test |
| 3 | GPIO27 is the satellite-speaker plan's BCLK | button on GPIO23 |
| 4 | bedroom button at night / with white noise | asked: **plays anyway** (user) |
| 5 | without `offset` a shuffled playlist starts anywhere | `offset: 0`; test with shuffle on |
| 6 | removing `play_bedroom_track` breaks a test, two diag tools and a tile | kept as a wrapper |
| 7 | living-room button played to the USB adapter if Bluetooth failed | stop unless `connected` |
| 8 | one `mode: single` automation dropped the other room's press | one automation per board |
| 9 | a bare "play" is new to Speech-to-Phrase; night false wakes could start music | no bare "play"; replay saved false wakes first |
| 10 | the gate only stopped the pause, not the replies | gate also stops `voice_reply`/`voice_tone`; dashboard tile |
| 11 | xero: sink listed is not yet the default sink | wait for the default sink |
| 12 | `on_connect` published `online` with VLC dead | publishes the VLC check result |
| 13 | Everywhere rule didn't require "playing"; Snapcast per-room volume made replies louder | moot: music silenced, preset always |
| 14 | "Sorry" left in docs; midnight-crossing window; no cross-reference to piece 6 | tone; `now >= start or now < end`; shared night helpers; cross-reference |

## Sixth review (2026-11-18) - all applied

User decision the same day: **a command that starts music and succeeds gets no spoken reply** - the music is the answer. That removed findings 1 and 4 outright.

| # | Finding | Done |
|---|---|---|
| 1 | after "play X", `voice_reply` chose pause or mute from a stale `source` (10s refresh cooldown): could pause Everywhere in both rooms for good | moot: no reply, so nothing to silence |
| 2 | the pause inside `voice_reply` had no `continue_on_error`; an error ended the script with no resume | moot (pause removed from `voice_reply`) |
| 3 | `mode: single` scripts drop overlapping calls (`snapcast_apply_mute`, `play_room_playlist`, `voice_music_pause`) | queued / parallel / queued |
| 4 | replies after "play X" came 1.3-1.5s late (HA's Spotify pause sleeps 1s) | moot: no reply |
| 5 | `offset` must go under `data:` | `data: {offset: 0}` |
| 6 | `voice_muted_` created by neither plan | step 3 helpers |
| 7 | the gate as an automation condition could leave music paused | checked inside `voice_reply` |
| 8 | Pi default card is HDMI; `uv` not on the Pi's PATH | `amixer -c Headphones`; `%h/.local/bin/uv` |
| 9 | `~/homelab/.env.mqtt` doesn't exist on xero | per-host path |
| 10 | bare "stop" is the nearest word to "stop white noise" | dropped (user) |
| 11 | docs table missing tiles and `scripts.yaml` | added |
| - | living-room button stops silently when Bluetooth fails | push notification (user; superseded 2026-11-18: Bluetooth errors ignored) |

## Seventh review (2026-11-18) - all applied

| # | Finding | Done |
|---|---|---|
| 1 | a failing media call is caught by HA, which answers "Done", not the error | `voice_start_music` script with `{ok}`; "Couldn't play ..." |
| 2 | "next/previous" after the wake-word pause load the track paused (librespot 0.8) and nothing resumes | they keep `voice_paused_` on, so `voice_resume` resumes |
| 3 | "resume/next/previous" acted on the last-used device, e.g. the bedroom from the living room at night; bare "resume" is a false-wake risk | room guard ("The music is in the bedroom"); never on `raspberrypi` with white noise on; multi-word forms only |
| 4 | music started where it can't be heard got no reply | flag only if audible here; else "Playing in the living room" (user) |
| 5 | `flock -n` let the bridge answer `connected` before the sink was default | `bt_speaker_mqtt.py` waits for the lock and answers `connected` only with the Apollo as default (multi-room piece 4) |
| 6 | voice "play X" in the living room played even when Bluetooth failed | same check and push as the button (superseded 2026-11-18: ignored) |
| 7 | ntfy push needed a new account | HA phone app (user; superseded 2026-11-18: no push) |
| 8 | a queued wake-word run could wipe the other room's music-started flag | cleared only while still listening |
| 9 | the restore overwrote white noise's PCM 91; a hand-muted jack stayed muted | no restore while white noise runs; preset with `unmute`; mute state saved |
| 10 | no saved false wakes to replay | bare short forms wait for a day of recordings from both boards |
| 11 | default-sink name ends `.1` | "starts with" |
| 12 | shared helpers had no owner; no rollback | `packages/night_quiet.yaml`; Rollback section |
| 13 | multi-room's bedroom error under white noise is never heard | multi-room says so (phone-app text only) |
| 14 | phone-app commands have no room | flag steps and guard only with a satellite room |
| 15 | a button press during a voice command left a reply over the new music | the button sets the flags |
| 16 | "stop the noise" vs "stop the song" | step 1 tests them against each other |

## Eighth review (2026-11-18) - all applied

User decisions the same day: **Bluetooth errors are ignored** - no living-room speaker connected means the reply is dropped, no waiting, no notification (this retired the push and the cross-plan Bluetooth timing findings); Spotify hidden from Assist; "play X" refused in the bedroom under white noise.

| # | Finding | Done |
|---|---|---|
| 1 | a bare "resume" reached HA's built-in command, which resumes the bedroom from anywhere | Spotify hidden from Assist (user) |
| 2 | the guard let Everywhere through when this room can't hear it | allowed only per `everywhere_bedroom_allowed` |
| 3 | the audible test counted the speaker's own reply mute | the shared test ignores `voice_muted_` |
| 4 | "next" on music paused earlier stayed silent | `media_play` after the skip in that case |
| 5, 6 | Bluetooth "connected" relied on multi-room; timeouts didn't fit; late answers misread | moot: Bluetooth errors ignored, replies drop when it isn't connected (user) |
| 7 | push would go to the old iPhone | moot: no push |
| 8 | rollback deleted the button and left mutes on | `play_button.yaml`; rollback clears flags and restores the volume first |
| 9 | a skipped restore left a file that later overwrote white noise | file deleted; start-up restore only without white noise |
| 10 | helpers without `initial:` start silent / "always night" | values set once after the first load, tested |
| 11 | some errors still abort; undefined `started`; single mode | `default({})`, `mode: parallel`, README gotcha |
| 12 | a button flag could swallow a later reply | flags only while a command is under way |
| 13 | the guard's answer could name the wrong place | laptop/phone and "Nothing is playing" branches |
| 14 | short forms already exist; recordings item named only the bedroom | rework `voice_spotify_control`; open item both boards, `replay_recordings.sh` device id |
| 15 | `packages/` is voice-assistant's folder | real paths; README lists owners |

## Ninth review (2026-11-18) - all applied

| # | Finding | Done |
|---|---|---|
| 1 | two commands within 10s: HA skips the second Spotify refresh and Spotcast never refreshes, so the pause and the guard saw idle | local record of the started device, used when newer than Spotify's state |
| 2 | night preset 40 is ~-60 dB on the Pi (dB-linear `%`), inaudible | set by ear at build time, ~75-82 (user) |
| 3 | HA exposes new entities to Assist automatically | unexpose each new media player; "none exposed" check in steps 3 and 8 |
| 4 | the button's "command under way" test was nearly always true (`responding` sticks) | went `listening` < 30s ago |
| 5 | stale Bluetooth reconnect text | rewritten; "or" in the bridge's check |
| 6 | white noise could be left at the reply preset | on a skipped restore, PCM set to `WHITE_NOISE_LEVEL` |
| 7 | `play_room_playlist` in the gitignored `scripts.yaml` | in `packages/play_button.yaml`; wrapper stays |
| 8 | the calibration poller cron line was undocumented and never removed | docs row; open item to remove after the week |
| 9 | multi-room's everywhere branch didn't mention `voice_start_music` | recorded in the paused multi-room plan's ninth table |
| - | user: room guard for "pause the music" and "music volume up/down" too | Design 9 |
