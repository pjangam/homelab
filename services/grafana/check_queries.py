#!/usr/bin/env python3
"""Run every query in the generated dashboards against Prometheus and report
which return no data or an error. $__interval becomes 1m over the last 10 min.
Usage: services/grafana/check_queries.py [prometheus_url]"""
import json, sys, time, urllib.parse, urllib.request
from pathlib import Path

prom = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:9090"
bad = 0
for f in sorted((Path(__file__).resolve().parent / "dashboards").glob("*.json")):
    for p in json.loads(f.read_text())["panels"]:
        for t in p["targets"]:
            q = t["expr"].replace("$__interval", "1m")
            now = int(time.time())
            url = f"{prom}/api/v1/query_range?" + urllib.parse.urlencode(
                {"query": q, "start": now - 600, "end": now, "step": 60})
            try:
                r = json.load(urllib.request.urlopen(url, timeout=20))
                n = len(r["data"]["result"])
                status = f"{n} series" if n else "NO DATA"
            except urllib.error.HTTPError as e:
                status = "ERROR " + json.load(e).get("error", "")[:120]
            if not status.endswith("series"):
                bad += 1
            print(f"{f.stem:10} {p['title'][:38]:38} {t['legendFormat'][:22]:22} {status}")
sys.exit(1 if bad else 0)
