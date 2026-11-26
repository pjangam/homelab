#!/usr/bin/env python3
"""Export this host's jobs (jobs.toml) to Prometheus via node-exporter's
textfile collector. Runs every minute as the job-jobs-collector timer.

Per job it reads systemd's own record of the last run (start, end, exit
status, CPU; one `systemctl show` for all units), the peak memory, RAM and
CPU record_run.sh saved, and the timer's next run. When it sees a run it has
not seen before, it appends it to the job's history
(~/.local/state/jobs-dashboard/runs/<job>.jsonl, last 60 days) together with
the peak CPU and SSD temperatures during the run, read from Prometheus.

The 60-day p50/p95/max of duration, CPU, RAM, busiest second and
temperatures come from that per-run history, never from averaging a gauge.
They are kept in stats.json: maxima, counts and failures are updated with
each new run, the percentiles and per-day CPU totals are recomputed from the
file hourly (one job per collector run), so the history is not re-read
every minute. The collector records its own runs last (record_self).

    jobs_collector.py            # write the .prom file
    jobs_collector.py --print    # print it instead
"""
import argparse
import json
import math
import os
import resource
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
SVC_PROPS = ["Id", "ActiveState", "Result", "ExecMainStartTimestamp", "ExecMainExitTimestamp",
             "ExecMainStatus", "CPUUsageNSec", "ExecMainStartTimestampMonotonic",
             "ExecMainExitTimestampMonotonic", "NextElapseUSecRealtime"]
STATS = STATE / "stats.json"   # per-job summary of the history, see summarize()
RECOMPUTE_S = 3600             # a job's percentiles are recomputed from its file this often
MIN_P = 20                     # a p50/p95 of fewer runs is just noise around the max


def show_all(units, props):
    """One `systemctl --user show` for every unit -> {unit: {prop: value}}.
    Timestamps in UTC so they parse without tz guessing. One call, not two per
    job: each fork of systemctl was most of the collector's CPU."""
    out = subprocess.run(["systemctl", "--user", "show", *units, "-p", ",".join(props)],
                         capture_output=True, text=True, env={**os.environ, "TZ": "UTC"}).stdout
    blocks = {}
    for block in out.split("\n\n"):
        d = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if d.get("Id"):
            blocks[d["Id"]] = d
    return blocks


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


def nearest(sorted_values, q):
    """Nearest-rank quantile of an already sorted list (no interpolation)."""
    v = sorted_values
    return v[min(len(v) - 1, max(0, math.ceil(q * len(v)) - 1))]


def field_values(r):
    """The per-run numbers the stats are taken over, {field: value}, for the
    fields this run counts towards."""
    v = {"duration": r["duration"]}
    for k in ("cpu", "ram", "mem"):
        if r.get(k) is not None:
            v[k] = r[k]
    # under a second there is no 1s sample: the whole-run rate is noise (README Traps)
    if r["duration"] >= 1 and r.get("cpu_max") is not None:
        v["cpu_max"] = r["cpu_max"]
    # a shorter run cannot move a temperature, it only reads whatever else did
    if r["duration"] >= 60:
        for sensor, c in (r.get("temps") or {}).items():
            v[f"temp_{sensor}"] = c
    return v


def summarize(runs, now):
    """Everything the metrics need from a job's history (runs of the last KEEP_DAYS)."""
    runs = sorted(runs, key=lambda r: r["start"])
    vals = {}
    for r in runs:
        for k, x in field_values(r).items():
            vals.setdefault(k, []).append(x)
    fields = {}
    for k, xs in vals.items():
        xs.sort()   # once per field; p50, p95 and max all come from it
        fields[k] = {"n": len(xs), "max": xs[-1]}
        if len(xs) >= MIN_P:
            fields[k]["p50"], fields[k]["p95"] = nearest(xs, 0.5), nearest(xs, 0.95)
    days = {}
    for r in runs:
        if r.get("cpu") is not None:
            d = datetime.fromtimestamp(r["start"]).date().isoformat()   # local (IST) days
            days[d] = days.get(d, 0.0) + r["cpu"]
    fails = 0
    for r in reversed(runs):
        if r["ok"]:
            break
        fails += 1
    ok = [r["end"] for r in runs if r["ok"]]
    return {"computed": now, "fields": fields, "fails": fails,
            "last_success": max(ok) if ok else None, "last": runs[-1] if runs else None,
            "cpu_busiest_day": max(days.values()) if days else None,
            "cpu_last_24h": (sum(r["cpu"] for r in runs if r.get("cpu") is not None
                                 and r["end"] >= now - 86400) if days else None)}


def apply_run(s, run):
    """Fold one new run into a summary without re-reading the history: counts,
    maxima, failures and the latest run stay exact; p50/p95 and the per-day
    CPU totals wait for the next hourly summarize()."""
    for k, x in field_values(run).items():
        f = s["fields"].setdefault(k, {"n": 0, "max": x})
        f["n"] += 1
        f["max"] = max(f["max"], x)
    s["fails"] = 0 if run["ok"] else s["fails"] + 1
    if run["ok"]:
        s["last_success"] = max(run["end"], s["last_success"] or 0)
    s["last"] = run


def history_path(name):
    return STATE / "runs" / f"{name}.jsonl"


def read_history(name, now):
    """The runs of the last KEEP_DAYS. Every-minute jobs keep ~86k runs, so the
    file is appended to and only rewritten without the old runs when its
    oldest run is a day past the cutoff."""
    path = history_path(name)
    runs = []
    if path.exists():
        for line in path.read_text().splitlines():
            try:
                runs.append(json.loads(line))
            except ValueError:
                pass
    cutoff = now - KEEP_DAYS * 86400
    fresh = [r for r in runs if r["end"] >= cutoff]
    if runs and runs[0]["end"] < cutoff - 86400:
        tmp = path.with_suffix(".tmp")
        tmp.write_text("".join(json.dumps(r) + "\n" for r in fresh))
        os.replace(tmp, path)
    return fresh


def append_history(name, run):
    path = history_path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        f.write(json.dumps(run) + "\n")


def load_stats():
    try:
        return json.loads(STATS.read_text())
    except (OSError, ValueError):
        return {}   # missing or torn: every job is summarized from its file again


def save_stats(stats):
    STATS.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATS.with_suffix(".tmp")
    tmp.write_text(json.dumps(stats))
    os.replace(tmp, STATS)


def record(stats, name, run, now, enrich=None):
    """Add run to a job's history and summary if it is new; return the summary.
    A job without a summary is summarized from its file (first run, or after
    stats.json was lost)."""
    s = stats.get(name)
    if s is None:
        runs = read_history(name, now)
        if run is not None and not any(r["start"] == run["start"] for r in runs[-50:]):
            if enrich:
                enrich(run)
            append_history(name, run)
            runs.append(run)
        s = stats[name] = summarize(runs, now)
    elif run is not None and (s["last"] is None or run["start"] > s["last"]["start"]):
        if enrich:
            enrich(run)
        append_history(name, run)
        apply_run(s, run)
    return s


# field -> (metric stem, unit, what one value is)
FIELD_METRICS = {
    "duration": ("duration", "seconds", "run time"),
    "cpu": ("cpu", "seconds", "CPU time of a run, whole process tree"),
    "ram": ("ram", "bytes", "peak RAM of a run (anon: the processes' own memory, no page cache; "
                            "runs under 1s: memory.peak, an upper bound)"),
    "mem": ("memory", "bytes", "peak memory of a run incl. page cache (memory.peak)"),
    "cpu_max": ("cpu_busiest_second", "percent",
                "busiest 1s of a run, % of one core, runs of 1s or more"),
}


def esc(s):
    return str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def collect(host, jobs, now, temps_fn=peak_temps, stats=None):
    lines = {}

    def m(metric, help_, labels, value):
        if value is None:
            return
        block = lines.setdefault(metric, [f"# HELP {metric} {help_}", f"# TYPE {metric} gauge"])
        lab = ",".join(f'{k}="{esc(v)}"' for k, v in labels.items())
        block.append(f"{metric}{{{lab}}} {format(value, '.15g') if isinstance(value, float) else value}")

    if stats is None:
        stats = load_stats()
    names = {j["name"] for j in jobs}
    for gone in set(stats) - names:   # removed from jobs.toml
        del stats[gone]
    # Percentiles move slowly: refresh at most one job per run, the stalest,
    # so the hourly re-reads of the big history files are spread out.
    stale = [n for n, s in stats.items() if now - s["computed"] >= RECOMPUTE_S]
    if stale:
        n = min(stale, key=lambda n: stats[n]["computed"])
        stats[n] = summarize(read_history(n, now), now)

    boot = time.time() - float(Path("/proc/uptime").read_text().split()[0])
    units = show_all([f"job-{j['name']}.{t}" for j in jobs for t in ("service", "timer")], SVC_PROPS)
    for j in jobs:
        name, unit = j["name"], f"job-{j['name']}"
        svc = units.get(f"{unit}.service", {})
        tmr = units.get(f"{unit}.timer", {})
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
            mem = cpu_max = ram = None
            if rec.exists():
                # "<time> <peak bytes> <peak cpu %> <exit> <peak ram>" (record_run.sh)
                parts = rec.read_text().split()
                if len(parts) >= 2 and num(parts[0]) and num(parts[0]) >= end - 5:
                    mem = num(parts[1])
                    cpu_max = num(parts[2]) if len(parts) >= 4 else None
                    ram = num(parts[4]) if len(parts) >= 5 else None
            status = int(num(svc.get("ExecMainStatus")) or 0)
            cpu = num(svc.get("CPUUsageNSec"))
            # the wall-clock timestamps are whole seconds; the monotonic ones are microseconds
            m0, m1 = num(svc.get("ExecMainStartTimestampMonotonic")), num(svc.get("ExecMainExitTimestampMonotonic"))
            dur = (m1 - m0) / 1e6 if m0 and m1 and m1 >= m0 else end - start
            clean = lambda x: x if x is not None and not math.isnan(x) else None  # noqa: E731
            run = {"start": start, "end": end, "duration": dur, "exit": status,
                   "ok": svc.get("Result") == "success",
                   "cpu": cpu / 1e9 if cpu is not None and cpu < 2**63 else None,
                   "mem": clean(mem), "ram": clean(ram), "cpu_max": clean(cpu_max)}

        def add_temps(r):   # once per run, then kept in the history
            r["temps"] = temps_fn(PROM_HOST.get(host, host), r["start"], r["end"])
        s = record(stats, name, run, now, add_temps)
        last = s["last"]
        if not last:
            continue
        m("homelab_job_last_end_timestamp_seconds", "End of the latest finished run", L, last["end"])
        m("homelab_job_last_duration_seconds", "Duration of the latest finished run", L,
          float(last["duration"]))
        m("homelab_job_last_exit_code", "Exit status of the latest finished run", L, last["exit"])
        m("homelab_job_last_ok", "1 if the latest finished run succeeded (ok_codes count)",
          L, int(last["ok"]))
        m("homelab_job_last_cpu_seconds", "CPU time of the latest run, whole process tree",
          L, last.get("cpu"))
        m("homelab_job_last_cpu_max_percent",
          "Highest 1s CPU use of the latest run, % of one core (100 = one full core)",
          L, last.get("cpu_max"))
        m("homelab_job_last_memory_peak_bytes", "Peak memory of the latest run's cgroup, incl. page cache",
          L, last.get("mem"))
        m("homelab_job_last_ram_peak_bytes", "Peak RAM (anon) of the latest run", L, last.get("ram"))
        for sensor, c in (last.get("temps") or {}).items():
            m("homelab_job_last_peak_temp_celsius", "Hottest reading during the latest run",
              {**L, "sensor": sensor}, c)
        m("homelab_job_consecutive_failures", "Failed runs in a row, newest first", L, s["fails"])
        m("homelab_job_last_success_timestamp_seconds", "End of the latest successful run",
          L, s["last_success"])
        f = s["fields"]
        m("homelab_job_runs", f"Runs recorded in the last {KEEP_DAYS} days", L,
          f.get("duration", {}).get("n", 0))
        for k, st in f.items():
            if k.startswith("temp_"):
                stem, unit_, what, labels = ("temp", "celsius", "hottest reading during a run of 60s or more",
                                             {**L, "sensor": k[5:]})
            else:
                stem, unit_, what = FIELD_METRICS[k]
                labels = L
            for q in ("max", "p95", "p50"):
                if q in st:
                    m(f"homelab_job_{stem}_{q}_{unit_}", f"{q} over {KEEP_DAYS} days of: {what}",
                      labels, float(st[q]))
        m("homelab_job_cpu_busiest_day_seconds",
          f"CPU seconds of the job's busiest day (IST) in the last {KEEP_DAYS} days", L, s["cpu_busiest_day"])
        m("homelab_job_cpu_last_24h_seconds", "CPU seconds of the job's runs in the last 24h (hourly)",
          L, s["cpu_last_24h"])
        m("homelab_job_stats_timestamp_seconds", "When the job's p50/p95/per-day CPU were last recomputed",
          L, s["computed"])
    m("homelab_jobs_collector_timestamp_seconds", "When jobs_collector.py last wrote this file",
      {"host": host}, now)
    save_stats(stats)
    return "\n".join(l for block in lines.values() for l in block) + "\n"


def record_self(t0, m0):
    """The collector's own run. systemd never shows it finished (it is always
    the run in progress when the collector looks), so it records itself last,
    with its CPU and memory from getrusage (children = the systemctl call)."""
    me, kids = resource.getrusage(resource.RUSAGE_SELF), resource.getrusage(resource.RUSAGE_CHILDREN)
    peak = max(me.ru_maxrss, kids.ru_maxrss) * 1024.0   # KiB on Linux; RSS, no cache
    run = {"start": t0, "end": time.time(), "duration": time.monotonic() - m0, "exit": 0, "ok": True,
           "cpu": me.ru_utime + me.ru_stime + kids.ru_utime + kids.ru_stime,
           "mem": peak, "ram": peak, "cpu_max": None, "temps": {}}
    stats = load_stats()
    record(stats, "jobs-collector", run, run["end"])
    save_stats(stats)


def main():
    t0, m0 = time.time(), time.monotonic()
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--print", action="store_true")
    a = ap.parse_args()
    host = socket.gethostname()
    jobs = load_jobs(HERE / "jobs.toml", host)
    text = collect(host, jobs, time.time())
    if a.print:
        sys.stdout.write(text)
        return
    TEXTFILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = TEXTFILE.with_suffix(".prom.tmp")
    tmp.write_text(text)
    os.replace(tmp, TEXTFILE)
    if any(j["name"] == "jobs-collector" for j in jobs):
        record_self(t0, m0)


if __name__ == "__main__":
    main()
