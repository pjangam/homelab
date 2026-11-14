#!/usr/bin/env python3
"""Recent Assist pipeline runs, every pipeline: when, what speech-to-text
heard, and what HA answered (or the error). HA keeps only the last few runs
per pipeline in memory, so run it soon after a failed voice command.

  set -a; . ./.env.healthcheck; set +a
  projects/voice-assistant/recent_runs.py [count per pipeline, default 8]
"""
import json
import sys

from ha_ws import call

N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
for p in call({"type": "assist_pipeline/pipeline/list"})["pipelines"]:
    runs = call({"type": "assist_pipeline/pipeline_debug/list", "pipeline_id": p["id"]})["pipeline_runs"]
    if not runs:
        continue
    print(f"== {p['name']}")
    for r in runs[-N:]:
        ev = call({"type": "assist_pipeline/pipeline_debug/get", "pipeline_id": p["id"],
                   "pipeline_run_id": r["pipeline_run_id"]})["events"]
        heard = answer = err = None
        device = ""
        for e in ev:
            d = e.get("data") or {}
            if e["type"] == "run-start":
                device = (d.get("satellite_id") or d.get("device_id") or "")
            if e["type"] == "stt-end":
                heard = (d.get("stt_output") or {}).get("text")
            elif e["type"] == "intent-end":
                answer = (d.get("intent_output") or {}).get("response", {}).get("speech", {}).get("plain", {}).get("speech")
            elif e["type"] == "error":
                err = f"{d.get('code')}: {d.get('message')}"
        print(f"{r['timestamp'][:19]} {device[-24:]:24} heard={heard!r}")
        if answer:
            print(f"{'':45}-> {answer}")
        if err:
            print(f"{'':45}!! {err}")
