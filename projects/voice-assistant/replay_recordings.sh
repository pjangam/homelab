#!/usr/bin/env bash
# Replay the satellite's saved voice commands through speech-to-text at
# several volume gains, to tell "too quiet / noisy audio" apart from "words
# the model doesn't know". Needs HA's debug recordings on
# (assist_pipeline: debug_recording_dir in configuration.yaml). Transcription
# only - nothing is executed.
#   set -a; . ./.env.healthcheck; set +a
#   projects/voice-assistant/replay_recordings.sh [count] [gain ...]
#   (default: the last 6 commands, at gains 1 2 4 8)
set -euo pipefail
cd "$(dirname "$0")/../.."
HA=http://localhost:8123
count=${1:-6}; shift || true
gains=("$@"); [ ${#gains[@]} -gt 0 ] || gains=(1 2 4 8)
dev=f201def98beb10329a75b755eccf06a6   # Voice Satellite's HA device id
dir="HOMEASSISTANT_CONFIG/assist_recordings/$dev/Home Assistant"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
for run in $(ls -t "$dir" | head -n "$count" | tac); do
  wav="$dir/$run/01_stt-stt.speech_to_phrase.wav"
  [ -f "$wav" ] || continue
  line="$(date -d @"$(stat -c %Y "$wav")" +%m-%d\ %H:%M)"
  for g in "${gains[@]}"; do
    # The HA image ships ffmpeg; alimiter stops the gain from clipping.
    docker exec -i homeassistant ffmpeg -loglevel error -i pipe:0 \
      -af "volume=${g},alimiter=limit=0.95" -ar 16000 -ac 1 -c:a pcm_s16le -f wav pipe:1 \
      <"$wav" >"$work/g.wav"
    got=$(curl -sf -H "Authorization: Bearer $HA_TOKEN" --data-binary @"$work/g.wav" \
      -H 'X-Speech-Content: format=wav; codec=pcm; sample_rate=16000; bit_rate=16; channel=1; language=en' \
      "$HA/api/stt/stt.speech_to_phrase" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text") or "-")')
    line+="  x${g}: ${got}"
  done
  echo "$line"
done
