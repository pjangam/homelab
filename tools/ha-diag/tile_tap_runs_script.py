"""Make every tile for a script on a storage-mode dashboard run it on tap,
instead of opening the more-info popup with its Run button.

Same tap_action / icon_tap_action the AC timer tiles on dashboard-home already
use. Goes through HA's websocket API (lovelace/config + lovelace/config/save)
so HA writes .storage itself - editing the file under a running HA gets
overwritten. Needs aiohttp, so run it with HA's own Python:

  HA_TOKEN=$(grep '^HA_TOKEN=' .env.healthcheck | cut -d= -f2- | tr -d '"')
  docker exec -i -e HA_TOKEN="$HA_TOKEN" homeassistant \
    python3 - dashboard-home script.play_bedroom_track \
    < tools/ha-diag/tile_tap_runs_script.py
"""
import asyncio
import json
import os
import sys

import aiohttp

URL = "ws://localhost:8123/api/websocket"


def patch(node, entity):
    """Walk the config; return how many tiles for `entity` were changed."""
    n = 0
    if isinstance(node, dict):
        if node.get("type") == "tile" and node.get("entity") == entity:
            run = {"action": "perform-action", "perform_action": entity}
            if node.get("tap_action") != run or node.get("icon_tap_action") != run:
                node["tap_action"] = dict(run)
                node["icon_tap_action"] = dict(run)
                n += 1
        for v in node.values():
            n += patch(v, entity)
    elif isinstance(node, list):
        for v in node:
            n += patch(v, entity)
    return n


async def main(url_path, entity):
    async with aiohttp.ClientSession() as s, s.ws_connect(URL) as ws:
        await ws.receive_json()
        await ws.send_json({"type": "auth", "access_token": os.environ["HA_TOKEN"]})
        if (await ws.receive_json())["type"] != "auth_ok":
            raise SystemExit("auth failed")

        await ws.send_json({"id": 1, "type": "lovelace/config", "url_path": url_path})
        config = (await ws.receive_json())["result"]
        changed = patch(config, entity)
        if not changed:
            print(f"{url_path}: no tile for {entity} needed changing")
            return

        await ws.send_json({"id": 2, "type": "lovelace/config/save",
                            "url_path": url_path, "config": config})
        reply = await ws.receive_json()
        if not reply.get("success"):
            raise SystemExit(f"save failed: {json.dumps(reply)}")
        print(f"{url_path}: {changed} tile(s) for {entity} now run it on tap")


asyncio.run(main(sys.argv[1], sys.argv[2]))
