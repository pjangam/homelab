#!/usr/bin/env bash
# Round-trip check of the speech-to-text: synthesise each phrase with HA's
# Google Translate TTS, convert to 16kHz mono PCM, post it to HA's STT API for
# stt.speech_to_phrase and print what came back. Nothing is executed - this
# tests transcription only, not the command.
#   set -a; . ./.env.healthcheck; set +a; projects/voice-assistant/test_stt.sh ["phrase" ...]
set -euo pipefail
HA=http://localhost:8123
auth=(-H "Authorization: Bearer $HA_TOKEN")
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
phrases=("$@")
[ ${#phrases[@]} -gt 0 ] || phrases=(
  "turn on white noise" "turn off the bedroom light" "set the AC to 24 degrees"
  "hall fan fast" "turn off the AC" "activate ojaswi sleeping scene")
for p in "${phrases[@]}"; do
  url=$(curl -sf "${auth[@]}" -H 'Content-Type: application/json' \
    -d "{\"engine_id\":\"tts.google_translate_en_com\",\"message\":\"$p\",\"language\":\"en\"}" \
    "$HA/api/tts_get_url" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')
  curl -sf "$HA$url" -o "$work/in.mp3"
  # local sox has no mp3 support; the HA image ships ffmpeg
  docker exec -i homeassistant ffmpeg -loglevel error -i pipe:0 -ar 16000 -ac 1 -c:a pcm_s16le -f wav pipe:1 \
    <"$work/in.mp3" >"$work/in.wav"
  got=$(curl -sf "${auth[@]}" --data-binary @"$work/in.wav" \
    -H 'X-Speech-Content: format=wav; codec=pcm; sample_rate=16000; bit_rate=16; channel=1; language=en' \
    "$HA/api/stt/stt.speech_to_phrase" | python3 -c 'import json,sys;r=json.load(sys.stdin);print(r.get("text"), "|", r["result"])')
  printf '%-34s -> %s\n' "$p" "$got"
done
