#!/usr/bin/env python3
"""Per-hour count of times each Wi-Fi device went `unavailable` in HA.

HA marks an ESPHome/WLED device unavailable when its API connection drops, so
this is a cheap Wi-Fi stability log for the 2.4GHz-only devices - no extra
logger needed. Devices on the router and on the extender failing in the same
hour points at the router's radio (docs/wifi.md).

Usage (on xero, times in IST):
  set -a; . ./.env.healthcheck; set +a
  python3 tools/ha-diag/wifi_drops.py 2026-11-06T18:00 2026-11-07T00:00
  python3 tools/ha-diag/wifi_drops.py 2026-11-06T18:00 2026-11-07T00:00 --times
"""
import argparse
import collections
import datetime as dt
import json
import os
import urllib.parse
import urllib.request

IST = dt.timezone(dt.timedelta(hours=5, minutes=30))
HA = "http://localhost:8123"

# Entity -> (short name, which access point it normally uses)
DEVICES = {
    "light.diwali_lights": ("wled-door", "router"),
    "assist_satellite.voice_living_room_assist_satellite": ("sat-living", "router"),
    "assist_satellite.voice_satellite_assist_satellite": ("sat-bedroom", "extender?"),
    "switch.smart_switch_bench_relay": ("kandil", "extender"),
}


def history(entity, start, end):
    q = urllib.parse.urlencode({
        "filter_entity_id": entity, "end_time": end.isoformat(),
        "minimal_response": "", "no_attributes": "",
    })
    req = urllib.request.Request(
        f"{HA}/api/history/period/{urllib.parse.quote(start.isoformat())}?{q}",
        headers={"Authorization": f"Bearer {os.environ['HA_TOKEN']}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    return data[0] if data else []


def main():
    p = argparse.ArgumentParser()
    p.add_argument("start", help="IST, e.g. 2026-11-06T18:00")
    p.add_argument("end", help="IST, e.g. 2026-11-07T00:00")
    p.add_argument("--times", action="store_true", help="also list each drop")
    a = p.parse_args()
    start = dt.datetime.fromisoformat(a.start).replace(tzinfo=IST)
    end = dt.datetime.fromisoformat(a.end).replace(tzinfo=IST)

    counts = {}
    hours = set()
    for ent, (name, _) in DEVICES.items():
        c = collections.Counter()
        for s in history(ent, start, end):
            if s["state"] != "unavailable":
                continue
            t = dt.datetime.fromisoformat(s["last_changed"]).astimezone(IST)
            if t < start:  # the window's opening state, not a drop
                continue
            c[t.strftime("%d %H:00")] += 1
            if a.times:
                print(f"  {t:%d %H:%M:%S}  {name}")
        counts[name] = c
        hours |= set(c)

    names = [n for n, _ in DEVICES.values()]
    print(f"{'hour (IST)':12} " + " ".join(f"{n:>11}" for n in names))
    print(f"{'AP':12} " + " ".join(f"{ap:>11}" for _, ap in DEVICES.values()))
    for h in sorted(hours):
        print(f"{h:12} " + " ".join(f"{counts[n][h]:>11}" for n in names))
    print(f"{'total':12} " + " ".join(f"{sum(counts[n].values()):>11}" for n in names))


if __name__ == "__main__":
    main()
