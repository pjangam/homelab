#!/usr/bin/env python3
"""Run the preferred Assist pipeline over the websocket exactly as the phone
app does for voice (start_stage stt, audio streamed as binary frames), feeding
it a 16kHz mono 16-bit WAV. Prints every pipeline event. Distinguishes "the
pipeline cannot take voice at all" from "this client never sends audio".
    set -a; . ./.env.healthcheck; set +a; test_pipeline_ws.py file.wav [end_stage]
"""
import asyncio, json, os, sys, wave
import websockets

async def main(path, end_stage):
    async with websockets.connect("ws://localhost:8123/api/websocket", max_size=None) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": os.environ["HA_TOKEN"]}))
        print(json.loads(await ws.recv())["type"])
        await ws.send(json.dumps({"id": 1, "type": "assist_pipeline/run", "start_stage": "stt",
                                  "end_stage": end_stage, "input": {"sample_rate": 16000}}))
        handler = None
        while True:
            msg = json.loads(await ws.recv())
            print(json.dumps(msg)[:400])
            if msg.get("type") == "result" and not msg.get("success"):
                return
            ev = msg.get("event", {})
            if ev.get("type") == "run-start":
                handler = ev["data"]["runner_data"]["stt_binary_handler_id"]
                break
        with wave.open(path) as w:
            pcm = w.readframes(w.getnframes())
        silence = b"\0" * 32000  # 1s trailing silence so VAD ends the command
        for i in range(0, len(pcm + silence), 2048):
            await ws.send(bytes([handler]) + (pcm + silence)[i:i + 2048])
            await asyncio.sleep(0.03)
        await ws.send(bytes([handler]))  # empty frame = end of audio
        while True:
            msg = json.loads(await ws.recv())
            print(json.dumps(msg)[:400])
            if msg.get("event", {}).get("type") in ("run-end", "error"):
                return

asyncio.run(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "intent"))
