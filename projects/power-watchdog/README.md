# Power watchdog (clean shutdown on extended outage)

One script, `watchdog_power.sh`, run from xero's crontab. It is **armed**: on a
real extended outage it shuts xero down rather than only logging.


**Why:** this server runs on its own UPS battery (separate from the router's). If the battery fully drains before mains returns, the server crashes uncontrolled - the likely cause of ZFS corruption found in `datapool` on 2026-07-12. `watchdog_power.sh` shuts the server down cleanly well before that happens instead.

**How it works:**
1. Every 5 minutes (cron), checks `/sys/class/net/enp1s0/carrier` - `enp1s0` connects through a WiFi extender with no battery backup of its own, so losing carrier is a reliable proxy for "mains is out, running on UPS battery." Since 2026-10-17 xero is cabled to the router instead. That still works while the router has **no UPS** (its mini UPS is backing xero while xero's own is out for warranty, 2026-10-22): the router dies with mains and takes the carrier with it. Once the router is back on a UPS, the carrier stays up in an outage and the watchdog needs the ping signal (`PROJECTS.md` "Pi audio move follow-ups", step 3).
2. On carrier loss, starts a clock in `~/.cache/power-watchdog/down-since`.
3. Once down for **10 minutes** (`DOWN_THRESHOLD_MIN` in the script), runs `sudo /usr/sbin/shutdown -h now`. It was 200 minutes, from a live outage test on 2026-07-31 (~288 minutes real runtime on xero's own UPS); cut to 10 on 2026-10-08 when that UPS died and power cuts became frequent. Raise it again once a replacement UPS's runtime is measured.
4. All actions logged via `logger -t power-watchdog` (`journalctl -t power-watchdog`) and to `power-watchdog.log` in the repo root.

**Currently armed** - this will actually shut the server down on a real extended outage, not just log.

**Arm / disarm** (no need to touch cron):
```bash
touch ~/.power-watchdog-armed        # arm (enables the real shutdown)
rm ~/.power-watchdog-armed           # disarm (back to dry-run/logging only)
touch ~/.power-watchdog-disabled     # fully disable (skips the check entirely)
rm ~/.power-watchdog-disabled        # re-enable
```

Arming for the first time also requires a one-time sudoers setup (installed by `new_machine_setup.sh`) granting passwordless sudo for `/usr/sbin/shutdown -h now` only, since the watchdog runs unattended from cron.

**Known gap:** a graceful shutdown here doesn't automatically solve "how does the server turn back on" once mains returns - since the UPS keeps the server's PSU continuously powered throughout (before, during, and after the shutdown), the BIOS's "Restore on AC Power Loss" setting never actually triggers (it only fires on a genuine AC-loss-then-restore event at the PSU, which doesn't happen here). See the "Power-outage watchdog" entry in `PROJECTS.md` for the current plan (Wake-on-LAN via a mains-powered ESP32, in progress under `esp32/wol_on_boot/`).

**Cron entry** (`crontab -e`):
```
*/5 * * * * /home/pramod/code/homelab/projects/power-watchdog/watchdog_power.sh >> /home/pramod/code/homelab/power-watchdog.log 2>&1
```

