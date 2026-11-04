# xero stats as percentiles

xero's CPU, temperature, memory and CPU pressure on the dashboards as **p95 and
max of each minute - never an average**. A minute at 50% could be a steady 50%
or thirty seconds pinned at 100%, and only the second one matters. Started
2026-10-09; it replaces HA System Monitor's processor use, processor
temperature and CPU pressure.

`xero-stats-mqtt.py` runs on xero as the `systemd --user` unit
`xero-stats-mqtt.service`, publishing one retained JSON object a minute with HA
discovery - the same shape as [`projects/pi-health/`](../pi-health/README.md),
sharing the per-second sampler in
[`tools/host-stats/`](../../tools/host-stats/README.md).

`enable_drivetemp.sh` loads the `drivetemp` kernel module now and at every
boot, so the SATA disks expose a hwmon temperature this can read without root.
Run it from a real terminal (it sudo-prompts), then
`systemctl --user restart xero-stats-mqtt`.
