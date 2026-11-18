# Synthetic healthcheck + email/heartbeat notifications
**Status:** Done

**Why:** problems on xero needed to be noticed without someone looking, including a total machine freeze.
**Outcome:** `healthcheck.sh` (cron, every 15 min) checks Docker containers, `systemctl --user`/system failed units, ZFS pool health, disk space, and linger, alerts by email, and pings a healthchecks.io dead-man's-switch every run.

#### Design
- Alerts via Gmail SMTP to the user's own email (HA mobile push doesn't work without a Nabu Casa subscription - confirmed by testing), with state-based dedup so an unresolved problem alerts once, not every run.
- The healthchecks.io dead-man's-switch catches a total machine freeze that a script running on the machine itself could never detect about itself.
- Caught a real bug in its own construction: `systemctl --user` fails silently under cron's stripped environment without `XDG_RUNTIME_DIR` set.
