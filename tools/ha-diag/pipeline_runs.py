#!/usr/bin/env python3
"""Print Home Assistant's recent voice (Assist) pipeline runs: when, what
speech-to-text heard, which intent/sentence trigger it matched (or the error),
and what HA replied. HA keeps these in memory only (lost on restart, last ~10
runs per pipeline), so check soon after a command misbehaves.

Run on xero:
  tools/ha-diag/pipeline_runs.py            # all pipelines
  tools/ha-diag/pipeline_runs.py next       # only runs whose heard text contains "next"
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "projects/voice-assistant"))
if "HA_TOKEN" not in os.environ:
    for line in (ROOT / ".env.healthcheck").read_text().splitlines():
        if line.startswith("HA_TOKEN="):
            os.environ["HA_TOKEN"] = line.split("=", 1)[1].strip().strip('"')
from ha_ws import call  # noqa: E402

needle = (sys.argv[1] if len(sys.argv) > 1 else "").lower()
pipelines = call({"type": "assist_pipeline/pipeline/list"})["pipelines"]
rows = []
for p in pipelines:
    runs = call({"type": "assist_pipeline/pipeline_debug/list", "pipeline_id": p["id"]})["pipeline_runs"]
    for r in runs:
        ev = call({"type": "assist_pipeline/pipeline_debug/get", "pipeline_id": p["id"],
                   "pipeline_run_id": r["pipeline_run_id"]})["events"]
        heard, intent, reply, errors = "", "", "", []
        for e in ev:
            d = e.get("data") or {}
            if e["type"] == "stt-end":
                heard = (d.get("stt_output") or {}).get("text", "")
            elif e["type"] == "intent-start" and not heard:
                heard = d.get("intent_input", "")
            elif e["type"] == "intent-end":
                out = d.get("intent_output") or {}
                resp = out.get("response") or {}
                reply = ((resp.get("speech") or {}).get("plain") or {}).get("speech", "")
                intent = resp.get("response_type", "")
                if resp.get("data", {}).get("code"):
                    intent += " " + resp["data"]["code"]
                tgt = [t.get("name") for t in (resp.get("data") or {}).get("success", [])]
                if tgt:
                    intent += " -> " + ", ".join(filter(None, tgt))
            elif e["type"] == "error":
                errors.append(f'{d.get("code")}: {d.get("message")}')
        rows.append((r["timestamp"], p["name"], heard, intent, reply, errors))

for ts, name, heard, intent, reply, errors in sorted(rows):
    if needle and needle not in heard.lower():
        continue
    print(ts[:19], f"[{name}]", repr(heard))
    if intent or reply:
        print("   ", intent, "| reply:", repr(reply))
    for e in errors:
        print("    error:", e)
