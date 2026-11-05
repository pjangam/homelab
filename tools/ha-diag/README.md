# ha-diag

Three Home Assistant questions that are awkward to answer from the UI.

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

`script_traces.py <script_id>` - a script's recent runs: start time (UTC),
whether it finished, who started it, and any step's error. HA keeps these
traces in memory only, so a restart loses them - check soon after a failure.
"Finished" with no error only means the service call was accepted: for
`play_bedroom_track` it means Spotify took the command, not that the speaker
you were listening to played (2026-11-05: it played on xero while the bedroom
Pi was off). Uses the host's `websockets` and `.env.healthcheck`'s `HA_TOKEN`.
Run on xero.
