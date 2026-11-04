# host-stats

`host_stats.py` - the per-second sampler shared by
[`projects/xero-stats/`](../../projects/xero-stats/README.md) and
[`projects/pi-health/`](../../projects/pi-health/README.md). Both publish once a
minute, and a value read once a minute (or HA System Monitor's average over its
poll) hides exactly the spikes worth seeing - so a background thread samples
every second and each report gives the **p95 and the max** of the minute.
Never an average.

`thermal_load_test.sh` - repeatable cooling benchmark for xero: pin every core
for a duration, then watch the cool-down, sampling `x86_pkg_temp` and average
core clock. Run it before and after a cooling change. It stops early at
`ABORT_C` so [`services/immich/load_guard.sh`](../../services/immich/README.md)
never trips; when that happens, "time to ABORT_C" is the number to compare
instead of the peak. Past runs are in `results/`.
