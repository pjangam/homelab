# 2026-07-31: Deliberate UPS-unplug test ends in uncontrolled crash (watchdog still unarmed)

**Symptom:** UPS deliberately unplugged at 16:55 to measure real battery runtime under load. The server ran until 21:43:40 (~288 minutes / 4h49m) before dying, uncontrolled - not a clean shutdown. It came back on its own around 22:30 with nobody touching the power button.

**Root cause:** not a bug - the power-outage watchdog (`watchdog_power.sh`) existed at this point but was still in dry-run (unarmed): it logs carrier-loss on `enp1s0` (the proxy signal for "on battery") but never actually calls `shutdown`. So it correctly detected the outage the whole time but, by design at that point, took no action - the server ran until the battery physically died rather than being shut down cleanly beforehand.

**Timeline:**
- **16:55** - UPS unplugged; `enp1s0` lost carrier, logged by the (unarmed) watchdog.
- **16:55-21:43** - a separate heartbeat logger (timestamping to local disk every 2s, independent of network state) kept running the whole time, giving an accurate independent record of when the machine actually died.
- **21:43:40** - machine went down hard - battery exhausted, no clean shutdown, ~288 minutes after the outage started. Far more runtime than the old "~3-4hr" guess this project had been using.
- **~22:30** - machine rebooted on its own with nobody touching the power button. Confirmed genuinely automatic with the user on 2026-08-26 (not a delayed manual press someone forgot about) - BIOS "Restore on AC Power Loss" is enabled by default on this board.
- **After reboot** - `zpool status` came back `all pools are healthy` despite the hard crash, likely thanks to `copies=2`/`sync=always` already being set on the Immich datasets - not something to rely on repeating for an arbitrary uncontrolled crash.

**Fix:** none needed for this event itself - it was the planned outcome of a deliberate test with the watchdog intentionally still unarmed, run specifically to get a real runtime number instead of a guess. Two real follow-ups came out of it:
1. Threshold updated from a 90min guess to **200min**, giving ~88min of real margin below the confirmed 288min failure point.
2. A new gap was found: a graceful shutdown before battery depletion doesn't actually get the server back on its own, since the UPS keeps the PSU continuously powered throughout (see "New gap found" in PROJECTS.md) - BIOS AC-restore has nothing to trigger on in that case. This is what drove the Wake-on-LAN sender project (see the 2026-08-28 incident below, which is the case where this gap actually mattered).

**Prevention:** the watchdog was armed shortly after (confirmed armed 2026-08-20: `~/.power-watchdog-armed` present, sudoers rule installed, cron live at `*/5 * * * *`), so a real outage from this point on triggers an actual clean shutdown at the 200min threshold rather than running to failure. See the 2026-08-28 incident for how that plays out once the WoL-based recovery path is also in place.
