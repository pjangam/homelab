#!/usr/bin/env bash
# Would AI4Bharat's IndicConformer (Marathi) work as a fallback for the
# Marathi song titles Speech-to-Phrase misses? Synthesises "play <title>" for
# the Marathi playlist twice with HA's Google TTS - the Marathi voice reading
# Devanagari, and the English voice reading Spotify's Latin title - runs each
# clip through IndicConformer on xero's CPU (onnx-asr, int8 ONNX) and through
# devanagari_match.py, and prints the time, the Devanagari it heard and the
# song it would play. Nothing is played.
#   set -a; . ./.env.healthcheck; set +a
#   projects/voice-assistant/bench_indicconformer.sh [extra.wav ...]
# Extra 16kHz mono WAVs (e.g. HA debug recordings of real attempts) are
# transcribed too, labelled by file name.
# Image: Dockerfile.indicconformer (built on first run). Model:
# OpenVoiceOS/ai4bharat-indicconformer-mr-onnx (MIT, 138MB int8), cached in
# the docker volume indicconformer-cache.
set -euo pipefail
cd "$(dirname "$0")"
HA=http://localhost:8123
auth=(-H "Authorization: Bearer $HA_TOKEN")
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
if ! docker image inspect indicconformer-bench >/dev/null 2>&1; then
  mkdir "$work/ctx"
  whl="$work/ctx/onnx_asr-0.12.0-py3-none-any.whl"
  # resume (-C -) until complete: downloads from xero get cut off midway
  for _ in $(seq 1 15); do
    curl -s -C - -m 60 -o "$whl" https://files.pythonhosted.org/packages/6a/60/2fa469a2ee674c35ab48821a1039762ae7b9d0b88188ac1012e779477f76/onnx_asr-0.12.0-py3-none-any.whl || true
    [ "$(stat -c%s "$whl" 2>/dev/null)" = 3980006 ] && break
  done
  echo "5e7ceca454609819ea7833f61e2302e0c8f6ece4f8a78b66c5daba53cb51de4a  $whl" | sha256sum -c --quiet
  docker build -t indicconformer-bench -f Dockerfile.indicconformer "$work/ctx"
fi

# Latin title as in Spotify | the same in Devanagari
titles=(
  "aggobai dhaggobai|अग्गोबाई ढग्गोबाई" "sasa to sasa ki kapoos jasa|ससा तो ससा की कापूस जसा"
  "chiv chiv chimni|चिव चिव चिमणी" "chanda rani|चांदा राणी" "konas thauk kasa|कोणास ठाऊक कसा"
  "mungibai|मुंगीबाई" "illu illu pillu|इल्लु इल्लु पिल्लु" "boom boom ba|बूम बूम बा"
  "eka makdane kadhla dukan|एका माकडाने काढलं दुकान" "beduk shalemadhe gela|बेडूक शाळेमध्ये गेला"
  "jhuk jhuk gadi|झुक झुक गाडी" "sang na aai|सांग ना आई" "manu tai aali|मनू ताई आली"
  "pakhra pakhra yeun ja|पाखरा पाखरा येऊन जा" "swapnat pahili ranichi baug|स्वप्नात पाहिली राणीची बाग")

tts() {  # tts <lang> <text> <out.wav>
  local url
  url=$(curl -sf "${auth[@]}" -H 'Content-Type: application/json' \
    -d "{\"engine_id\":\"tts.google_translate_en_com\",\"message\":\"$2\",\"language\":\"$1\"}" \
    "$HA/api/tts_get_url" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')
  curl -sf "$HA$url" | docker exec -i homeassistant ffmpeg -loglevel error -i pipe:0 \
    -ar 16000 -ac 1 -c:a pcm_s16le -f wav pipe:1 >"$3"
}
i=0
for t in "${titles[@]}"; do
  latin=${t%%|*}; dev=${t#*|}; i=$((i+1))
  tts mr "प्ले $dev" "$work/mr$i.wav";    printf 'mr%s.wav\tmr: %s\n' "$i" "$latin" >>"$work/clips.tsv"
  tts en "play $latin" "$work/en$i.wav";  printf 'en%s.wav\ten: %s\n' "$i" "$latin" >>"$work/clips.tsv"
done
# not Marathi songs: what else reaches a fallback when Speech-to-Phrase gives
# up. A good result is "nothing", or the right English song.
for p in "turn on the hall fan" "set the AC to 24 degrees" "what time is it" \
         "play numb by linkin park" "play faint" "play something nice"; do
  i=$((i+1)); tts en "$p" "$work/x$i.wav"; printf 'x%s.wav\tother: %s\n' "$i" "$p" >>"$work/clips.tsv"
done
for f in "$@"; do cp "$f" "$work/"; printf '%s\treal: %s\n' "$(basename "$f")" "$(basename "$f")" >>"$work/clips.tsv"; done

cat >"$work/bench.py" <<'EOF'
import json, sys, time
import numpy as np
import onnx_asr


def audio(path):
    # ffmpeg writing to a pipe leaves the WAV length unset (0x7fffffff), so
    # read the 16kHz s16 mono samples after the 44-byte header ourselves
    return np.frombuffer(open(path, "rb").read()[44:], dtype=np.int16).astype(np.float32) / 32768


t = time.time()
m = onnx_asr.load_model("nemo-conformer-ctc", "/model", quantization="int8")
print(f"load {time.time()-t:.1f}s", file=sys.stderr, flush=True)
rows = [l.rstrip("\n").split("\t") for l in open("/w/clips.tsv")]
m.recognize(audio(f"/w/{rows[0][0]}"), sample_rate=16000)  # warm-up
for f, said in rows:
    t = time.time()
    text = m.recognize(audio(f"/w/{f}"), sample_rate=16000)
    print(json.dumps({"said": said, "text": text, "secs": time.time() - t}, ensure_ascii=False), flush=True)
EOF
# the model files, once, into the cache volume (Hugging Face, not pypi)
docker run --rm -v indicconformer-cache:/model indicconformer-bench python -c "
from huggingface_hub import snapshot_download
snapshot_download('OpenVoiceOS/ai4bharat-indicconformer-mr-onnx', local_dir='/model',
                  allow_patterns=['config.json', 'vocab.txt', 'model.int8.onnx'])" >/dev/null
docker run --rm --cpus 4 -v indicconformer-cache:/model:ro -v "$work:/w" indicconformer-bench \
  python /w/bench.py | python3 devanagari_match.py
