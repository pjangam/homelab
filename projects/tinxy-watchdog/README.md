# Tinxy watchdog (ISP-outage auto-restart)

One script, `watchdog_tinxy.sh`, run every 5 minutes by a `systemd --user` timer. A bandage for a
flaky ISP, meant to be removed once the line is stable - not permanent
infrastructure.


**Why:** a flood damaged nearby ISP infra, causing frequent connectivity drops. Tinxy is cloud-push (MQTT to `mqtt.tinxy.in`), so every ISP blip makes all Tinxy devices show "unavailable" in HA until the MQTT client reconnects on its own. `watchdog_tinxy.sh` restarts the `homeassistant` container only if that reconnect doesn't happen — it's a bandage for the ISP issue, meant to be disabled once it's resolved.

**How it works:**
1. Every 5 minutes (cron), the script tails `HOMEASSISTANT_CONFIG/home-assistant.log` for the Tinxy coordinator's own signal lines: `Tinxy: MQTT disconnected – marking all N relays offline` (down) vs `Tinxy MQTT: connected to ...` (up).
2. If the most recent of those two lines is a "disconnected", it starts a clock in `~/.cache/tinxy-watchdog/down-since`.
3. Only after **20 continuous minutes** of disconnection does it run `docker restart homeassistant` — short blips (the common case with a flaky ISP) resolve on their own and never trigger a restart. After restarting, it resets the clock so it won't restart again for another 20 minutes if the ISP is still down.
4. All actions are logged via `logger -t tinxy-watchdog` (`journalctl -t tinxy-watchdog`) and to `tinxy-watchdog.log` in the repo root.

**Disable / re-enable** (no need to touch cron):
```bash
touch ~/.tinxy-watchdog-disabled   # disable
rm ~/.tinxy-watchdog-disabled      # re-enable
```

**Schedule:** every 5 minutes as the `systemd --user` timer `job-tinxy-watchdog` (since 2026-11-18, was cron), defined in `projects/jobs-dashboard/jobs.toml`. `systemctl --user list-timers job-tinxy-watchdog` shows the next run.

