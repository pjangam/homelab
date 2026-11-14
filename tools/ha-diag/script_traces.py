#!/usr/bin/env python3
"""Print a Home Assistant script's recent run traces: when it ran, who/what
started it, whether it finished, and the error if it failed. HA keeps the
last few traces in memory (lost on restart), so check soon after a failure.

Run on xero:
  tools/ha-diag/script_traces.py play_bedroom_track
  tools/ha-diag/script_traces.py voice_play_song automation   # an automation, by its id
"""
import asyncio, json, os, sys
from pathlib import Path
import websockets

ROOT = Path(__file__).resolve().parents[2]
for line in (ROOT / ".env.healthcheck").read_text().splitlines():
    if line.startswith("HA_TOKEN="):
        TOKEN = line.split("=", 1)[1].strip().strip('"')


async def main(script, domain):
    async with websockets.connect("ws://localhost:8123/api/websocket", max_size=None) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        await ws.recv()
        await ws.send(json.dumps({"id": 1, "type": "trace/list", "domain": domain, "item_id": script}))
        traces = json.loads(await ws.recv())["result"]
        for i, t in enumerate(sorted(traces, key=lambda t: t["timestamp"]["start"]), start=2):
            await ws.send(json.dumps({"id": i, "type": "trace/get", "domain": domain,
                                      "item_id": script, "run_id": t["run_id"]}))
            full = json.loads(await ws.recv())["result"]
            ctx = full.get("context") or {}
            started_by = "user " + ctx["user_id"][:8] if ctx.get("user_id") else ("parent " + ctx["parent_id"][:8] if ctx.get("parent_id") else "system")
            print(t["timestamp"]["start"][:19], t["state"], t.get("script_execution"), started_by)
            if full.get("error"):
                print("   error:", full["error"])
            trig = (full.get("trace", {}).get("trigger") or [{}])[0].get("variables", {}).get("trigger", {})
            if trig.get("sentence"):
                print("   heard:", repr(trig["sentence"]), "device:", (trig.get("device_id") or "-")[:8])
            for path, steps in full.get("trace", {}).items():
                for s in steps:
                    if s.get("error"):
                        print("  ", path, "->", s["error"])
                    res = s.get("result") or {}
                    if path.endswith("/if") or "conversation_response" in json.dumps(res) or "response" in res:
                        print("  ", path, "->", json.dumps(res)[:200])


asyncio.run(main(sys.argv[1] if len(sys.argv) > 1 else "play_bedroom_track",
                 sys.argv[2] if len(sys.argv) > 2 else "script"))
