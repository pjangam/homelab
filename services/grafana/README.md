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

## Not covered yet

- **Home Assistant's own sensors** (Pi health, healthcheck, AC, room
  temperatures): HA's `prometheus:` integration would expose them, but it
  needs a `configuration.yaml` edit and an HA restart (see the memory note on
  restart side effects).
- **Immich job queues**: Immich exports Prometheus metrics with
  `IMMICH_TELEMETRY_INCLUDE=all` on ports 8081/8082 inside the container.
