#!/usr/bin/env python3
"""Home as a UI-editable (storage-mode) dashboard, with git as its record.

A YAML-mode dashboard cannot be edited from the UI ("The edit UI is not
available when in YAML mode"), and the point of Home is to be Overview's
content with edits made in the browser. So Home is a storage-mode dashboard,
living in the gitignored HOMEASSISTANT_CONFIG/.storage/, and
dashboards/home.yaml is its tracked copy:

  ui_dashboard.py create   # make /dashboard-home from dashboards/home.yaml
  ui_dashboard.py export   # after editing in the UI: write it back to home.yaml, then commit
  ui_dashboard.py restore  # push home.yaml over the live dashboard (e.g. after a rebuild)

Goes through the websocket API, so no HA restart is needed for any of them.
Needs HA_TOKEN (read from .env.healthcheck if not set).
"""
import asyncio
import json
import os
import sys
from pathlib import Path

import websockets
import yaml

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
HOME_YAML = HERE / "dashboards" / "home.yaml"
URL_PATH = "dashboard-home"
HEADER = """\
# Home - tracked copy of the storage-mode (UI-editable) Home dashboard at
# /dashboard-home. Started 2026-09-22 as a verbatim copy of Overview.
# Edit in the HA UI, then `projects/ha-dashboard/ui_dashboard.py export` and
# commit; `ui_dashboard.py restore` pushes this file back into HA.
"""


def token():
    if os.environ.get("HA_TOKEN"):
        return os.environ["HA_TOKEN"]
    for line in (REPO / ".env.healthcheck").read_text().splitlines():
        if line.startswith("HA_TOKEN="):
            return line.split("=", 1)[1]
    sys.exit("HA_TOKEN not set and not in .env.healthcheck")


async def ws_call(messages):
    """Open one authenticated session and run each message in order."""
    url = os.environ.get("HA_URL", "http://localhost:8123").replace("http", "ws", 1) + "/api/websocket"
    results = []
    async with websockets.connect(url, max_size=None) as ws:
        json.loads(await ws.recv())
        await ws.send(json.dumps({"type": "auth", "access_token": token()}))
        auth = json.loads(await ws.recv())
        if auth.get("type") != "auth_ok":
            sys.exit(f"HA rejected the token: {auth}")
        for i, msg in enumerate(messages, start=1):
            await ws.send(json.dumps({"id": i, **msg}))
            while True:
                reply = json.loads(await ws.recv())
                if reply.get("id") == i and reply.get("type") == "result":
                    if not reply.get("success"):
                        sys.exit(f"HA refused {msg['type']}: {reply.get('error')}")
                    results.append(reply.get("result"))
                    break
    return results


def call(*messages):
    return asyncio.run(ws_call(list(messages)))


def load_home_yaml():
    return yaml.safe_load(HOME_YAML.read_text())


def save(config):
    call({"type": "lovelace/config/save", "url_path": URL_PATH, "config": config})


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "create":
        (dashboards,) = call({"type": "lovelace/dashboards/list"})
        if any(d["url_path"] == URL_PATH for d in dashboards):
            sys.exit(f"{URL_PATH} already exists as a storage dashboard - use restore")
        call({"type": "lovelace/dashboards/create", "url_path": URL_PATH, "title": "Home",
              "icon": "mdi:home-outline", "show_in_sidebar": True, "require_admin": False,
              "mode": "storage"})
        save(load_home_yaml())
        print(f"created /{URL_PATH} from {HOME_YAML.relative_to(REPO)}")
    elif cmd == "restore":
        save(load_home_yaml())
        print(f"pushed {HOME_YAML.relative_to(REPO)} to /{URL_PATH}")
    elif cmd == "export":
        (config,) = call({"type": "lovelace/config", "url_path": URL_PATH})
        HOME_YAML.write_text(HEADER + yaml.safe_dump(config, sort_keys=False, allow_unicode=True, width=100))
        print(f"wrote {HOME_YAML.relative_to(REPO)} - review with git diff and commit")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
