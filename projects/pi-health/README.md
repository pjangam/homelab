# wol Pi health over MQTT

The wol-sender Pi reporting its own health to Home Assistant, so xero's
healthcheck can tell "Pi healthy" from "Pi silent". Started 2026-10-06 for the
Pi's under-voltage problem (`PROJECTS.md`, "wol Pi health monitoring").

`pi-health-mqtt.py` runs **on the Pi** as `pi-health-mqtt.service`
(`systemd --user`, linger on). Every interval it publishes one retained JSON
object; each HA entity picks its field out with a `value_template`.
Availability is an MQTT last-will, so the entities go unavailable within a
keepalive if the Pi drops off the LAN or the daemon dies.

Install or update it by running `deploy_pi_health.sh` **on xero** - the Pi has
no repo clone, so the script lands the files under `~/homelab` and rewrites the
unit's paths to match. Re-run after any change to the script or the unit;
installed units are copies, not symlinks.

Sampling is shared with xero's own stats via
[`tools/host-stats/`](../../tools/host-stats/README.md), and the publishing
shape matches [`projects/xero-stats/`](../xero-stats/README.md).
