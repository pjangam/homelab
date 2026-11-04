# Synthetic healthcheck

The homelab's one alarm clock. `healthcheck.sh` runs from xero's crontab every
15 minutes, checks the things whose failure is otherwise silent, and is
**quiet when healthy** - it emails and pushes only on a real problem, so that
an arriving alert always means something.

What it checks: containers, systemd units, `systemd --user` linger (the gotcha
that broke white noise), ZFS pool health, disk space, backup freshness, CPU and
SSD temperature, TLS cert expiry
([`projects/certs-backup/check_certs.sh`](../certs-backup/README.md)) and
whether the MirAIe AC is actually usable
([`projects/miraie-ac/`](../miraie-ac/README.md)) - which it also auto-fixes
once per outage.

| | |
|---|---|
| `healthcheck.sh` | the check itself (cron, */15) |
| `publish_healthcheck_mqtt.py` | one-shot publisher - results to MQTT with HA discovery, for the Stats dashboard |
| `healthcheck_last_run.sh` | when did it last actually complete? Reads the retained `last_check`, because a healthy run writes nothing to the log |
| `verify_healthcheck_entities.sh` | does HA really hold what we published? Closes the "a monitor that cannot report its own failure" gap |
| `add_stats_dashboard_tile.py` | add a tile over HA's websocket API, no HA restart (idempotent, snapshots the dashboard first) |
| `test_cpu_temp_check.sh`, `test_ssd_temp_check.sh`, `test_healthcheck_dashboard_verify.sh` | tests |

Alert routing (email + ntfy, and which topic) is in
[`services/ntfy/README.md`](../../services/ntfy/README.md).
