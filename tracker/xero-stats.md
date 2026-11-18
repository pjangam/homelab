# xero stats as percentiles (xero-stats)
**Status:** Done
**Priority:** P3

**Why:** the HA dashboards showed xero's CPU as System Monitor's average over its poll, CPU pressure as the kernel's 10s average and temperature as one reading a minute, so spikes never showed; the user, 2026-10-09: "never use average use percentiles". The wol Pi's tiles were averages too (its CPU read ~5% while the same minute's p95 was 35%, max 75%).
**Outcome:** done 2026-10-09. xero and the wol Pi publish p95/max per minute from 1s samples, and the Stats and Home dashboards use them.

#### What shipped
- `tools/host-stats/host_stats.py` samples every second.
- `projects/xero-stats/xero-stats-mqtt.py` (systemd --user on xero) publishes CPU, temperature, memory used and CPU pressure p95/max per minute to `homelab/xero/stats`.
- `projects/pi-health` uses the same sampler (its old average entities were deleted).
- Stats and Home dashboards switched over (`add_stats_dashboard_tile.py --replace` added for it).
- `healthcheck.sh` takes its temperature peak from `sensor.xero_cpu_temperature_max_1_min`.
- Disk usage stays a plain reading - it is a level, not something averaged.

#### Log
- 2026-10-09: the user asked for percentiles; done the same day.
- 2026-10-21: datapool's Kingston A400 stalled for 44s at 08:35 (ATA timeouts, link reset, 5 read / 2 write errors in `zpool status`; SMART, short self-test and CRC counters all clean, so a controller stall, not flash or cable). Added the SSD's temperature (p95/max, read every 10s in its own thread so a stalled drive cannot block the CPU samples; `projects/xero-stats/enable_drivetemp.sh` loads the module) and datapool's ZFS error counts, so a repeat shows when it happened and how hot the drive was. `healthcheck.sh` already alerts on an unhealthy pool via `zpool status -x`. drivetemp loaded and persisted the same day (SSD read 45°C); five tiles (SSD temperature p95/max, ZFS read/write/checksum errors) added to the Stats dashboard's System Monitor section, after the CPU temperature. Then, the same day, on the user's ask: HA's Stats dashboard is the high-level view and Grafana the detail. Stats keeps max tiles only (every p95 tile removed, xero's and the wol Pi's CPU too) and shows both SSDs by name (Kingston datapool, BIWIN boot) with max-only entities; Grafana's Hosts dashboard got SSD temperature (max and p95 overlaid, both drives) and ZFS errors panels. `add_stats_dashboard_tile.py --remove` added for it.
