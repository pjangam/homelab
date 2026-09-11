#!/usr/bin/env python3
"""Add a tile to the Stats dashboard without restarting Home Assistant.

Storage-mode dashboards live in HOMEASSISTANT_CONFIG/.storage/ but HA holds
them in memory, so hand-editing that JSON does nothing until HA restarts -
and on 2026-09-11 restarting HA for exactly that reason is what knocked the
MirAIe AC entity out for 37 minutes (the AC's availability is published
retain=false, so a fresh HA has no availability value and pins the entity
`unavailable`; see scripts/fix_miraie_ac.sh). Going through the websocket API
instead updates the live config and writes the file, with no restart and
nothing else disturbed.

Idempotent: adding a tile that is already on the board changes nothing.

  scripts/add_stats_dashboard_tile.py binary_sensor.foo
  scripts/add_stats_dashboard_tile.py binary_sensor.foo --after binary_sensor.bar

Needs HA_TOKEN in the environment (it is in .env.healthcheck).
"""
import argparse
import asyncio
import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

import websockets

REPO = Path(__file__).resolve().parent.parent
STORAGE = REPO / "HOMEASSISTANT_CONFIG" / ".storage"


async def ws_call(url, token, messages):
    """Open one authenticated session and run each message in order."""
    results = []
    async with websockets.connect(url, max_size=None) as ws:
        hello = json.loads(await ws.recv())
        if hello.get("type") != "auth_required":
            raise SystemExit(f"unexpected greeting from HA: {hello}")
        await ws.send(json.dumps({"type": "auth", "access_token": token}))
        auth = json.loads(await ws.recv())
        if auth.get("type") != "auth_ok":
            raise SystemExit(f"HA rejected the token: {auth}")
        for i, msg in enumerate(messages, start=1):
            await ws.send(json.dumps({"id": i, **msg}))
            while True:
                reply = json.loads(await ws.recv())
                if reply.get("id") == i and reply.get("type") == "result":
                    if not reply.get("success"):
                        raise SystemExit(f"HA refused {msg['type']}: {reply.get('error')}")
                    results.append(reply.get("result"))
                    break
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("entity")
    ap.add_argument("--dashboard", default="dashboard-stats")
    ap.add_argument("--section", type=int, default=0)
    ap.add_argument("--after", help="place the new tile directly after this entity")
    ap.add_argument("--url", default=os.environ.get("HA_URL", "http://localhost:8123"))
    args = ap.parse_args()

    token = os.environ.get("HA_TOKEN")
    if not token:
        sys.exit("HA_TOKEN not set - source .env.healthcheck first")

    ws_url = args.url.replace("http://", "ws://").replace("https://", "wss://") + "/api/websocket"
    get = {"type": "lovelace/config", "url_path": args.dashboard}
    (config,) = asyncio.run(ws_call(ws_url, token, [get]))

    section = config["views"][0]["sections"][args.section]
    cards = section["cards"]
    if any(c.get("entity") == args.entity for c in cards):
        print(f"{args.entity} is already on the board - nothing to do.")
        return

    tile = {"type": "tile", "entity": args.entity}
    at = len(cards)
    if args.after:
        for i, c in enumerate(cards):
            if c.get("entity") == args.after:
                at = i + 1
                break
        else:
            sys.exit(f"--after entity {args.after} is not on the board")
    cards.insert(at, tile)

    # HA rewrites the storage file on save, so snapshot it first. Not into
    # .storage/ itself - that is root-owned by the HA container and not
    # writable here - but into the repo's gitignored backups/ dir.
    live = STORAGE / f"lovelace.{args.dashboard.replace('-', '_')}"
    if live.exists():
        backup_dir = REPO / "backups" / "lovelace"
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup = backup_dir / f"{live.name}.{datetime.now():%Y%m%d%H%M%S}"
        shutil.copy2(live, backup)
        print(f"snapshot: {backup.relative_to(REPO)}")

    save = {"type": "lovelace/config/save", "url_path": args.dashboard, "config": config}
    asyncio.run(ws_call(ws_url, token, [save]))
    print(f"added {args.entity} at position {at} of section {args.section}.")


if __name__ == "__main__":
    main()
