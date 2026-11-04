# Prometheus

Metrics store behind the Grafana dashboards
([`services/grafana/README.md`](../grafana/README.md)). One file:
[`prometheus.yml`](prometheus.yml).

It scrapes **every 5s**, not the usual 15-60s, for the same reason the stats
projects publish percentiles: a counter's rate is only as fine as its scrape
interval, so at 60s a ten-second CPU spike is already flattened before any
percentile can see it.

Targets: node_exporter on xero and on the wol Pi (over the LAN - see
[`services/node-exporter/`](../node-exporter/README.md)), cAdvisor for
per-container series, and itself. Everything is on localhost except the Pi.
