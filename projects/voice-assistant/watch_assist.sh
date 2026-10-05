#!/usr/bin/env bash
# Live view of everything a voice attempt touches: HA's log (assist pipeline,
# wyoming, stt, auth failures), the speech-to-phrase container's log, and each
# new Assist pipeline run summarised stage by stage. For debugging a client
# (phone app, satellite) that "does nothing". Turn on debug first with:
#   logger.set_level {"homeassistant.components.assist_pipeline": "debug", ...}
#   set -a; . ./.env.healthcheck; set +a; projects/voice-assistant/watch_assist.sh
cd "$(dirname "$0")/../.."
tail -n0 -F HOMEASSISTANT_CONFIG/home-assistant.log 2>/dev/null \
  | grep --line-buffered -iE "assist_pipeline|wyoming|components\.stt|conversation|http\.ban|websocket_api" \
  | grep --line-buffered -vE "wyoming.coordinator|non-existing handler|chat_log|Exposed entities|slot lists" \
  | sed -u "s/^/[ha] /" &
docker logs -f --since 1s speech-to-phrase 2>&1 | grep --line-buffered -vE '^(LOG \(|online2-cli)' | sed -u 's/^/[stp] /' &
trap 'kill $(jobs -p) 2>/dev/null' EXIT
python3 -u - <<'PY'
import json, time, sys
sys.path.insert(0, "projects/voice-assistant")
from ha_ws import call, call_many
pipe = call({"type": "assist_pipeline/pipeline/list"})["preferred_pipeline"]
seen = {r["pipeline_run_id"] for r in call({"type": "assist_pipeline/pipeline_debug/list", "pipeline_id": pipe})["pipeline_runs"]}
pending = {}
while True:
    time.sleep(3)
    runs = call({"type": "assist_pipeline/pipeline_debug/list", "pipeline_id": pipe})["pipeline_runs"]
    for r in runs:
        rid = r["pipeline_run_id"]
        if rid not in seen:
            seen.add(rid); pending[rid] = time.time()
            print(f"[run] new {rid} at {r['timestamp']}")
    for rid in list(pending):
        ev = call({"type": "assist_pipeline/pipeline_debug/get", "pipeline_id": pipe, "pipeline_run_id": rid})["events"]
        if any(e["type"] == "run-end" for e in ev) or time.time() - pending[rid] > 60:
            del pending[rid]
            for e in ev:
                d = e.get("data") or {}
                if e["type"] == "stt-end": d = d.get("stt_output")
                elif e["type"] == "intent-end": d = (d.get("intent_output") or {}).get("response", {}).get("speech")
                print(f"[run]   {e['type']}: {json.dumps(d)[:300]}")
            if not ev: print("[run]   (no events after 60s)")
PY
