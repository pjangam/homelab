# Voice assistant (HA Assist, local)

Voice control for lights, white noise, fans and the AC through Home
Assistant's built-in **Assist**. Fully local, not "smart": speech is matched
against a fixed set of commands for the entities exposed to Assist.

HA here is a plain Docker container, not HA OS, so voice add-ons cannot be
installed. That is very likely why an earlier attempt at a voice plugin never
worked. Each voice piece runs as its own container in `docker-compose.yml`,
connected to HA through the Wyoming integration.

## Pieces

| Piece | Where |
|---|---|
| Speech-to-text | `speech-to-phrase` container, `127.0.0.1:10300`. Legacy v1.4 (Kaldi) image: the newer Speech-to-Phrase ships only as an HA OS app. Fast on xero's CPU, where Whisper would not be. |
| Command matching | HA's own conversation agent (`prefer_local_intents` on), plus `packages/voice_commands.yaml` for what its built-in sentences do not cover |
| Text-to-speech | `piper` container, `127.0.0.1:10200`, voice `en_US-lessac-medium`. **Required, not optional** - see Gotchas. |
| Pipeline | The preferred "Home Assistant" Assist pipeline: `stt.speech_to_phrase` + `tts.piper` |
| Mic | The HA phone app's Assist button, for now. Planned: the packed-away aarti-lights ESP32 + INMP441, reflashed to ESPHome, with a custom "Alejandro" openWakeWord model on xero (the board is an original ESP32, not an S3). Wiring: `wiring.html` (https://claude.ai/artifact/UWMZYLRTNdLTgHvdU6Vz6m) |

## Commands

Built in (HA + Speech-to-Phrase): `turn on/off <name>` for any exposed light,
switch, fan or media player; `activate <scene> scene`; `run <script> script`;
timers; `what time is it`.

Added in `packages/voice_commands.yaml` (sentence-trigger automations):
- `turn on/off the AC`, `set the AC to 24 [degrees]`, `AC 24 degrees` (16-30)
- `[set the] [bedroom] fan [to] high|fast|medium|low|slow` (bare "fan" = bedroom)
- `hall fan fast`, `living room fan low`, ...

Names and aliases come from `setup_assist.py`: bedroom light / tube light,
bedroom bulb, balcony light, bedroom fan, hall light, shelf light, hall fan,
white noise, AC.

## Files

- `setup_assist.py` - idempotent: which entities are exposed (and the stale
  Tinxy duplicates that are not), aliases, device areas, the Wyoming entry and
  the pipeline's STT. Edit the lists at its top, re-run, then restart
  `speech-to-phrase`.
- `packages/` - bind-mounted to `/config/packages`; loaded by
  `homeassistant: packages: !include_dir_named packages` in the gitignored
  `HOMEASSISTANT_CONFIG/configuration.yaml` (added 2026-10-05). Reload with
  `automation.reload` after editing.
- `custom_sentences/en/` - lists for `{wildcards}` in the sentence triggers
  (Speech-to-Phrase cannot hear a wildcard without one).
- `ha_ws.py` - tiny HA websocket client used by the above.
- `test_pipeline_ws.py file.wav [end_stage]` - runs the pipeline over the
  websocket exactly as the phone app does for voice (binary audio frames).
  `end_stage tts` reproduces the app's request.
- `watch_assist.sh` - live view of voice runs stage by stage, HA log and
  speech-to-phrase log, for "the client does nothing" debugging.
- `esphome/` - the ESP32 satellites: `voice-satellite-common.yaml` (shared), one small file per board - `voice-satellite.yaml` (first board, .125, HA area Bedroom) and `voice-living-room.yaml` (.126, waiting on a second INMP441) - `build_on_mac.sh [living]`, `esphome.sh`
  (ESPHome in docker: `compile`, `run --device /dev/ttyUSB0`, later OTA to
  192.168.1.125), and the gitignored `secrets.yaml` (Wi-Fi, API key, OTA
  password). **Prefer not to compile on xero:** the RAM is replaced and cleared
  (2026-10-09), but a full-core build still runs xero in the 90s°C on its
  pegboard until "xero cooling" in PROJECTS.md is done. Build on the Mac instead: `esphome/build_on_mac.sh` from a
  clone (venv, no Docker) flashes over USB on the Mac, OTA, or copies the
  `.bin` to xero for `esphome.sh flash-bin`.
- `wakewords/` - custom openWakeWord models, mounted into the `openwakeword`
  container (`127.0.0.1:10400`, preloads `hey_jarvis`, the wake word since 2026-10-08; `okay_nabu` before).
- `check_stt.sh` + `stt_probe.wav` - sends a saved "turn off the AC" clip
  (Piper's voice) through speech-to-text. Run every 15 min by
  `projects/healthcheck/healthcheck.sh`, which restarts speech-to-phrase
  when it fails (it trains on HA's custom sentences only at start, and can
  start before HA has loaded them after a boot), pushes a low-priority ntfy,
  and raises a problem only if the restart did not help. Restarts are logged
  in `~/.cache/healthcheck/stt-restarts.log`.
- `test_stt.sh` - synthesises phrases with HA's Google TTS and posts them to
  the STT API; transcription check only, executes nothing.

```sh
set -a; . ./.env.healthcheck; set +a      # HA_TOKEN for the scripts
projects/voice-assistant/setup_assist.py
docker restart speech-to-phrase          # retrain on new names/sentences
projects/voice-assistant/test_stt.sh "turn on white noise"
```

The container's own HA token is `HA_TOKEN_SPEECH_TO_PHRASE` in `.env`
(long-lived token "speech-to-phrase" in HA's profile page).

## Gotchas

- **The phone app's voice mode needs a TTS engine on the pipeline.** It always
  asks for `end_stage: tts`; without TTS, HA rejects the run with
  `validation-error: the pipeline does not support text-to-speech` before any
  audio is sent. The app shows nothing at all, typing still works, and the
  pipeline debug view lists the run with **zero events**. Cost an evening on
  2026-10-05 before `test_pipeline_ws.py ... tts` reproduced it.
- **Speech-to-Phrase spells initialisms out:** "AC" is transcribed "A C", and
  HA's matcher then knows no device called "A C". The sentence triggers list
  `(AC|A C|air conditioner)` for that reason. Do the same for any new
  initialism in a sentence trigger.
- **Retraining is only on start.** A newly exposed entity, a new alias or a new
  sentence trigger cannot be recognised until `docker restart speech-to-phrase`.
- **HA's alias list holds a `None`** as the slot for the entity's own name; keep
  it when editing aliases through the websocket API.
- Speech-to-Phrase only ever returns a sentence from its grammar, so a mumble
  can come back as the *nearest* command rather than nothing. Watch for false
  activations once a mic is always listening.
