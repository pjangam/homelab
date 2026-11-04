# ha-diag

Two Home Assistant questions that are awkward to answer from the UI.

`unavailable_now_vs_before.sh` - every entity unavailable **right now**, next
to the states it had in an earlier window, so after a restart or an outage you
can tell what is newly broken from what was already dead (decommissioned Tinxy
devices, a dishwasher that is switched off). Prints `NEW` when the entity had a
real state in that window, else `was`. Run on xero.

`tile_tap_runs_script.py` - make every tile for a script run it on tap instead
of opening the more-info popup. Goes through HA's websocket API so **HA writes
`.storage` itself**: editing those files under a running HA just gets
overwritten, the same trap
[`projects/healthcheck/add_stats_dashboard_tile.py`](../../projects/healthcheck/README.md)
exists to avoid. Needs aiohttp, so run it with HA's own Python inside the
container.
