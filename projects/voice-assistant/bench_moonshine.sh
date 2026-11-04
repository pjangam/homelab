#!/usr/bin/env bash
# Moonshine counterpart of bench_whisper.sh: same phrases, same TTS audio, same
# columns. Moonshine's compute scales with clip length (Whisper always pays
# for a 30s window), so it should suit 2s commands. useful-moonshine-onnx,
# CPU, installed from pypi on each run; models download from Hugging Face.
#   set -a; . ./.env.healthcheck; set +a
#   projects/voice-assistant/bench_moonshine.sh [model ...]   (default: tiny base)
set -euo pipefail
cd "$(dirname "$0")"
HA=http://localhost:8123
auth=(-H "Authorization: Bearer $HA_TOKEN")
models=("$@"); [ ${#models[@]} -gt 0 ] || models=(moonshine/tiny moonshine/base)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
phrases=("play papercut" "play numb by linkin park" "play shape of you"
         "play bohemian rhapsody by queen" "play aggobai dhaggobai")
i=0
for p in "${phrases[@]}"; do
  i=$((i+1))
  url=$(curl -sf "${auth[@]}" -H 'Content-Type: application/json' \
    -d "{\"engine_id\":\"tts.google_translate_en_com\",\"message\":\"$p\",\"language\":\"en\"}" \
    "$HA/api/tts_get_url" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')
  curl -sf "$HA$url" -o "$work/$i.mp3"
  docker exec -i homeassistant ffmpeg -loglevel error -i pipe:0 -ar 16000 -ac 1 -c:a pcm_s16le -f wav pipe:1 \
    <"$work/$i.mp3" >"$work/$i.wav"
  printf '%s\t%s\n' "$i.wav" "$p" >>"$work/phrases.tsv"
done
cat >"$work/bench.py" <<'EOF'
import os, sys, time
from moonshine_onnx import MoonshineOnnxModel, load_audio, load_tokenizer
tok = load_tokenizer()
rows = [l.rstrip("\n").split("\t") for l in open("/w/phrases.tsv")]
for name in sys.argv[1:]:
    t = time.time(); m = MoonshineOnnxModel(model_name=name)
    print(f"\n== {name} (load {time.time()-t:.1f}s)", flush=True)
    m.generate(load_audio(f"/w/{rows[0][0]}"))  # warm-up
    for f, said in rows:
        dur = (os.path.getsize(f"/w/{f}") - 44) / 32000  # 16kHz s16 mono
        t = time.time()
        text = tok.decode_batch(m.generate(load_audio(f"/w/{f}")))[0].strip()
        print(f"{time.time()-t:5.2f}s  audio {dur:.1f}s  {said!r:36} -> {text!r}", flush=True)
EOF
docker run --rm -v "$work:/w" -v moonshine-bench-cache:/root/.cache python:3.12-slim sh -c \
  "pip install -q --root-user-action=ignore useful-moonshine-onnx >/dev/null && python /w/bench.py ${models[*]}"
