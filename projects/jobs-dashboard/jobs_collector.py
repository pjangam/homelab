#!/usr/bin/env python3
"""Export this host's jobs (jobs.toml) to Prometheus via node-exporter's
textfile collector. Runs every minute as the job-jobs-collector timer.

Per job it reads systemd's own record of the last run (start, end, exit
status, CPU), the peak memory record_run.sh saved, and the timer's next run.
When it sees a run it has not seen before, it appends it to the job's history
(~/.local/state/jobs-dashboard/runs/<job>.jsonl, last 60 days) together with
the peak CPU and SSD temperatures during the run, read from Prometheus. The
p95 and max duration come from that per-run history, never from averaging a
gauge.

    jobs_collector.py            # write the .prom file
    jobs_collector.py --print    # print it instead
"""
import argparse
import json
import math
import os
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from install_jobs import HERE, REPO, load_jobs  # noqa: E402

STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "jobs-dashboard"
TEXTFILE = REPO / "services/node-exporter/textfile/jobs.prom"
PROM = "http://127.0.0.1:9090"
KEEP_DAYS = 60   # Prometheus's 8GB cap keeps about this much too
# hostname -> the `host` label Prometheus puts on that machine's metrics
PROM_HOST = {"xero": "xero", "wol-sender": "wol-pi"}
# sensor -> PromQL selector on node_hwmon_temp_celsius. drivetemp's target0 is
# the Kingston (sda, datapool), target1 the BIWIN boot SSD (checked 2026-11-18).
SENSORS = {
    "xero": {"cpu": 'chip="platform_coretemp_0"',
             "ssd_data": 'chip="target0:0:0_0:0:0:0"',
             "ssd_boot": 'chip="target1:0:0_1:0:0:0"'},
    "wol-pi": {"cpu": 'chip="thermal_thermal_zone0"'},
}
SVC_PROPS = ["ActiveState", "Result", "ExecMainStartTimestamp", "ExecMainExitTimestamp",
             "ExecMainStatus", "CPUUsageNSec", "ExecMainStartTimestampMonotonic",
             "ExecMainExitTimestampMonotonic"]


def show(unit, props):
    """systemctl --user show, timestamps in UTC so they parse without tz guessing."""
    out = subprocess.run(["systemctl", "--user", "show", unit, "-p", ",".join(props)],
                         capture_output=True, text=True, env={**os.environ, "TZ": "UTC"}).stdout
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def ts(value):
    """'Wed 2026-11-18 06:57:01 UTC' -> unix seconds, or None."""
    if not value or value == "n/a":
        return None
    try:
        return datetime.strptime(value, "%a %Y-%m-%d %H:%M:%S %Z").replace(
            tzinfo=timezone.utc).timestamp()
    except ValueError:
        return None


def num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def peak_temps(host, start, end):
    """Max of each sensor over [start, end] from Prometheus; {} if unreachable."""
    temps = {}
    window = max(10, math.ceil(end - start) + 5)   # a 5s scrape needs >=1 sample
    for name, sel in SENSORS.get(host, {}).items():
        q = f'max(max_over_time(node_hwmon_temp_celsius{{host="{host}",{sel}}}[{window}s]))'
        url = f"{PROM}/api/v1/query?" + urllib.parse.urlencode({"query": q, "time": end + 5})
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                res = json.load(r)["data"]["result"]
            if res:
                temps[name] = float(res[0]["value"][1])
        except Exception:
            return {}
    return temps


def quantile(values, q):
    """Nearest-rank quantile of a list (no interpolation)."""
    v = sorted(values)
    return v[min(len(v) - 1, max(0, math.ceil(q * len(v)) - 1))]


def update_history(name, run, now, enrich=None):
    """Append run if new (after enrich(run) adds to it); return the runs of the last KEEP_DAYS."""
    path = STATE / "runs" / f"{name}.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    runs = []
    if path.exists():
        for line in path.read_text().splitlines():
            try:
                runs.append(json.loads(line))
            except ValueError:
                pass
    cutoff = now - KEEP_DAYS * 86400
    fresh = [r for r in runs if r["end"] >= cutoff]
    is_new = run is not None and not any(r["start"] == run["start"] for r in runs[-50:])
    if is_new:
        if enrich:
            enrich(run)
        fresh.append(run)
    # Every-minute jobs keep ~86k runs: append the new one and rewrite the
    # file only once a day, when the oldest run is a day past the cutoff.
    if runs and runs[0]["end"] < cutoff - 86400:
        tmp = path.with_suffix(".tmp")
        tmp.write_text("".join(json.dumps(r) + "\n" for r in fresh))
        os.replace(tmp, path)
    elif is_new:
        with path.open("a") as f:
            f.write(json.dumps(run) + "\n")
    return fresh


def esc(s):
    return str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def collect(host, jobs, now, temps_fn=peak_temps):
    lines = {}

    def m(metric, help_, labels, value):
        if value is None:
            return
        block = lines.setdefault(metric, [f"# HELP {metric} {help_}", f"# TYPE {metric} gauge"])
        lab = ",".join(f'{k}="{esc(v)}"' for k, v in labels.items())
        block.append(f"{metric}{{{lab}}} {format(value, '.15g') if isinstance(value, float) else value}")

    boot = time.time() - float(Path("/proc/uptime").read_text().split()[0])
    for j in jobs:
        name, unit = j["name"], f"job-{j['name']}"
        svc = show(f"{unit}.service", SVC_PROPS)
        tmr = show(f"{unit}.timer", ["NextElapseUSecRealtime", "ActiveState"])
        start, end = ts(svc.get("ExecMainStartTimestamp")), ts(svc.get("ExecMainExitTimestamp"))
        # the collector always finds itself mid-run; counting that would shade every minute
        running = (svc.get("ActiveState") in ("activating", "deactivating")
                   and name != "jobs-collector")
        L = {"name": name}  # not "job": Prometheus uses that for the scrape job
        m("homelab_job_info", "Static facts about a job from jobs.toml (value 1)",
          {**L, "unit": unit, "schedule": j["on_calendar"], "desc": j["desc"], "log": j["log"],
           "timer": tmr.get("ActiveState", "")}, 1)
        m("homelab_job_next_run_timestamp_seconds", "When the timer fires next",
          L, ts(tmr.get("NextElapseUSecRealtime")))
        m("homelab_job_running", "1 while the job runs", L, int(running))
        m("homelab_job_last_start_timestamp_seconds", "Start of the latest run (may be running)",
          L, start)
        # started, not running, never finished: killed by a reboot or power loss
        interrupted = bool(start and not running and (end is None or end < start) and start < boot)
        m("homelab_job_interrupted", "1 if the latest run never finished (host went down)",
          L, int(interrupted))

        run = None
        if start and end and end >= start and not running:
            rec = (STATE / f"{unit}.service.run")
            mem = None
            if rec.exists():
                parts = rec.read_text().split()
                if len(parts) >= 2 and num(parts[0]) and num(parts[0]) >= end - 5:
                    mem = num(parts[1])
            status = int(num(svc.get("ExecMainStatus")) or 0)
            cpu = num(svc.get("CPUUsageNSec"))
            # the wall-clock timestamps are whole seconds; the monotonic ones are microseconds
            m0, m1 = num(svc.get("ExecMainStartTimestampMonotonic")), num(svc.get("ExecMainExitTimestampMonotonic"))
            dur = (m1 - m0) / 1e6 if m0 and m1 and m1 >= m0 else end - start
            run = {"start": start, "end": end, "duration": dur, "exit": status,
                   "ok": svc.get("Result") == "success",
                   "cpu": cpu / 1e9 if cpu is not None and cpu < 2**63 else None,
                   "mem": mem if mem is not None and not math.isnan(mem) else None}
        def add_temps(r):   # once per run, then kept in the history
            r["temps"] = temps_fn(PROM_HOST.get(host, host), r["start"], r["end"])
        runs = update_history(name, run, now, add_temps)
        last = max(runs, key=lambda r: r["start"]) if runs else None
        if last:
            m("homelab_job_last_end_timestamp_seconds", "End of the latest finished run", L, last["end"])
            m("homelab_job_last_duration_seconds", "Duration of the latest finished run", L,
              float(last["duration"]))
            m("homelab_job_last_exit_code", "Exit status of the latest finished run", L, last["exit"])
            m("homelab_job_last_ok", "1 if the latest finished run succeeded (ok_codes count)",
              L, int(last["ok"]))
            m("homelab_job_last_cpu_seconds", "CPU time of the latest run, whole process tree",
              L, last.get("cpu"))
            m("homelab_job_last_memory_peak_bytes", "Peak memory of the latest run's cgroup",
              L, last.get("mem"))
            for sensor, c in (last.get("temps") or {}).items():
                m("homelab_job_last_peak_temp_celsius", "Hottest reading during the latest run",
                  {**L, "sensor": sensor}, c)
            ok = [r for r in runs if r["ok"]]
            fails = 0
            for r in sorted(runs, key=lambda r: r["start"], reverse=True):
                if r["ok"]:
                    break
                fails += 1
            m("homelab_job_consecutive_failures", "Failed runs in a row, newest first", L, fails)
            if ok:
                m("homelab_job_last_success_timestamp_seconds", "End of the latest successful run",
                  L, max(r["end"] for r in ok))
            durs = [r["duration"] for r in runs]
            m("homelab_job_runs", f"Runs recorded in the last {KEEP_DAYS} days", L, len(durs))
            m("homelab_job_duration_max_seconds", f"Longest run in the last {KEEP_DAYS} days",
              L, float(max(durs)))
            if len(durs) >= 20:   # a p95 of a handful of runs is just the max
                m("homelab_job_duration_p95_seconds", f"p95 run time over {KEEP_DAYS} days",
                  L, float(quantile(durs, 0.95)))
    m("homelab_jobs_collector_timestamp_seconds", "When jobs_collector.py last wrote this file",
      {"host": host}, now)
    return "\n".join(l for block in lines.values() for l in block) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--print", action="store_true")
    a = ap.parse_args()
    host = socket.gethostname()
    text = collect(host, load_jobs(HERE / "jobs.toml", host), time.time())
    if a.print:
        sys.stdout.write(text)
        return
    TEXTFILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = TEXTFILE.with_suffix(".prom.tmp")
    tmp.write_text(text)
    os.replace(tmp, TEXTFILE)


if __name__ == "__main__":
    main()
