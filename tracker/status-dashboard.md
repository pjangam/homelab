# Consolidated status dashboard
**Status:** Done

**Why:** previously the only way to know something's wrong was a `healthcheck.sh` email after the fact.
**Outcome:** `healthcheck.sh` publishes its check results to MQTT with HA discovery, and a "Homelab Health" section on the "Stats" Lovelace dashboard shows them. Verified end-to-end: entities confirmed live via the HA REST API, dashboard confirmed intact after restart with no lovelace-related errors in logs.

#### Design
- Check results published: containers, systemd units, ZFS pool health, disk usage, backup freshness - grouped under a "Homelab Healthcheck" device, 9 entities total.
- Published on every 15min cron run independent of the email-alert path, so a publish failure can't suppress a real alert.
- The "Homelab Health" section has tile cards for all 9 entities. Adding it required stopping HA briefly to hand-edit the storage-mode dashboard file directly, since it's UI-managed rather than YAML.
