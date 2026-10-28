#!/usr/bin/env python3
"""Show each ESPHome voice satellite as HA sees it: config entry state,
area, and the live assist_satellite / select / light entities.

Run on xero, from the repo root:
    set -a; . ./.env.healthcheck; set +a
    projects/voice-assistant/satellite_status.py
"""
from ha_ws import call_many


def main():
    entries, devices, entities, states = call_many([
        {"type": "config_entries/get", "domain": "esphome"},
        {"type": "config/device_registry/list"},
        {"type": "config/entity_registry/list"},
        {"type": "get_states"},
    ])
    state = {s["entity_id"]: s for s in states}
    for entry in entries:
        print(f"{entry['title']}: entry {entry['state']}"
              f"{', disabled by ' + entry['disabled_by'] if entry.get('disabled_by') else ''}")
        for dev in (d for d in devices if entry["entry_id"] in d.get("config_entries", [])):
            print(f"  device {dev.get('name_by_user') or dev.get('name')}, area {dev.get('area_id')}, "
                  f"firmware {dev.get('sw_version')}")
            for ent in sorted((e for e in entities if e.get("device_id") == dev["id"]),
                              key=lambda e: e["entity_id"]):
                s = state.get(ent["entity_id"])
                when = s["last_changed"][:19] if s else ""
                print(f"    {ent['entity_id']:58} {s['state'] if s else '(no state)':14} {when}")


if __name__ == "__main__":
    main()
