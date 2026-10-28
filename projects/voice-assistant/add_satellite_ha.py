#!/usr/bin/env python3
"""Add an ESPHome voice satellite to Home Assistant and put it in its room.

HA discovers these boards over mDNS, but the discovery still has to be
confirmed by hand with the board's noise encryption key - so after flashing a
new satellite there is always a click-through left. This does that over the
API instead, and sets the device's area in the same run (the room a satellite
serves is its HA area, nothing in the firmware).

Idempotent: if the host is already a config entry it only fixes the area
(it does not enable a disabled entry - see satellite_status.py).

Run on xero, from the repo root:
    set -a; . ./.env.healthcheck; set +a
    projects/voice-assistant/add_satellite_ha.py 192.168.1.126 api_key_living_room living_room

The key argument is the *name* of the key in esphome/secrets.yaml, never the
key itself, so the secret stays in the gitignored file and out of shell
history. Area is an HA area_id (see `ha_ws.py '{"type":
"config/area_registry/list"}'`); omit it to leave the area unset.
"""
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

from ha_ws import call, call_many

HA_HTTP = os.environ.get("HA_HTTP", "http://localhost:8123")
SECRETS = pathlib.Path(__file__).resolve().parent / "esphome" / "secrets.yaml"


def http(method, path, body=None):
    req = urllib.request.Request(
        HA_HTTP + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {os.environ['HA_TOKEN']}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} -> HTTP {e.code}: {e.read()[:300].decode()}")


def secret(name):
    for line in SECRETS.read_text().splitlines():
        key, _, value = line.partition(":")
        if key.strip() == name:
            return value.strip().strip('"').strip("'")
    raise SystemExit(f"{name} not found in {SECRETS}")


def existing_entry(host):
    """The esphome config entry already pointing at this host, if any."""
    for entry in http("GET", "/api/config/config_entries/entry?domain=esphome"):
        # The entry's host is not in the REST payload, so match on the title
        # HA builds from the device name, then confirm through the device
        # registry below. Title is the esphome `name:` (e.g. voice-living-room).
        yield entry


def entry_for_host(host):
    """The esphome entry for a host. Read from HA's own store, because no API
    returns an entry's host."""
    store = pathlib.Path(__file__).resolve().parents[2] / "HOMEASSISTANT_CONFIG" / ".storage" / "core.config_entries"
    for entry in json.loads(store.read_text())["data"]["entries"]:
        if entry["domain"] == "esphome" and entry["data"].get("host") == host:
            return entry["entry_id"]
    raise SystemExit(f"HA says {host} is configured, but no esphome entry in {store} has that host")


def set_area(entry_id, area_id):
    devices = call({"type": "config/device_registry/list"})
    mine = [d for d in devices if entry_id in d.get("config_entries", [])]
    if not mine:
        print(f"warning: no device found for entry {entry_id}; area not set")
        return
    for d in mine:
        if d.get("area_id") == area_id:
            print(f"area already {area_id} for {d.get('name')}")
            continue
        call_many([{"type": "config/device_registry/update",
                    "device_id": d["id"], "area_id": area_id}])
        print(f"area of {d.get('name')} set to {area_id}")


def main():
    if not 2 <= len(sys.argv) - 1 <= 3:
        raise SystemExit(__doc__)
    host, key_name = sys.argv[1], sys.argv[2]
    area_id = sys.argv[3] if len(sys.argv) > 3 else None

    before = {e["entry_id"]: e["title"] for e in existing_entry(host)}

    flow = http("POST", "/api/config/config_entries/flow",
                {"handler": "esphome", "show_advanced_options": False})
    flow_id = flow["flow_id"]
    step = http("POST", f"/api/config/config_entries/flow/{flow_id}",
                {"host": host, "port": 6053})
    if step.get("step_id") in ("encryption_key", "authenticate"):
        step = http("POST", f"/api/config/config_entries/flow/{flow_id}",
                    {"noise_psk": secret(key_name)})
    if step.get("type") == "abort" and str(step.get("reason")).startswith("already_configured"):
        # HA ends an aborted flow by itself, so there is nothing to delete.
        # Its entry may also be disabled - this neither enables nor adds it.
        entry_id = entry_for_host(host)
        print(f"{host} is already entry {entry_id}")
        if area_id:
            set_area(entry_id, area_id)
        return
    if step.get("type") != "create_entry":
        if step.get("type") != "abort":
            http("DELETE", f"/api/config/config_entries/flow/{flow_id}")
        raise SystemExit(f"flow did not finish: step={step.get('step_id')} "
                         f"reason={step.get('reason')} errors={step.get('errors')}")

    entry_id = step["result"]["entry_id"]
    print(f"added {step['result']['title']} ({host}) as entry {entry_id}"
          f"{' - was already present' if entry_id in before else ''}")
    if area_id:
        set_area(entry_id, area_id)


if __name__ == "__main__":
    main()
