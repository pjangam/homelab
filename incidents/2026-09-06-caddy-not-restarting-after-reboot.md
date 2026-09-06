# 2026-09-06: Caddy doesn't come back after a reboot, because renewing the cert marked it "manually stopped"

**Symptom:** after the morning power-outage shutdown and subsequent reboot, ntfy/email alerted `Container caddy is exited (Exited (0) 4 hours ago)` and the Home Assistant healthcheck sensor went red. Ten of eleven containers came back on their own; only `caddy` stayed down. Nothing in caddy's own logs suggested a fault - its last line was a clean `shutdown complete, signal=SIGTERM, exit_code=0`.

**Root cause:** `cron/renew_certs.sh` reloaded Caddy after installing a new cert with `docker kill --signal=USR1 caddy`. **Any `docker kill` sets Docker's internal `HasBeenManuallyStopped` flag on the container - even a signal like `USR1` that leaves it running.** With `restart: unless-stopped`, Docker honours that flag and refuses to start the container again, at daemon start or at boot. So every successful cert renewal silently guaranteed that caddy would not come back after the next reboot, with no symptom in the meantime.

Confirmed three ways:
- `HasBeenManuallyStopped` was `True` for `caddy` and `False` for all ten other containers (read from `/var/lib/docker/containers/<id>/config.v2.json`).
- `dockerd`'s boot log never mentions caddy at all - it wasn't attempted and failed, it was skipped entirely.
- Reproduced on a throwaway container: `docker run -d --restart unless-stopped` -> flag `False`; `docker kill --signal=USR1` -> flag `True`, container still running.

**Why it surfaced now and not earlier:** cert renewal had been failing silently for three months and was fixed on 2026-09-04 (`65656a1`, see `2026-09-04-tls-cert-renewal-silently-broken.md`). The bug was latent that whole time precisely *because* renewal never ran. Renewal then worked on 2026-09-04 23:56 and 2026-09-06 05:00, and this morning's outage shutdown was the first reboot after a working renewal. Fixing cert renewal is what activated this.

**Timeline:**
- **2026-09-06 05:00:02** - weekly renewal runs (`0 5 * * 0`), logs `signalled caddy to reload`. Caddy keeps serving normally; the manual-stopped flag is now set, invisibly.
- **~05:40** - mains power out; `enp1s0` loses carrier and the power watchdog starts its clock.
- **09:00:02** - watchdog crosses its 200min threshold and shuts the server down cleanly. Docker stops all eleven containers; caddy exits 0 on SIGTERM like everything else.
- **11:55:46** - server booted back up by hand (see the manual-power-on notes in PROJECTS.md).
- **11:56:08** - `dockerd` restores containers. Ten start. Caddy is skipped, because Docker believes a human stopped it on purpose.
- **12:00 onwards** - `healthcheck.sh` (every 15min) reports `Container caddy is exited`, emails/pushes the alert, and publishes `overall_problem` over MQTT, turning the HA healthcheck sensor red. This part worked exactly as intended - the alert was correct and arrived within 15 minutes.
- **12:52** - `docker start caddy` brings it back; confirmed serving (`https://xero.<tailnet>/projects/` -> 200) and the manual-stopped flag resets to `False`.

**Fix:** `cron/renew_certs.sh` now reloads through Caddy's own admin API instead of signalling the container:

```
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --address 127.0.0.1:2019
```

This never touches Docker's container state. `--address` is passed explicitly because `localhost` resolves to `::1` first inside the container while Caddy's admin endpoint binds `127.0.0.1` only - the default fails with connection refused, which would have turned a silent landmine into a loud but unnecessary renewal failure.

Verified end to end: the reload succeeds, `HasBeenManuallyStopped` stays `False` afterwards, caddy keeps serving (200), and a full `./cron/renew_certs.sh` run completes with `exit=0` logging `reloaded caddy via admin API` and leaves the flag clean.

**Note on the alert itself:** the healthcheck alert was accurate and timely. The gap wasn't detection, it was that the failure was created a week ahead of when it fired, by an unrelated-looking job, with no symptom in between.

**Two adjacent risks found while investigating - both fixed the same day:**

1. **`new_machine_setup.sh` still installed the old crontab line**, complete with `sudo docker kill --signal=USR1 caddy`. The live crontab was replaced on 2026-09-04 but the provisioning script wasn't, so setting up a new machine would have reintroduced both the original silent-renewal-failure bug and this one. Replaced with the weekly `cron/renew_certs.sh` entry that actually runs on this machine, with the `grep -v` filter widened to match both the old and new entries so re-running stays idempotent. Note the one remaining manual prerequisite, now called out in a comment there: `tailscale set --operator=$USER`, without which renewal fails on every cron run.
2. **`cron/backup_vaultwarden.sh` was exposed to the same class of failure.** It runs `docker stop vaultwarden` -> `tar | gpg` -> `docker start vaultwarden` under `set -euo pipefail` with no guard. If the backup step ever failed, the script would exit with vaultwarden stopped *and* flagged manually-stopped - so it would have stayed down through the next reboot too, same as caddy did here. Fixed with `trap 'docker start vaultwarden ...' EXIT` set *before* the stop, so the restart happens on every exit path.

`scripts/test_backup_restart_guard.sh` covers that guard against real Docker on a throwaway container, rather than running the real backup (which would stop the live vaultwarden and upload to the rclone remote). It asserts the failure path restarts and leaves the flag clear, the success path still works with the trap in place, and - as a regression baseline - that an unguarded stop/fail really does leave the container both stopped and flagged. All six checks pass.

**Prevention:** the general rule this incident establishes - **don't use `docker kill`/`docker stop` as a way to signal or cycle a long-running container that relies on `restart: unless-stopped`.** Use the service's own reload mechanism where it has one. Where a genuine stop/start is unavoidable (the vaultwarden backup above), guard the restart with a `trap ... EXIT` so a mid-script failure can't leave the container both stopped and flagged.
