#!/usr/bin/env python3
"""Minimal Home Assistant websocket client for the voice-assistant setup.

Reads HA_TOKEN from the environment (source ../../.env.healthcheck or
../../.env.voice first). Usage as a CLI:
    ha_ws.py '{"type": "config/area_registry/list"}'
or import call() from another script.
"""
import asyncio
import json
import os
import sys

import websockets

HA_WS = os.environ.get("HA_WS", "ws://localhost:8123/api/websocket")


async def _call_many(msgs):
    async with websockets.connect(HA_WS, max_size=None) as ws:
        await ws.recv()  # auth_required
        await ws.send(json.dumps({"type": "auth", "access_token": os.environ["HA_TOKEN"]}))
        auth = json.loads(await ws.recv())
        if auth["type"] != "auth_ok":
            raise SystemExit(f"auth failed: {auth}")
        results = []
        for i, msg in enumerate(msgs, start=1):
            await ws.send(json.dumps({**msg, "id": i}))
            while True:
                reply = json.loads(await ws.recv())
                if reply.get("id") == i and reply["type"] == "result":
                    break
            if not reply["success"]:
                raise SystemExit(f"{msg['type']} failed: {reply['error']}")
            results.append(reply["result"])
        return results


def call_many(msgs):
    return asyncio.run(_call_many(msgs))


def call(msg):
    return call_many([msg])[0]


if __name__ == "__main__":
    print(json.dumps(call(json.loads(sys.argv[1])), indent=1))
