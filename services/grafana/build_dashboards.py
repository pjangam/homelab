#!/usr/bin/env python3
"""Generate the Grafana dashboards in services/grafana/dashboards/.

The JSON there is provisioned read-in by Grafana (see provisioning/), so this
script is the source of truth: change it, run it, commit both. Grafana picks
the files up within a minute, no restart.

Every panel shows the max and/or p95 of each graph interval, never an
average (user's rule, 2026-10-09): Prometheus scrapes every 5s, a counter
becomes a 5s rate with irate(), and each point on a graph is the max or p95
of the 5s values inside that point's interval ($__interval). Zoomed out to
a week, a point covers ~10 minutes and still shows the worst 5 seconds in it.
Gauges (temperature, memory, disk) get max_over_time the same way.
"""
import json
import tomllib
from pathlib import Path

import yaml

OUT = Path(__file__).resolve().parent / "dashboards"
DS = {"type": "prometheus", "uid": "prometheus"}

_ids = iter(range(1, 1000))


def counter_rate(metric_expr):
    """A per-second rate over the last two 5s samples."""
    return f"irate({metric_expr}[30s])"


def peak(expr):
    """(max, p95) of expr's 5s values within each graph point's interval."""
    return (f"max_over_time(({expr})[$__interval:5s])",
            f"quantile_over_time(0.95, ({expr})[$__interval:5s])")


def panel(title, targets, unit, x, y, w=12, h=8, max_=None, desc="", stack=False):
    p = {
        "id": next(_ids), "type": "timeseries", "title": title, "description": desc,
        "datasource": DS, "interval": "$res",
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {
            "defaults": {
                "unit": unit, "min": 0,
                "custom": {"lineWidth": 1, "fillOpacity": 10 if stack else 0, "showPoints": "never",
                           "spanNulls": True,
                           "stacking": {"mode": "normal" if stack else "none"}},
            },
            "overrides": [
                # p95 lines dashed so max and p95 of the same series read as a pair.
                {"matcher": {"id": "byRegexp", "options": ".*p95.*"},
                 "properties": [{"id": "custom.lineStyle", "value": {"fill": "dash", "dash": [6, 4]}}]},
            ],
        },
        "options": {
            "legend": {"displayMode": "table", "placement": "right", "calcs": ["max", "lastNotNull"],
                       "sortBy": "Max", "sortDesc": True},
            "tooltip": {"mode": "multi", "sort": "desc", "hideZeros": True},
        },
        "targets": [{"datasource": DS, "refId": chr(65 + i), "expr": e, "legendFormat": l}
                    for i, (e, l) in enumerate(targets)],
    }
    if max_ is not None:
        p["fieldConfig"]["defaults"]["max"] = max_
    return p


def stat(title, expr, legend, unit, x, y, w=12, h=4, desc=""):
    """One number per series, as of the dashboard's end time."""
    return {
        "id": next(_ids), "type": "stat", "title": title, "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": {"unit": unit, "color": {"mode": "fixed", "fixedColor": "text"}}},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "values": False},
                    "colorMode": "none", "graphMode": "none", "textMode": "value_and_name"},
        "targets": [{"datasource": DS, "refId": "A", "instant": True, "range": False,
                     "expr": expr, "legendFormat": legend}],
    }


def max_p95(expr, legend):
    mx, p95 = peak(expr)
    return [(mx, f"{legend} max"), (p95, f"{legend} p95")]


# The "Resolution" dropdown: the narrowest a graph point may get (each panel's
# min interval). Grafana still widens points to fit the range - a week is ~10min
# a point whatever this says - so 5s means "automatic"; a wider value smooths
# short ranges, where 5s points make every panel a wall of spikes.
RESOLUTION = {
    "type": "custom", "name": "res", "label": "Resolution",
    "query": "5s,1m,5m,15m,1h",
    "current": {"text": "5s", "value": "5s"},
    "options": [{"text": v, "value": v, "selected": v == "5s"} for v in ["5s", "1m", "5m", "15m", "1h"]],
}


def dashboard(uid, title, panels, desc):
    return {
        "uid": uid, "title": title, "description": desc, "tags": ["homelab"],
        "timezone": "browser", "refresh": "30s", "schemaVersion": 39,
        "time": {"from": "now-6h", "to": "now"},
        "panels": panels, "editable": True,
        "templating": {"list": [RESOLUTION]},
    }


# ---- Hosts: xero and the wol Pi ---------------------------------------------
cpu_busy = ('100 * (1 - sum by (host) (' + counter_rate('node_cpu_seconds_total{mode=~"idle|iowait"}') +
            ') / count by (host) (node_cpu_seconds_total{mode="idle"}))')
core_busy = '100 * (1 - sum by (host, cpu) (' + counter_rate('node_cpu_seconds_total{mode=~"idle|iowait"}') + '))'
temp = 'node_thermal_zone_temp{type=~"x86_pkg_temp|cpu-thermal"}'
core_temp = 'node_hwmon_temp_celsius{chip=~"platform_coretemp.*"}'
mem_used = '100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)'
psi = lambda kind, which: '100 * ' + counter_rate(f'node_pressure_{kind}_{which}_seconds_total')
net_dev = 'device=~"enp.*|eth.*|wl.*|tailscale0"'
disk_dev = 'device=~"sd[a-z]|nvme.*|mmcblk[0-9]"'
# drivetemp's hwmon chips are named by SATA port: ata1 = sda, ata2 = sdb.
ssd_temp = lambda port: f'node_hwmon_temp_celsius{{host="xero",chip="target{port}:0:0_{port}:0:0:0"}}'

y = 0
hosts = []
hosts.append(stat("Uptime", 'time() - node_boot_time_seconds', "{{host}}", "dtdurations", 0, y,
                  desc="Since each host's kernel booted (node_boot_time_seconds), so a container or HA restart "
                       "does not reset it. A clean shutdown on a power cut (projects/power-watchdog) does."))
hosts.append(stat("Reboots in range", 'changes(node_boot_time_seconds[$__range])', "{{host}}", "short", 12, y,
                  desc="How many times the boot time changed within the selected range. Prometheus keeps 90 days."))
y += 4
hosts.append(panel("CPU busy, all cores", max_p95(cpu_busy, "{{host}}"), "percent", 0, y, max_=100,
                   desc="Share of all cores busy (not idle, not iowait) per 5s; each point is the max / p95 of its interval."))
hosts.append(panel("CPU temperature", max_p95(temp, "{{host}}"), "celsius", 12, y,
                   desc="xero: x86_pkg_temp (N5105 TjMax 105°C; healthcheck warns at 90, the Immich load guard stops it at 93). Pi: cpu-thermal."))
y += 8
hosts.append(panel("CPU busy per core (max)", [(peak(core_busy)[0], "{{host}} cpu{{cpu}}")], "percent", 0, y, max_=100))
hosts.append(panel("xero core temperatures (max)", [(peak(core_temp)[0], "{{sensor}}")], "celsius", 12, y))
y += 8
hosts.append(panel("Memory used (excl. cache)", max_p95(mem_used, "{{host}}"), "percent", 0, y, max_=100,
                   desc="1 - MemAvailable/MemTotal: page cache does not count, it is handed back on demand."))
hosts.append(panel("Pressure stall (xero)", [
    *max_p95(psi("cpu", "waiting"), "cpu some"),
    *max_p95(psi("memory", "waiting"), "memory some"),
    *max_p95(psi("io", "waiting"), "io some"),
], "percent", 12, y, desc="% of each 5s that some task waited for CPU / memory / IO (PSI). The Pi's kernel has no PSI."))
y += 8
hosts.append(panel("Disk busy", max_p95('100 * ' + counter_rate(f'node_disk_io_time_seconds_total{{{disk_dev}}}'),
                                        "{{host}} {{device}}"), "percent", 0, y, max_=100,
                   desc="xero: sda = datapool (ZFS), sdb = boot SSD. Pi: mmcblk0."))
hosts.append(panel("Disk throughput (max)", [
    (peak(counter_rate(f'node_disk_read_bytes_total{{{disk_dev}}}'))[0], "{{host}} {{device}} read"),
    (peak(counter_rate(f'node_disk_written_bytes_total{{{disk_dev}}}'))[0], "{{host}} {{device}} write"),
], "Bps", 12, y))
y += 8
hosts.append(panel("Network (max)", [
    (peak(counter_rate(f'node_network_receive_bytes_total{{{net_dev}}}'))[0], "{{host}} {{device}} rx"),
    (peak(counter_rate(f'node_network_transmit_bytes_total{{{net_dev}}}'))[0], "{{host}} {{device}} tx"),
], "Bps", 0, y, desc="xero's wired link negotiated 100Mb/s (~12MB/s) as of 2026-10-09."))
hosts.append(panel("SSD used", [
    (peak('100 * (1 - node_filesystem_avail_bytes{host="xero",mountpoint="/"} / '
          'node_filesystem_size_bytes{host="xero",mountpoint="/"})')[0], "BIWIN boot SSD (/)"),
    (peak('100 * homelab_zpool_used_bytes{zpool="datapool"} / '
          '(homelab_zpool_used_bytes{zpool="datapool"} + homelab_zpool_avail_bytes{zpool="datapool"})')[0],
     "Kingston SSD (datapool)"),
], "percent", 12, y, max_=100,
    desc="xero's two SSDs. Kingston = the whole ZFS pool incl. snapshots, from `zfs list` "
         "(services/node-exporter/zpool_textfile.sh, timer every 15 min); 100% is when writes stop. "
         "Its datasets are copies=2, so each GB of new data costs 2 GB here."))
y += 8
hosts.append(panel("ZFS ARC size (xero, max)", [(peak('node_zfs_arc_size')[0], "ARC")], "bytes", 0, y))
hosts.append(panel("SSD temperature (xero)", [
    *max_p95(ssd_temp(0), "Kingston (datapool)"),
    *max_p95(ssd_temp(1), "BIWIN boot"),
], "celsius", 12, y,
    desc="drivetemp hwmon, loaded since 2026-10-21 (projects/xero-stats/enable_drivetemp.sh). "
         "The Kingston A400 is rated to 70°C; SMART says it has reached 84°C. Chips are named by SATA "
         "port, so moving a cable swaps the two."))
y += 8
hosts.append(panel("ZFS errors (xero, max)", [
    (peak('sum by (zpool, type) (homelab_zpool_vdev_errors)')[0], "{{zpool}} {{type}}"),
], "short", 0, y,
    desc="Read / write / checksum errors summed over the pool's vdevs, as zpool status counts them "
         "(services/node-exporter/zpool_textfile.sh, timer every 15 min). They hold until `zpool clear`, "
         "so a step up marks when they happened. A level, so max only: a p95 would just repeat it. "
         "Checksum errors with no read/write errors mean bad data, not a bad link."))

# ---- Containers on xero (cAdvisor) -------------------------------------------
# Containers started with a bare `docker run` (builds, tests, one-off tools)
# get Docker's adjective_surname names, and over two days they outnumbered the
# real services (18 of 46 series on 2026-10-23). They are summed into one line.
# Immich's compose names match the same shape, so they are let through first.
AUTO_NAME = '[a-z]+_[a-z]+'
ONE_OFF = "one-off (docker run)"
TOP_N = 8


# cAdvisor gives a host-networked container the host's own interfaces, so each
# of them reports all of xero's traffic (five identical lines, 2026-10-23).
# They are left out of the network panels; read from compose so it can't drift.
_compose = yaml.safe_load((Path(__file__).resolve().parents[2] / "docker-compose.yml").read_text())
HOST_NET = sorted(svc.get("container_name", name) for name, svc in _compose["services"].items()
                  if svc.get("network_mode") == "host")


def by_container(metric, wrap=lambda s: s, skip=()):
    """sum by (name) of metric, with the one-off containers folded together."""
    named = f'{metric}{{name!="",name!~"{"|".join([AUTO_NAME, *skip])}"}}'
    immich = f'{metric}{{name=~"immich_.+"}}'
    one_off = f'{metric}{{name=~"{AUTO_NAME}",name!~"immich_.+"}}'
    return (f'(sum by (name) ({wrap(named)}) or sum by (name) ({wrap(immich)})'
            f' or label_replace(sum ({wrap(one_off)}), "name", "{ONE_OFF}", "", ""))')


def top(expr, graphed):
    """Keep graphed only for the TOP_N containers by expr's peak over the whole
    dashboard range. Ranked once, as of the range's end, so the set does not
    change from point to point and the legend stays TOP_N long."""
    return (f'({graphed}) and on (name) topk({TOP_N}, '
            f'max_over_time(({expr})[$__range:1m] @ ${{__to:date:seconds}}))')


c_cpu = '100 * ' + by_container('container_cpu_usage_seconds_total', counter_rate)
c_mem = by_container('container_memory_working_set_bytes')
c_rx = by_container('container_network_receive_bytes_total', counter_rate, HOST_NET)
c_tx = by_container('container_network_transmit_bytes_total', counter_rate, HOST_NET)
top_desc = f" Top {TOP_N} containers by peak over the selected range; `docker run` one-offs are one line."
containers = [
    panel("Container CPU (max)", [(top(c_cpu, peak(c_cpu)[0]), "{{name}}")], "percent", 0, 0, w=24, h=10,
          desc="100% = one full core; xero has 4. Each point is the max 5s value in its interval." + top_desc),
    panel("Container CPU (p95)", [(top(c_cpu, peak(c_cpu)[1]), "{{name}} p95")], "percent", 0, 10, w=24, h=10,
          desc=top_desc.strip()),
    panel("Container memory, working set (max)", [(top(c_mem, peak(c_mem)[0]), "{{name}}")], "bytes", 0, 20,
          w=24, h=10, desc=top_desc.strip()),
    panel("Container network received (max)", [(top(c_rx, peak(c_rx)[0]), "{{name}}")], "Bps", 0, 30, h=10,
          desc="Host-networked containers (" + ", ".join(HOST_NET) + ") are left out: cAdvisor reports all of xero's traffic for each of them." + top_desc),
    panel("Container network sent (max)", [(top(c_tx, peak(c_tx)[0]), "{{name}}")], "Bps", 12, 30, h=10,
          desc="Host-networked containers (" + ", ".join(HOST_NET) + ") are left out: cAdvisor reports all of xero's traffic for each of them." + top_desc),
]

# ---- Network usage per LAN device (xero as gateway) ---------------------------
# projects/lan-gateway: nft counts bytes per device IP; usage_textfile.sh writes
# them for node-exporter once a minute, so a minute is the finest grain there is
# (a 5s irate would read 0 between updates). Totals use increase(), which
# handles the counter reset on every xero reboot or table reload.
#
# Two sources, added up per device name:
#   - from CUTOVER on, homelab_lan_device_bytes_total{id}: bytes per device
#     (MAC, Tailscale label or IP), named as of the dashboard's "to" time, so
#     renaming a device relabels its history.
#   - before it, the per-IP counter, each 5 minutes named by whatever held the
#     IP then (homelab_lan_device_info at that moment). The router hands an IP
#     on when a device leaves, so naming old IP history by today's name filed
#     a week of an Android phone under a guest's laptop (2026-10-31). Those
#     names were cached an hour, so a device's first hour on a new IP may show
#     as the bare IP, and later renames do not reach this part.
gw = 'homelab_lan_gateway_bytes_total'
dev = 'homelab_lan_device_bytes_total'
CUTOVER = 1793415660  # 2026-10-31 08:31 IST, the first per-device sample


def by_name_now(expr):
    """Name each per-id series of expr as of the dashboard's "to" time. Not
    @ end(): Grafana rounds a range query's end down to its step, which on the
    hourly panels is up to an hour ago. An id with no name keeps its id."""
    return (f'(({expr}) * on (id) group_left (device) (homelab_lan_device_name @ ${{__to:date:seconds}})'
            f' or on (id) label_replace({expr}, "device", "$1", "id", "(.*)"))')


def by_name_then(expr):
    """Name each per-ip series of expr by the device on that IP at the time,
    and keep only points before CUTOVER."""
    return (f'((({expr}) * on (ip) group_left (device) homelab_lan_device_info'
            f' or on (ip) label_replace({expr}, "device", "$1", "ip", "(.*)"))'
            f' and on () (vector(time()) < {CUTOVER}))')


def both(new, old, by="device, direction"):
    """new + old summed per device; a src label keeps them apart until the sum."""
    return (f'sum by ({by}) (label_replace(sum by ({by}) ({new}), "src", "new", "", "")'
            f' or label_replace(sum by ({by}) ({old}), "src", "old", "", ""))')


def bytes_in(window):
    """Bytes per device and direction in each window ending at a point."""
    old = f'sum_over_time((sum by (device, direction) ({by_name_then(f"increase({gw}[5m])")}))[{window}:5m])'
    return both(by_name_now(f"increase({dev}[{window}])"), old)


def rate_of(direction):
    sel = f'{{direction="{direction}"}}'
    return both(by_name_now(f"rate({dev}{sel}[2m])"), by_name_then(f"rate({gw}{sel}[2m])"), by="device")


def usage_bars(title, time_from, x, y, w=8, h=10):
    """Bytes per device and direction over a fixed window, largest first."""
    return {
        "id": next(_ids), "type": "bargauge", "title": title, "datasource": DS,
        "timeFrom": time_from, "hideTimeOverride": False,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": {"unit": "bytes", "min": 0, "decimals": 1}},
        "options": {"orientation": "horizontal", "displayMode": "basic", "showUnfilled": True,
                    "valueMode": "text", "namePlacement": "left",
                    # auto sizing squeezes ~16 rows until the names vanish; fixed rows scroll
                    "sizing": "manual", "minVizHeight": 16, "maxVizHeight": 16,
                    "reduceOptions": {"calcs": ["lastNotNull"], "values": False}},
        "transformations": [{"id": "sortBy", "options": {"sort": [{"field": "Value", "desc": True}]}}],
        "targets": [{"datasource": DS, "refId": "A", "instant": True, "range": False,
                     "expr": f'sort_desc({bytes_in("$__range")})',
                     "legendFormat": "{{device}} {{direction}}"}],
    }


usage = [
    usage_bars("Today", "now/d", 0, 0),
    usage_bars("This month", "now/M", 8, 0),
    usage_bars("Last 30 days", "30d", 16, 0),
    {**panel("Per day", [(bytes_in("1d"), "{{device}} {{direction}}")],
             "bytes", 0, 10, w=24, h=10, stack=True,
             desc="Bytes per device per day, stacked. Days are UTC days (05:30 to 05:30 IST): "
                  "Prometheus aligns 1d steps to UTC, and a day's bar appears only once it has ended - "
                  "the Today gauge covers the day so far."),
     "interval": "1d", "timeFrom": "30d"},
    {**panel("Per hour", [(bytes_in("1h"), "{{device}} {{direction}}")],
             "bytes", 0, 20, w=24, h=10, stack=True,
             desc="Bytes per device per hour, stacked, last 2 days. An hour's bar appears once it has ended."),
     "interval": "1h", "timeFrom": "2d"},
    panel("Throughput per device (max)", [
        (f'max_over_time(({rate_of("down")})[$__interval:1m])', "{{device}} down"),
        (f'max_over_time(({rate_of("up")})[$__interval:1m])', "{{device}} up"),
    ], "Bps", 0, 30, w=24, h=10,
        desc="The counters update once a minute, so this is each minute's rate and each point the max "
             "of those minutes - no finer than a minute."),
]
for bars in usage[3:5]:
    bars["fieldConfig"]["defaults"]["custom"].update({"drawStyle": "bars", "fillOpacity": 80})
    bars["options"]["legend"]["calcs"] = ["sum", "max"]

# ---- Jobs: every scheduled job (projects/jobs-dashboard) ----------------------
# jobs_collector.py writes one homelab_job_* series per job (label `name`; `job`
# is Prometheus's own scrape label). The 60-day p50/p95/max (duration, CPU,
# RAM, busiest second, temperatures) are computed per run by the collector from
# its run history, not from these gauges.
J = 'max by (host, name) (homelab_job_{}{{name=~"$jobname"}})'
JOB_VAR = {"type": "query", "name": "jobname", "label": "Job", "datasource": DS,
           "query": {"query": "label_values(homelab_job_info, name)", "refId": "J"},
           "definition": "label_values(homelab_job_info, name)",
           "includeAll": True, "multi": True, "allValue": ".+", "refresh": 2,
           "current": {"text": "All", "value": "$__all"}}


# Table height: one grid unit per job plus the header, so no row hides behind a scrollbar.
JOBS_ROWS = len(tomllib.loads((OUT.parent.parent.parent / "projects/jobs-dashboard/jobs.toml").read_text())["job"])
JOBS_H = max(10, JOBS_ROWS + 3)


def jobs_table(y):
    cols = [  # (refId, expr, column, unit)
        ("A", J.format("last_ok"), "OK", "none"),
        ("B", J.format("last_start_timestamp_seconds") + " * 1000", "Last start", "dateTimeFromNow"),
        ("C", J.format("last_duration_seconds"), "Duration", "s"),
        ("D", J.format("duration_p95_seconds"), "p95 (60d)", "s"),
        ("E", J.format("duration_max_seconds"), "Max (60d)", "s"),
        ("F", J.format("next_run_timestamp_seconds") + " * 1000", "Next run", "dateTimeFromNow"),
        ("G", J.format("consecutive_failures"), "Fails in a row", "none"),
        ("H", J.format("last_cpu_max_percent"), "Max CPU (1 core = 100%)", "percent"),
        ("I", J.format("last_ram_peak_bytes"), "Peak RAM", "bytes"),
        ("K", 'max by (host, name) (homelab_job_last_peak_temp_celsius{name=~"$jobname",sensor="cpu"})', "CPU °C", "celsius"),
        ("L", 'max by (host, name) (homelab_job_last_peak_temp_celsius{name=~"$jobname",sensor="ssd_data"})', "Kingston °C", "celsius"),
        ("M", J.format("runs"), "Runs (60d)", "none"),
    ]
    rename = {f"Value #{r}": c for r, _, c, _ in cols}
    overrides = [{"matcher": {"id": "byName", "options": c},
                  "properties": [{"id": "unit", "value": u}]} for _, _, c, u in cols]
    overrides += [
        {"matcher": {"id": "byName", "options": "OK"},
         "properties": [{"id": "mappings", "value": [{"type": "value", "options": {
             "1": {"text": "ok", "color": "green"}, "0": {"text": "FAILED", "color": "red"}}},
             {"type": "special", "options": {"match": "null", "result": {"text": "not run yet", "color": "transparent"}}}]},
             {"id": "custom.cellOptions", "value": {"type": "color-background"}}]},
        {"matcher": {"id": "byName", "options": "Fails in a row"},
         "properties": [{"id": "thresholds", "value": {"mode": "absolute", "steps": [
             {"color": "transparent", "value": None}, {"color": "red", "value": 1}]}},
             {"id": "custom.cellOptions", "value": {"type": "color-background"}}]},
    ]
    targets = [{"datasource": DS, "refId": "Z", "instant": True, "range": False, "format": "table",
                "expr": 'max by (host, name, desc, schedule, log) (homelab_job_info{name=~"$jobname"})'}]
    targets += [{"datasource": DS, "refId": r, "instant": True, "range": False, "format": "table",
                 "expr": e} for r, e, _, _ in cols]
    return {
        "id": next(_ids), "type": "table", "title": "Jobs", "datasource": DS,
        "description": "One row per job, latest finished run. Schedules and commands: "
                       "projects/jobs-dashboard/jobs.toml. Output: the log file, or journalctl --user -u job-<name>.",
        "gridPos": {"x": 0, "y": y, "w": 24, "h": JOBS_H},
        "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": overrides},
        "options": {"showHeader": True, "cellHeight": "sm", "sortBy": [{"displayName": "OK", "desc": False}]},
        "targets": targets,
        "transformations": [
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "Value #Z": True},
                "indexByName": {"host": 0, "name": 1, "desc": 2, "schedule": 3},
                "renameByName": {**rename, "name": "Job", "host": "Host", "desc": "What it does",
                                 "schedule": "Schedule", "log": "Log"}}},
        ],
    }


def job_temp(stat, sensor):
    return f'max by (host, name) (homelab_job_temp_{stat}_celsius{{name=~"$jobname",sensor="{sensor}"}})'


CPU_COLS = [  # (refId, expr, column, unit, header tooltip)
    ("A", J.format("runs"), "Runs", "none", "Runs recorded in the last 60 days."),
    ("B", J.format("cpu_p50_seconds"), "CPU s p50", "s",
     "CPU seconds of a typical run, whole process tree. Blank: fewer than 20 runs, see max. "
     "Sub-second jobs are mostly the recording hooks' own cost: compare with the noop row."),
    ("C", J.format("cpu_p95_seconds"), "CPU s p95", "s", "CPU seconds of a heavy run (p95 over 60 days)."),
    ("D", J.format("cpu_max_seconds"), "CPU s max", "s", "CPU seconds of the heaviest run in 60 days."),
    ("E", J.format("cpu_busiest_day_seconds"), "CPU top day", "s",
     "CPU seconds of all the job's runs on its busiest day (IST) in 60 days: work per run x how often. "
     "Recomputed hourly."),
    ("F", J.format("cpu_last_24h_seconds"), "CPU s 24h", "s",
     "CPU seconds of all the job's runs in the last 24 hours. Recomputed hourly."),
    ("G", J.format("cpu_busiest_second_p95_percent"), "1s CPU % p95", "percent",
     "Busiest second of a run: highest 1s CPU, % of one core (xero has 4: up to 400), p95 over runs of 1s or more. "
     "Over 100 = it uses more than one core. Blank: fewer than 20 runs of 1s or more (recorded since 2026-11-24)."),
    ("H", J.format("cpu_busiest_second_max_percent"), "1s CPU % max", "percent",
     "Highest 1s CPU of any run of 1s or more, % of one core. Blank: every run was under a second."),
]
MEM_COLS = [
    ("I", J.format("ram_p95_bytes"), "RAM p95", "bytes",
     "Peak RAM of a heavy run: the processes' own memory (anon), no page cache - what two jobs at the same "
     "time would fight over. Recorded since 2026-11-26."),
    ("J", J.format("ram_max_bytes"), "RAM max", "bytes", "Peak RAM (anon) of the hungriest run in 60 days."),
    ("K", J.format("memory_max_bytes"), "+cache max", "bytes",
     "memory.peak of the biggest run: RAM plus the page cache its file reads filled. Much bigger than RAM = "
     "it reads a lot of files, not that it needs the memory."),
    ("L", job_temp("p95", "cpu"), "CPU °C p95", "celsius",
     "Hottest CPU reading during a run, p95 over runs of a minute or more (shorter runs only read what "
     "something else did)."),
    ("M", job_temp("max", "cpu"), "CPU °C max", "celsius", "Hottest CPU reading during any run of a minute or more."),
    ("N", job_temp("p95", "ssd_data"), "SSD °C p95", "celsius",
     "Kingston (datapool) SSD: hottest reading during a run of a minute or more, p95. The Kingston is rated to 70°C."),
    ("O", job_temp("max", "ssd_data"), "SSD °C max", "celsius",
     "Kingston (datapool) SSD: hottest reading during any run of a minute or more."),
]


def cost_table(title, cols, sort_by, desc, y):
    rename = {f"Value #{r}": c for r, _, c, _, _ in cols}
    overrides = [{"matcher": {"id": "byName", "options": c},
                  "properties": [{"id": "unit", "value": u}, {"id": "description", "value": d}]}
                 for _, _, c, u, d in cols]
    targets = [{"datasource": DS, "refId": "Z", "instant": True, "range": False, "format": "table",
                "expr": 'max by (host, name) (homelab_job_info{name=~"$jobname"})'}]
    targets += [{"datasource": DS, "refId": r, "instant": True, "range": False, "format": "table",
                 "expr": e} for r, e, _, _, _ in cols]
    return {
        "id": next(_ids), "type": "table", "title": title, "datasource": DS,
        "description": desc + " p50/p95 need 20 runs; max shows from the first. Counts and maxima update with "
                       "each run, p50/p95 and the CPU totals hourly. Hover a header for what it means. "
                       "Source: projects/jobs-dashboard/jobs_collector.py.",
        "gridPos": {"x": 0, "y": y, "w": 24, "h": JOBS_H},
        # Grafana's default 150px minimum per column pushes the last ones off screen
        "fieldConfig": {"defaults": {"custom": {"align": "auto", "minWidth": 60}},
                        "overrides": overrides + [
                            {"matcher": {"id": "byName", "options": n}, "properties": [{"id": "custom.width", "value": w}]}
                            for n, w in (("Host", 60), ("Job", 200))]},
        "options": {"showHeader": True, "cellHeight": "sm", "sortBy": [{"displayName": sort_by, "desc": True}]},
        "targets": targets,
        "transformations": [
            {"id": "merge", "options": {}},
            {"id": "organize", "options": {
                "excludeByName": {"Time": True, "Value #Z": True},
                "indexByName": {"host": 0, "name": 1},
                "renameByName": {**rename, "name": "Job", "host": "Host"}}},
        ],
    }


y = 0
jobs = [jobs_table(y)]
y += JOBS_H
jobs.append(cost_table("CPU per job (60 days)", CPU_COLS, "CPU top day",
                       "Which jobs are CPU-heavy: per run, per day, and whether one uses more than a core.", y))
y += JOBS_H
jobs.append(cost_table("RAM and heat per job (60 days)", MEM_COLS, "RAM max",
                       "Which jobs need RAM (keep two big ones apart) and which heat xero.", y))
y += JOBS_H
jobs.append(panel("Duration of each run", [(J.format("last_duration_seconds"), "{{host}} {{name}}")],
                  "s", 0, y, w=12, desc="Steps to each run's duration when it finishes. "
                  "Runs shorter than the gap between points can be missed when zoomed out; the table's p95/max cannot."))
jobs.append(panel("Failures in a row", [(J.format("consecutive_failures"), "{{host}} {{name}}")],
                  "none", 12, y, w=12, desc="0 while the job succeeds; climbs by one per failed run."))
y += 8
EACH_RUN = ("Steps to each run's value when it finishes, so a trend (a backup growing, a change making a job "
            "heavier) shows here and not in the 60-day table. Zoomed out, runs shorter than the gap between "
            "points can be missed; the table's max cannot.")
jobs.append(panel("CPU seconds of each run", [(J.format("last_cpu_seconds"), "{{host}} {{name}}")],
                  "s", 0, y, w=8, desc=EACH_RUN))
jobs.append(panel("Peak RAM of each run", [(J.format("last_ram_peak_bytes"), "{{host}} {{name}}")],
                  "bytes", 8, y, w=8, desc="The processes' own memory (anon), no page cache. Recorded since "
                  "2026-11-26. " + EACH_RUN))
jobs.append(panel("Busiest second of each run (1 core = 100%)",
                  [(J.format("last_cpu_max_percent") + ' and on (host, name) ' + J.format("last_duration_seconds")
                    + " >= 1", "{{host}} {{name}}")],
                  "percent", 16, y, w=8, desc="Runs of 1s or more only (shorter ones read noise). "
                  "Over 100 = more than one core. " + EACH_RUN))
y += 8
jobs.append(panel("CPU temperature (jobs shaded while running)",
                  max_p95('max by (host) (node_hwmon_temp_celsius{chip=~"platform_coretemp.*"})', "{{host}}"),
                  "celsius", 0, y, w=12, desc="Shaded: a job that has been running for more than 10s (shorter runs cannot move a temperature)."))
jobs.append(panel("SSD temperature (jobs shaded while running)",
                  [(f"max_over_time(({ssd_temp(0)})[$__interval:5s])", "Kingston (datapool) max"),
                   (f"max_over_time(({ssd_temp(1)})[$__interval:5s])", "BIWIN (boot) max")],
                  "celsius", 12, y, w=12, desc="The Kingston is rated to 70°C. Shaded regions: a job was running."))
JOBS_ANNOTATIONS = [{"datasource": DS, "enable": True, "name": "Jobs running", "iconColor": "rgba(255, 152, 48, 0.4)",
                     "expr": 'max by (name) (homelab_job_running{name=~"$jobname"} == 1 and '
                             '(time() - homelab_job_last_start_timestamp_seconds) > 10)',
                     "step": "5s", "titleFormat": "{{name}}", "textFormat": "running",
                     "useValueForTime": False}]

OUT.mkdir(exist_ok=True)
for uid, title, panels, desc in [
    ("hosts", "Hosts", hosts, "xero and the wol Pi: max and p95 of 5s samples, never averages."),
    ("containers", "Containers (xero)", containers, "Per-container CPU, memory and network from cAdvisor."),
    ("jobs", "Jobs", jobs, "Every scheduled job on xero (and later the Pi): last run, next run, result, cost and "
     "temperatures. Source: projects/jobs-dashboard."),
    ("network-usage", "Network usage (per device)", usage,
     "Internet bytes per LAN device through xero as the gateway (projects/lan-gateway). "
     "Counted per device (MAC, Tailscale name, or IP behind the extender) since 2026-10-31 08:31; before that per IP, named by whichever device held the IP at the time. "
     "Devices are named from projects/lan-gateway/device-names, else the router's hostname, else their IP; only DHCP devices go through xero, fixed-IP ones (xero, the Pi, ESP32s) do not."),
]:
    path = OUT / f"{uid}.json"
    d = dashboard(uid, title, panels, desc)
    if uid == "jobs":
        d["templating"]["list"].append(JOB_VAR)
        d["annotations"] = {"list": JOBS_ANNOTATIONS}
    path.write_text(json.dumps(d, indent=2) + "\n")
    print(f"wrote {path.relative_to(OUT.parent.parent.parent)} ({len(panels)} panels)")
