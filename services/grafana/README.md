# Grafana + Prometheus

Graphs of everything xero and the wol Pi do, at
**https://xero.&lt;tailnet&gt;/grafana/** (tailnet only, through Caddy). Anyone
who can reach it can view; editing needs the `admin` login, password
`GRAFANA_ADMIN_PASSWORD` in `.env`. Set up 2026-10-11 because HA's dashboards
show one series at a time.

## Pieces

| Container | Where | Listens | Does |
|---|---|---|---|
| `prometheus` | xero, compose | 127.0.0.1:9090 | scrapes every **5s**, keeps 90 days / 8GB (`prometheus-data` volume, boot SSD) - `services/prometheus/prometheus.yml` |
| `node-exporter` | xero, compose | 127.0.0.1:9100 | host metrics: CPU per core, temperatures, memory, PSI, disks, network, filesystems, ZFS ARC |
| `node-exporter` | wol Pi, `services/node-exporter/deploy_pi.sh` | 192.168.1.124:9100 | the same for the Pi |
| `cadvisor` | xero, compose | 127.0.0.1:8088 | per-container CPU, memory, network |
| `grafana` | xero, compose | 127.0.0.1:3000 | the UI; datasource and dashboards are provisioned from `provisioning/` and `dashboards/` |

## SSD used

The "SSD used" panel shows xero's two SSDs only: the BIWIN boot SSD (`/`)
and the Kingston, as the whole `datapool` ZFS pool. Per-dataset `df` numbers
are useless for the pool (each dataset's "size" is its own data plus the
shared free space, and snapshots count nowhere), so
`services/node-exporter/zpool_textfile.sh` (xero's crontab, every minute) writes
`zfs list` used/avail for the pool to `services/node-exporter/textfile/`, which
node-exporter's textfile collector exports as `homelab_zpool_used_bytes` /
`homelab_zpool_avail_bytes`. used / (used + avail) is 100% when writes stop
(avail is after the ~1/32 slop reserve). The datasets are `copies=2`, so each
GB of new data costs 2 GB of that.

## SSD temperature and ZFS errors

Added 2026-10-21 after datapool's Kingston stalled for 44s. **SSD
temperature** is node-exporter's hwmon reading of the `drivetemp` module
(loaded at boot by `/etc/modules-load.d/drivetemp.conf`,
`projects/xero-stats/enable_drivetemp.sh`), max and p95 per drive. The chips
are named by SATA port (`target0...` = ata1 = the Kingston, `target1...` =
the BIWIN boot SSD), so moving a cable swaps the labels. **ZFS errors** are
each vdev's read/write/checksum counts from `zpool get ... all-vdevs`, written
by `zpool_textfile.sh` as `homelab_zpool_vdev_errors`; they hold until
`zpool clear`, so a step up marks when errors happened.

## HA vs Grafana

Since 2026-10-21 HA's Stats dashboard is the high-level view (max tiles only,
no p95) and Grafana holds the detail (max and p95 overlaid, per core, per
device). New detail goes here; HA gets a tile only for what is worth a glance.

## No averages

Every panel plots the **max** and **p95** of each graph interval, never an
average (the rule since 2026-10-09). Prometheus scrapes every 5s, `irate()`
turns a counter into a 5s rate, and each point on a graph is
`max_over_time` / `quantile_over_time(0.95, ...)` of the 5s values inside
that point's `$__interval`. Zoomed out to a week a point covers about ten
minutes and still shows the worst five seconds in it. p95 lines are dashed.
Legends show the max and the last value, not the mean.

## Changing dashboards

`build_dashboards.py` writes `dashboards/*.json`; that script is the source
of truth. Edit it, run it, commit both - Grafana reloads the files within a
minute. UI edits work but are lost on the next rebuild unless copied back.
`check_queries.py` runs every dashboard query against Prometheus and lists any
that return no data.

## On the iPhone

- **GrafLens** (free, open source) works. Server
  `https://xero.<tailnet>:3443` - a second Caddy site that serves Grafana at
  the root, because GrafLens keeps only host:port from the URL and calls
  `/api/...` at the root, which on :443 is Vaultwarden (it 404s). Token: the
  Viewer-only service account `ios-graflens` (created 2026-10-12; the token is
  not stored in the repo - revoke or re-issue it under Administration ->
  Service accounts).
- **The official "Grafana" app does not work here.** It is Grafana IRM
  (on-call/alerting), not a dashboard viewer: it asks for
  `/a/grafana-irm-app/mobile-app-connection`, which needs the IRM plugin and
  Grafana Cloud.
- A Safari "Add to Home Screen" shortcut to `/grafana/` also works, no login.

## Network usage (per device)

Added 2026-10-22 with `projects/lan-gateway/`: bytes each LAN device sends
and receives through xero as its internet gateway (DHCP devices only; xero,
the Pi and the ESP32s have fixed IPs on the router). Devices are named by
`homelab_lan_device_info{ip,device}`, joined on the names as of the
dashboard's end time, so naming a device relabels its whole history: see
`projects/lan-gateway/README.md` for where the names come from. Today / this month
/ last 30 days, per day, per hour, and per-minute throughput. The counters
are written once a minute (`homelab_lan_gateway_bytes_total`), so a minute is
the finest grain - the one place the 5s rule cannot apply. `increase()`
counts from a device's first sample, so the bytes in its first minute (and
the tests from before the dashboard existed) are not in the totals. Day bars
are UTC days (05:30 IST) and appear once the day has ended.

## Not covered yet

- **Home Assistant's own sensors** (Pi health, healthcheck, AC, room
  temperatures): HA's `prometheus:` integration would expose them, but it
  needs a `configuration.yaml` edit and an HA restart (see the memory note on
  restart side effects).
- **Immich job queues**: Immich exports Prometheus metrics with
  `IMMICH_TELEMETRY_INCLUDE=all` on ports 8081/8082 inside the container.
