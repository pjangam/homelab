#!/usr/bin/env python3
"""Add a tile to the Stats dashboard without restarting Home Assistant.

Storage-mode dashboards live in HOMEASSISTANT_CONFIG/.storage/ but HA holds
them in memory, so hand-editing that JSON does nothing until HA restarts -
and on 2026-09-11 restarting HA for exactly that reason is what knocked the
MirAIe AC entity out for 37 minutes (the AC's availability is published
retain=false, so a fresh HA has no availability value and pins the entity
`unavailable`; see projects/miraie-ac/fix_miraie_ac.sh). Going through the websocket API
instead updates the live config and writes the file, with no restart and
nothing else disturbed.

Idempotent: adding a tile that is already on the board changes nothing.

  projects/healthcheck/add_stats_dashboard_tile.py binary_sensor.foo
  projects/healthcheck/add_stats_dashboard_tile.py binary_sensor.foo --after binary_sensor.bar
  projects/healthcheck/add_stats_dashboard_tile.py sensor.foo --section-title "wol Pi"
  projects/healthcheck/add_stats_dashboard_tile.py sensor.new --replace sensor.old

--section-title picks the section by its heading, creating it (as the last
section) if there is none. A tile already in another section is moved
there, so this also re-homes existing tiles.

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

REPO = Path(__file__).resolve().parent.parent.parent
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
    ap.add_argument("--section-title", help="the section whose heading is this; created if missing")
    ap.add_argument("--after", help="place the new tile directly after this entity")
    ap.add_argument("--replace", help="put the tile where this entity's tile is, removing that one")
    ap.add_argument("--url", default=os.environ.get("HA_URL", "http://localhost:8123"))
    args = ap.parse_args()

    token = os.environ.get("HA_TOKEN")
    if not token:
        sys.exit("HA_TOKEN not set - source .env.healthcheck first")

    ws_url = args.url.replace("http://", "ws://").replace("https://", "wss://") + "/api/websocket"
    get = {"type": "lovelace/config", "url_path": args.dashboard}
    (config,) = asyncio.run(ws_call(ws_url, token, [get]))

    sections = config["views"][0]["sections"]
    replaced = None
    if args.replace:
        for idx, sec in enumerate(sections):
            for i, c in enumerate(sec.get("cards", [])):
                if c.get("type") == "tile" and c.get("entity") == args.replace:
                    replaced = (idx, i)
        if replaced is None:
            sys.exit(f"--replace entity {args.replace} is not on the board")
        if any(c.get("entity") == args.entity for sec in sections for c in sec.get("cards", [])):
            sys.exit(f"{args.entity} is already on the board - remove it first")
        idx, i = replaced
        sections[idx]["cards"][i] = {**sections[idx]["cards"][i], "entity": args.entity}
        args.section = idx
    elif args.section_title:
        for idx, sec in enumerate(sections):
            if any(c.get("type") == "heading" and c.get("heading") == args.section_title
                   for c in sec.get("cards", [])):
                break
        else:
            sections.append({"type": "grid", "cards": [
                {"type": "heading", "heading": args.section_title}]})
            idx = len(sections) - 1
            print(f"created section {args.section_title!r}.")
        args.section = idx
    section = sections[args.section]
    cards = section["cards"]
    if replaced:
        pass
    elif any(c.get("entity") == args.entity for c in cards):
        print(f"{args.entity} is already in that section - nothing to do.")
        return
    moved_from = None
    for idx, sec in enumerate([] if replaced else sections):
        if idx == args.section:
            continue
        for c in list(sec.get("cards", [])):
            if c.get("type") == "tile" and c.get("entity") == args.entity:
                sec["cards"].remove(c)
                moved_from = idx

    tile = {"type": "tile", "entity": args.entity}
    at = replaced[1] if replaced else len(cards)
    if replaced:
        pass
    elif args.after:
        for i, c in enumerate(cards):
            if c.get("entity") == args.after:
                at = i + 1
                break
        else:
            sys.exit(f"--after entity {args.after} is not on the board")
    if not replaced:
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
    how = (f"replaced {args.replace}" if replaced else
           f"moved from section {moved_from}" if moved_from is not None else "added")
    print(f"{how}: {args.entity} at position {at} of section {args.section}.")


if __name__ == "__main__":
    main()
