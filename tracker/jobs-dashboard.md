# Jobs dashboard in Grafana
**Status:** Active
**Priority:** P2
**Cost:** ₹0 (software only)
**Effort:** ~3 evenings left (scrub/TRIM, phases 2-4)

#### Open items
- [ ] **Claude, 2026-11-20:** check the first nightly runs under timers: Vaultwarden 02:00, HA 03:00, hardware.md 03:30, documents 03:45, spotify-songs 04:30 (`backup.log`, dashboard rows no longer "not run yet", healthcheck backup ages)
- [ ] **Claude, 2026-12-01:** check `glacier-archive`'s first run from its timer (04:00, hours; `backup.log`)
- [ ] **Pramod:** decide whether healthcheck should alert on a failed `job-*` run (left out of its failed-units check for now, to keep alerting unchanged)
- [ ] **Claude, after 2026-11-25:** remove the Diwali one-off, the crontab's last line
- [ ] **Claude:** phase 1 remainder: scrub/TRIM read from `zpool status` (root's `/etc/cron.d`)
- [ ] **Claude:** phase 2: repo-owned long-running `systemd --user` units (allowlist)
- [ ] **Claude:** phase 3: the Pi: `--collector.textfile.directory` in `deploy_pi.sh` (no sudo), its crontab to timers, `watchdog_nodered.sh` into the repo
- [ ] **Claude:** phase 4: container jobs: HA backups, automations, recorder purge/DB size; Immich jobs and DB dumps; Pi-hole gravity; Watchtower
- [ ] **Claude, once the nightly backups have 20 runs:** read the "CPU per job" and "RAM and heat per job" tables with the user and decide whether any heavy jobs need moving apart (RAM and 1s CPU % p95 fill in from then)
- [ ] **Claude, when closing:** project README + `Readme.md` index line, `docs/hardware.md` (xero and Pi schedules), `services/grafana/README.md` (retention is ~60 days, not 90), `services/node-exporter/README.md`; fix the crontab comment that puts Watchtower at 04:00 (it runs 09:30 IST)

**Why:** nothing shows in one place what runs on xero and the Pi, when it ran, whether it worked and what it cost. The 2026-11-01 Glacier failure went unseen for a week, and the 2026-11-08 scrub slot was chosen by reading crontabs by hand (user, 2026-11-18: "is there a central dashboard of all jobs/crons running on xero").

#### Decisions (user, 2026-11-18)
- **Where:** a new "Jobs" dashboard in Grafana, built by `services/grafana/build_dashboards.py`.
- **Scope:** xero cron + timers; xero's repo-owned `systemd --user` units; the wol Pi; jobs inside containers (HA: backups, automations, recorder purge/DB size).
- **Mechanism: cron jobs move to `systemd --user` timers** (architecture review, 2026-11-18), generated from one `jobs.toml` by an install script. systemd records last/next run, result, CPU and peak memory of the whole process tree; each job gets its own journal; `Persistent=true` catches up runs missed while xero was off (no UPS). Replaces the planned `jobrun` cron wrapper and cron parser.
- **Alerting:** unchanged for now.
- **Retention:** Prometheus stays at 8GB, which is about 60 days (not 90).
- **`watchdog_nodered.sh`** moves from the Pi's home folder into the repo.

#### What each job shows
| Column | Source |
|---|---|
| Schedule, next run | `systemctl --user show` (`NextElapseUSecRealtime`) |
| Last start, duration, result | `ExecMainStartTimestamp`, `ExecMainExitTimestamp`, `ExecMainStatus`/`Result`; per-job `ok_codes` in `jobs.toml` (MirAIe's exit 2 = skipped) |
| Duration p95 and max | the collector's per-run history (`runs/<job>.jsonl`); p95 only with >= 20 runs, else max and last |
| Max CPU (last run) | highest 1s CPU of the run, % of one core (`record_run.sh` sampler) |
| Peak RAM (last run) | highest 1s `anon` of the job's cgroup: its own memory, no page cache |
| CPU per job table | CPU seconds p50/p95/max per run, CPU seconds on the busiest IST day and last 24h, 1s CPU % p95/max (runs of 1 s or more) |
| RAM and heat per job table | RAM p95/max, memory incl. cache max, CPU and Kingston temperature p95/max (runs of 60 s or more) |
| Per-run graphs | CPU seconds, peak RAM and busiest second of each run over time, for trends |
| Peak CPU and SSD temperature during the run | collector on xero asks Prometheus for `max_over_time` over the run window (Prometheus scrapes both hosts, so this covers the Pi too) |
| Log | the journal unit name, never log text in Prometheus (Grafana is viewable without login) |

#### Traps found by the review (2026-11-18)
- **Network ordering:** `After=network-online.target` is a no-op in user units; jobs that need the network wait in `ExecStartPre`.
- **Logs healthcheck reads:** backup-freshness reads `backup.log` lines, so those jobs keep appending there (`StandardOutput=append:`).
- **flock:** the Glacier job's `flock -n` is unneeded under systemd (a running unit is not started twice).
- **Scrub/TRIM:** root's `/etc/cron.d` lines start the scrub and return at once; read start/end/errors from `zpool status` instead (no sudo).
- **Container timezones:** Watchtower and Immich run on UTC (Watchtower's "04:00" is 09:30 IST); Pi-hole's cron is IST.
- **Pi memory:** 905MB with swap in use, so container jobs are polled every 15 min from file mtimes, not `docker exec` every minute.
- **Ghost rows:** the collector exports only units in `jobs.toml`; removed jobs disappear.

#### Log
- 2026-11-18: designed with the user; plan written for an architecture review before building.
- 2026-11-18: architecture review: build after fixes (Pi cannot reach Prometheus, Pi node-exporter has no textfile collector, a broken cron wrapper would stop every job, schedules that differ from their cron line). User chose `systemd --user` timers over the wrapper, kept 8GB retention, all HA job kinds, and moving `watchdog_nodered.sh` into the repo.
- 2026-11-18 12:29: **pilot live.** `projects/jobs-dashboard/` (`jobs.toml`, `install_jobs.py`, `record_run.sh`, `jobs_collector.py`); `tinxy-watchdog` moved from cron to `job-tinxy-watchdog.timer` (crontab saved first as `crontab.xero.before`), collector every minute into `services/node-exporter/textfile/jobs.prom`. First runs: exit 0, 0.2s CPU, 14MB peak, temps from Prometheus. systemd 255 drops `MemoryPeak` at stop (read in `ExecStopPost` instead) and user units have no io controller (no disk numbers).
- 2026-11-18 13:50: **Grafana "Jobs" dashboard live** (`https://xero.<tailnet>/grafana/`, uid `jobs`): jobs table (result, last start, duration, p95/max over 60 days, next run, failures in a row, CPU, peak memory, peak CPU and Kingston temperature), duration and failure graphs, CPU and SSD temperature with jobs shaded while they run (only runs over 10s). The collector's `job` label clashed with Prometheus's scrape label, renamed to `name`.
- 2026-11-19: pilot checked: 320 `tinxy-watchdog` runs, all every 5 min, none doubled. **Phase 1: all 14 jobs left in xero's crontab moved to timers** in one step (crontab emptied at 15:11:17, before the first shared minute; only the 25 Nov Diwali one-off left). Checked: every-minute and 5/15-min jobs ran clean under their timers; hardware.md backup, cert renewal and MirAIe renewal started by hand, all exit 0 (rclone, gpg, ssh to the Pi, Caddy's admin API all fine). Locale same as cron (`en_IN`), so `backup.log` parsing unchanged. Collector moved to :30 (at :00 it caught 5-min jobs mid-start and shaded a minute every 5); history files appended, pruned daily (a full rewrite every minute would have been ~13MB/min for every-minute jobs); healthcheck skips failed `job-*` units; glacier keeps `flock -n` against a manual run. Dashboard table sized to all jobs, "not run yet" for jobs without a run. `check_hardware_md.sh` reads `jobs.toml`; READMEs and script headers no longer say cron.
- 2026-11-24: **Jobs table CPU column is now Max CPU %** (user): the highest 1s CPU use of the last run, % of one core, instead of total CPU seconds. `record_run.sh start` runs as each unit's last `ExecStartPre` and samples the job's cgroup `cpu.stat` every second; `ExecStopPost` closes the last partial second (reading the counter before its own work) and writes it to the `.run` file; new metric `homelab_job_last_cpu_max_percent`. Tested: a 1-core burn reads 100%, an idle `sleep` ~1% (the sampler's own cost), sub-second runs get the whole-run rate and read high. Units reinstalled on xero.
- 2026-11-26: **60-day stats per job** (user: "understand which jobs are cpu intensive vs memory intensive... so that we can tune and schedule them"; architecture review first, all 10 findings applied). Two new tables, "CPU per job" and "RAM and heat per job" (p50/p95/max from the run history, never averages), plus per-run CPU, RAM and busiest-second graphs for trends. RAM is now `anon` sampled each second (user: "ram needed for the job", so two RAM-heavy jobs are not scheduled together); `memory.peak` (incl. page cache: backup-documents 328 MB) stays as a second column. Temperatures p95/max only from runs of a minute or more (user: the main pain so far, keep the data ready). Collector: one `systemctl show` for all units, stats cached in `stats.json` and recomputed hourly instead of re-reading every history file every minute - 0.6 to ~0.2 CPU-s a run, kept every minute (5 min would have missed runs of every-minute jobs); it now records its own runs. New `noop` job (`/bin/true`, every 5 min) as the hooks' overhead baseline. Unit tests: `test_jobs_collector.py` (18). Also: zpool-textfile every 15 min instead of every minute (2026-11-25).
