# wol Pi health monitoring
**Status:** Done

**Why:** the Pi plays the bedroom white noise and Spotify, and has had under-voltage on two supplies. Nothing on xero could see the Pi's health except a temporary 15-minute ssh poll, and nothing recorded *when* a dip happened. Asked for 2026-10-06 as permanent monitoring, power first, with CPU, memory and temperature to follow.
**Outcome:** shipped 2026-10-06: `projects/pi-health/pi-health-mqtt.py` on the Pi publishes power, CPU, memory, temperature and disk to HA every 60s, shown in the "wol Pi" section of the Stats dashboard; `healthcheck.sh` alerts on under-voltage and on the Pi going unavailable. Left open: **dashboard only - nothing alerts on CPU, memory, temperature or disk yet;** if that is wanted, healthcheck.sh is where it goes (e.g. temperature, or disk over 90%).

#### Design
- `projects/pi-health/pi-health-mqtt.py` runs on the Pi as `pi-health-mqtt.service` (systemd --user, enabled; deploy with `projects/pi-health/deploy_pi_health.sh` from xero).
- Every 60s it publishes one retained JSON object to `homelab/wol_pi/state` on xero's Mosquitto, with a last-will on `homelab/wol_pi/available`.
- HA discovery makes a **wol Pi** device: Under-voltage (now / since boot), Throttled (now / since boot), Under-voltage events since boot (kernel log lines), Last under-voltage (timestamp), and diagnostics get_throttled, Booted, Last report. HA's history on these is the dashboard.
- Six of them are tiles in their own "wol Pi" section of the Stats dashboard (`add_stats_dashboard_tile.py --section-title "wol Pi"` adds more there): Under-voltage since boot, Under-voltage, Last under-voltage, Under-voltage events since boot, Throttled, Last report.
- CPU, memory, temperature and disk (same publisher, same 60s): CPU usage % (from `/proc/stat` deltas, so unknown for the first minute after a restart), Memory usage % (MemAvailable-based), CPU temperature °C, Disk usage % of `/` (the SD card). All have `state_class: measurement`, so HA keeps long-term statistics. Tiles in the "wol Pi" section.

#### Alerting
`healthcheck.sh` (xero, 15min) reads the entities back from HA. Under-voltage since boot = on alerts once per Pi boot; unavailable (the Pi off the network or the daemon dead) alerts too. Both tested: stopping the service took the entities to unavailable within seconds.

#### Gotcha
Kernel 6.18 logs "Undervoltage detected!" (hwmon), not "Under-voltage" - the old cron watch's `grep -ci under-voltage` would have counted 0 forever. The daemon matches both spellings. Its kernel count only covers the current boot: the Pi's journal is volatile.

#### Adding a metric
Set the field in `collect()` and add one line to `ENTITIES` in `pi-health-mqtt.py`, re-run `deploy_pi_health.sh`, then `add_stats_dashboard_tile.py <entity> --section-title "wol Pi"`.

#### Log
- 2026-10-06: asked for. Power monitoring shipped (under-voltage and throttling entities, Stats dashboard tiles, `healthcheck.sh` alerting).
- 2026-10-06: CPU, memory, temperature and disk added. First readings matched `free`, `df`, `vcgencmd measure_temp` and `top` on the Pi: CPU ~3%, memory ~50% of 905MB, 52.6°C, disk 34%.
