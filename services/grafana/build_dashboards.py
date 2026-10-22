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
from pathlib import Path

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
        "datasource": DS, "interval": "5s",
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
            "legend": {"displayMode": "table", "placement": "right", "calcs": ["max", "lastNotNull"]},
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
        "targets": [{"datasource": DS, "refId": chr(65 + i), "expr": e, "legendFormat": l}
                    for i, (e, l) in enumerate(targets)],
    }
    if max_ is not None:
        p["fieldConfig"]["defaults"]["max"] = max_
    return p


def max_p95(expr, legend):
    mx, p95 = peak(expr)
    return [(mx, f"{legend} max"), (p95, f"{legend} p95")]


def dashboard(uid, title, panels, desc):
    return {
        "uid": uid, "title": title, "description": desc, "tags": ["homelab"],
        "timezone": "browser", "refresh": "30s", "schemaVersion": 39,
        "time": {"from": "now-6h", "to": "now"},
        "panels": panels, "editable": True,
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
         "(services/node-exporter/zpool_textfile.sh, cron every minute); 100% is when writes stop. "
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
         "(services/node-exporter/zpool_textfile.sh, cron every minute). They hold until `zpool clear`, "
         "so a step up marks when they happened. A level, so max only: a p95 would just repeat it. "
         "Checksum errors with no read/write errors mean bad data, not a bad link."))

# ---- Containers on xero (cAdvisor) -------------------------------------------
c_cpu = '100 * sum by (name) (' + counter_rate('container_cpu_usage_seconds_total{name!=""}') + ')'
c_mem = 'container_memory_working_set_bytes{name!=""}'
containers = [
    panel("Container CPU (max)", [(peak(c_cpu)[0], "{{name}}")], "percent", 0, 0, w=24, h=10,
          desc="100% = one full core; xero has 4. Each point is the max 5s value in its interval."),
    panel("Container CPU (p95)", [(peak(c_cpu)[1], "{{name}} p95")], "percent", 0, 10, w=24, h=10),
    panel("Container memory, working set (max)", [(peak(c_mem)[0], "{{name}}")], "bytes", 0, 20, w=24, h=10),
    panel("Container network (max)", [
        (peak('sum by (name) (' + counter_rate('container_network_receive_bytes_total{name!=""}') + ')')[0], "{{name}} rx"),
        (peak('sum by (name) (' + counter_rate('container_network_transmit_bytes_total{name!=""}') + ')')[0], "{{name}} tx"),
    ], "Bps", 0, 30, w=24, h=10, desc="Host-networked containers (Caddy, Grafana, Prometheus, HA...) do not show here."),
]

# ---- Network usage per LAN device (xero as gateway) ---------------------------
# projects/lan-gateway: nft counts bytes per device IP; usage_textfile.sh writes
# them for node-exporter once a minute, so a minute is the finest grain there is
# (a 5s irate would read 0 between updates). Totals use increase(), which
# handles the counter reset on every xero reboot or table reload.
gw = 'homelab_lan_gateway_bytes_total'


def usage_bars(title, time_from, x, y, w=8, h=10):
    """Bytes per device and direction over a fixed window, largest first."""
    return {
        "id": next(_ids), "type": "bargauge", "title": title, "datasource": DS,
        "timeFrom": time_from, "hideTimeOverride": False,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "fieldConfig": {"defaults": {"unit": "bytes", "min": 0, "decimals": 1}},
        "options": {"orientation": "horizontal", "displayMode": "basic", "showUnfilled": True,
                    "valueMode": "text", "namePlacement": "top", "sizing": "auto",
                    "reduceOptions": {"calcs": ["lastNotNull"], "values": False}},
        "transformations": [{"id": "sortBy", "options": {"sort": [{"field": "Value", "desc": True}]}}],
        "targets": [{"datasource": DS, "refId": "A", "instant": True, "range": False,
                     "expr": f'sort_desc(sum by (ip, direction) (increase({gw}[$__range])))',
                     "legendFormat": "{{ip}} {{direction}}"}],
    }


usage = [
    usage_bars("Today", "now/d", 0, 0),
    usage_bars("This month", "now/M", 8, 0),
    usage_bars("Last 30 days", "30d", 16, 0),
    {**panel("Per day", [(f'sum by (ip, direction) (increase({gw}[1d]))', "{{ip}} {{direction}}")],
             "bytes", 0, 10, w=24, h=10, stack=True,
             desc="Bytes per device per day, stacked. Days are UTC days (05:30 to 05:30 IST): "
                  "Prometheus aligns 1d steps to UTC, and a day's bar appears only once it has ended - "
                  "the Today gauge covers the day so far."),
     "interval": "1d", "timeFrom": "30d"},
    {**panel("Per hour", [(f'sum by (ip, direction) (increase({gw}[1h]))', "{{ip}} {{direction}}")],
             "bytes", 0, 20, w=24, h=10, stack=True,
             desc="Bytes per device per hour, stacked, last 2 days. An hour's bar appears once it has ended."),
     "interval": "1h", "timeFrom": "2d"},
    panel("Throughput per device (max)", [
        (f'max_over_time((sum by (ip) (rate({gw}{{direction="down"}}[2m])))[$__interval:1m])', "{{ip}} down"),
        (f'max_over_time((sum by (ip) (rate({gw}{{direction="up"}}[2m])))[$__interval:1m])', "{{ip}} up"),
    ], "Bps", 0, 30, w=24, h=10,
        desc="The counters update once a minute, so this is each minute's rate and each point the max "
             "of those minutes - no finer than a minute."),
]
for bars in usage[3:5]:
    bars["fieldConfig"]["defaults"]["custom"].update({"drawStyle": "bars", "fillOpacity": 80})
    bars["options"]["legend"]["calcs"] = ["sum", "max"]

OUT.mkdir(exist_ok=True)
for uid, title, panels, desc in [
    ("hosts", "Hosts", hosts, "xero and the wol Pi: max and p95 of 5s samples, never averages."),
    ("containers", "Containers (xero)", containers, "Per-container CPU, memory and network from cAdvisor."),
    ("network-usage", "Network usage (per device)", usage,
     "Internet bytes per LAN device through xero as the gateway (projects/lan-gateway). "
     "Devices are shown by IP; only DHCP devices go through xero, fixed-IP ones (xero, the Pi, ESP32s) do not."),
]:
    path = OUT / f"{uid}.json"
    path.write_text(json.dumps(dashboard(uid, title, panels, desc), indent=2) + "\n")
    print(f"wrote {path.relative_to(OUT.parent.parent.parent)} ({len(panels)} panels)")
