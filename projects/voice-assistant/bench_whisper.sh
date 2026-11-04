#!/usr/bin/env bash
# How fast is Whisper on xero's N5105? Synthesises song-request phrases with
# HA's Google Translate TTS (same path as test_stt.sh), then transcribes each
# with faster-whisper (int8, CPU) at several model sizes and prints the text
# and the wall time per phrase. Answers "can free-form 'play <song>' run
# locally, or does it need a cloud STT" for "Spotify by voice" phase 2.
# Models are cached in the docker volume whisper-bench-models.
#   set -a; . ./.env.healthcheck; set +a
#   projects/voice-assistant/bench_whisper.sh [model ...]   (default: tiny base small)
set -euo pipefail
cd "$(dirname "$0")"
HA=http://localhost:8123
auth=(-H "Authorization: Bearer $HA_TOKEN")
models=("$@"); [ ${#models[@]} -gt 0 ] || models=(tiny.en base.en small.en)
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
from faster_whisper import WhisperModel
rows = [l.rstrip("\n").split("\t") for l in open("/w/phrases.tsv")]
for name in sys.argv[1:]:
    t = time.time(); m = WhisperModel(name, device="cpu", compute_type="int8", cpu_threads=4)
    print(f"\n== {name} (load {time.time()-t:.1f}s)", flush=True)
    m.transcribe(f"/w/{rows[0][0]}", beam_size=1, language="en")  # warm-up
    for f, said in rows:
        dur = (os.path.getsize(f"/w/{f}") - 44) / 32000  # 16kHz s16 mono; piped wav header has no length
        t = time.time()
        segs, _ = m.transcribe(f"/w/{f}", beam_size=1, language="en", vad_filter=False)
        text = "".join(s.text for s in segs).strip()
        print(f"{time.time()-t:5.2f}s  audio {dur:.1f}s  {said!r:36} -> {text!r}", flush=True)
EOF
# The wyoming-whisper image already has faster-whisper in a venv; pypi.org
# itself timed out from xero on 2026-11-04, so no pip install here.
docker run --rm --entrypoint /usr/src/.venv/bin/python -v "$work:/w" \
  -v whisper-bench-models:/root/.cache/huggingface rhasspy/wyoming-whisper:latest /w/bench.py "${models[@]}"
