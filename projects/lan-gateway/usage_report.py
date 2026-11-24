#!/usr/bin/env python3
"""Print internet usage per LAN device from Prometheus, the numbers behind the
Grafana "Network usage (per device)" dashboard, for reading in a terminal.

    projects/lan-gateway/usage_report.py              # last 7 days, today, top hours
    projects/lan-gateway/usage_report.py --days 30

Per-device counters only (homelab_lan_device_bytes_total, from 2026-10-31
08:31); older per-IP history is left out. Devices are named as today.
"""
import argparse
import json
import urllib.parse
import urllib.request

PROM = "http://127.0.0.1:9090/api/v1/query"
DEV = "homelab_lan_device_bytes_total"


def q(expr):
    url = PROM + "?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)["data"]["result"]


def named(inner):
    return (f"sum by (device, direction) (({inner}) * on (id) group_left (device) homelab_lan_device_name"
            f' or on (id) label_replace({inner}, "device", "$1", "id", "(.*)"))')


def table(title, window, top=20):
    rows = {}
    for s in q(named(f"increase({DEV}[{window}])")):
        d = s["metric"].get("device", "?")
        rows.setdefault(d, {})[s["metric"].get("direction", "?")] = float(s["value"][1])
    print(f"\n== {title}")
    tot = {"down": 0, "up": 0}
    for d, v in sorted(rows.items(), key=lambda kv: -sum(kv[1].values()))[:top]:
        print(f"  {v.get('down', 0) / 1e9:8.2f} GB down  {v.get('up', 0) / 1e9:7.2f} GB up   {d}")
    for v in rows.values():
        for k in tot:
            tot[k] += v.get(k, 0)
    print(f"  {tot['down'] / 1e9:8.2f} GB down  {tot['up'] / 1e9:7.2f} GB up   TOTAL ({len(rows)} devices)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--days", type=int, default=7)
    a = ap.parse_args()
    table(f"last {a.days} days", f"{a.days}d")
    table("last 24 hours", "24h", 10)
    # busiest hours in the window: per device, the max hourly total
    print(f"\n== busiest single hour per device, last {a.days} days")
    peak = q(f"topk(10, max_over_time(({named(f'increase({DEV}[1h])')})[{a.days}d:1h]))")
    for s in sorted(peak, key=lambda s: -float(s["value"][1])):
        m = s["metric"]
        print(f"  {float(s['value'][1]) / 1e9:7.2f} GB  {m.get('device')} {m.get('direction')}")


if __name__ == "__main__":
    main()
