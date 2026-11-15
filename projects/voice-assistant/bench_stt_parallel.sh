#!/usr/bin/env bash
# Fallback vs parallel for the stt-fallback proxy (2026-11-15). Times the same
# clips through speech-to-phrase alone (127.0.0.1:10301) and through a test
# copy of the proxy on 127.0.0.1:10302 in each mode:
#   fallback      IndicConformer only after speech-to-phrase returns nothing
#   parallel      IndicConformer started with speech-to-phrase on every request
#   parallel-2t   the same, IndicConformer limited to 2 of the 4 cores
# English clips show what parallel costs the commands that already work (CPU
# contention); Marathi clips show what it saves on a miss. Prints p50 and max
# per clip and mode. The live proxy on :10300 is not touched.
#   set -a; . ./.env.healthcheck; set +a
#   projects/voice-assistant/bench_stt_parallel.sh [runs]   (default 5)
set -euo pipefail
cd "$(dirname "$0")"
runs=${1:-5}
HA=http://localhost:8123
work=$(mktemp -d); trap 'docker rm -f stt-fallback-bench >/dev/null 2>&1; rm -rf "$work"' EXIT

tts() {  # tts <lang> <text> <out.wav>
  local url
  url=$(curl -sf -H "Authorization: Bearer $HA_TOKEN" -H 'Content-Type: application/json' \
    -d "{\"engine_id\":\"tts.google_translate_en_com\",\"message\":\"$2\",\"language\":\"$1\"}" \
    "$HA/api/tts_get_url" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])')
  curl -sf "$HA$url" | docker exec -i homeassistant ffmpeg -loglevel error -i pipe:0 \
    -ar 16000 -ac 1 -c:a pcm_s16le -f wav pipe:1 >"$3"
}
declare -A clips=(
  [en-faint]="en|play faint" [en-fan]="en|turn on the hall fan" [en-ac]="en|set the AC to 24 degrees"
  [mr-aggobai]="mr|प्ले अग्गोबाई ढग्गोबाई" [mr-manu]="mr|प्ले मनू ताई आली")
for k in "${!clips[@]}"; do v=${clips[$k]}; tts "${v%%|*}" "${v#*|}" "$work/$k.wav"; done

measure() {  # measure <label> <port>
  for k in $(printf '%s\n' "${!clips[@]}" | sort); do
    python3 wyoming_transcribe.py "127.0.0.1:$2" "$work/$k.wav" >/dev/null  # warm
    for _ in $(seq "$runs"); do
      python3 wyoming_transcribe.py "127.0.0.1:$2" "$work/$k.wav" | awk -v l="$1" -v k="$k" '{sub("s","",$1); print l, k, $1, $2, $3, $4, $5}'
    done
  done
}
start_proxy() {  # start_proxy <PARALLEL> <IC_THREADS>
  docker rm -f stt-fallback-bench >/dev/null 2>&1 || true
  docker run -d --name stt-fallback-bench --network host -e LISTEN_PORT=10302 -e UPSTREAM=127.0.0.1:10301 \
    -e PARALLEL="$1" -e IC_THREADS="$2" -v indicconformer-cache:/model \
    -v "$PWD:/app/projects/voice-assistant:ro" \
    -v "$PWD/../../HOMEASSISTANT_CONFIG/.storage:/app/HOMEASSISTANT_CONFIG/.storage:ro" \
    indicconformer python -u /app/projects/voice-assistant/stt_fallback.py >/dev/null
  until docker logs stt-fallback-bench 2>&1 | grep -q "fallback ready"; do sleep 1; done
}
{
  measure "stp-alone" 10301
  start_proxy 0 0; measure "fallback" 10302
  start_proxy 1 0; measure "parallel" 10302
  start_proxy 1 2; measure "parallel-2t" 10302
} >"$work/times.txt"
python3 - "$work/times.txt" <<'EOF'
import sys, collections, statistics
t = collections.defaultdict(list); text = {}
for line in open(sys.argv[1]):
    mode, clip, secs, *said = line.split()
    t[(clip, mode)].append(float(secs)); text[(clip, mode)] = " ".join(said)
modes = ["stp-alone", "fallback", "parallel", "parallel-2t"]
print(f"{'clip':12}" + "".join(f"{m:>22}" for m in modes))
for clip in sorted({c for c, _ in t}):
    row = []
    for m in modes:
        v = sorted(t[(clip, m)])
        row.append(f"p50 {statistics.median(v):.2f} max {v[-1]:.2f}")
    print(f"{clip:12}" + "".join(f"{r:>22}" for r in row))
print()
for clip in sorted({c for c, _ in t}):
    print(f"{clip:12} " + " | ".join(f"{m}: {text[(clip, m)]}" for m in modes))
EOF
