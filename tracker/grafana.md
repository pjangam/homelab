# Grafana for all stats
**Status:** Done
**Priority:** P3

**Why:** HA's dashboards show one series per tile and only what the sensor gives (averages, until 2026-10-09); asked for 2026-10-11 to see everything side by side with percentiles.
**Outcome:** running since 2026-10-11 at `https://xero.<tailnet>/grafana/` (`services/grafana/README.md`). Every panel is max/p95 of 5s samples per interval. Left open: maybe HA's `prometheus:` integration (needs an HA restart) and Immich's job-queue metrics, so those land in Grafana too.

#### What runs
- Prometheus (5s scrapes, 90d/8GB), node_exporter on xero and the wol Pi, cAdvisor for containers, Grafana 13.2.3 with two generated dashboards (Hosts, Containers).
- Checks: `services/grafana/check_queries.py` (every query returns data) and `services/grafana/shot_grafana.sh` (screenshots; fails if Grafana does not boot or a panel shows no data).
- Overhead ~10% of one core, ~0.7GB RAM.

#### Log
- 2026-10-11: asked for, and running the same day.
