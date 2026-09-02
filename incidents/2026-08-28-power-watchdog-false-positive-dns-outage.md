# 2026-08-28: WiFi extender switched off by accident triggers a real (unnecessary) clean shutdown, ~2h10m of LAN-wide DNS outage

**Symptom:** `xero` shut itself down cleanly at 20:50, taking Pi-hole (and therefore LAN-wide DNS) down with it for roughly 2h10m, with no actual mains/UPS power problem behind it. Neither of the two auto-recovery paths (BIOS "Restore on AC Power Loss", the Pi's boot-time WoL sender) fired to bring it back - required physically reinserting the power cable.

**Root cause:** the power-outage watchdog's only signal is carrier-loss on `enp1s0` (a proxy for "on battery," via the WiFi-failover extender that provides xero's ethernet uplink). At 17:26, someone accidentally switched off that extender - not a power outage, but from the watchdog's point of view it's indistinguishable from one, since it only ever sees "the interface lost carrier." It followed its normal logic exactly as designed: waited the full 200min threshold, then ran a real clean shutdown at 20:50.

That correct-per-its-own-logic shutdown then exposed the actual gap: **because xero's own PSU never lost power at any point**, neither auto-recovery mechanism had anything to trigger on:
- BIOS "Restore on AC Power Loss" only fires on a genuine AC-loss-then-restore event at the PSU - there wasn't one.
- The Pi's `wol-xero.service` only sends its magic packet on the Pi's own boot - the Pi never lost power either, so it never rebooted, so it never re-sent the packet.

**Timeline:**
- **17:26** - `enp1s0` lost carrier (WiFi extender switched off by accident, not a real outage).
- **17:26-20:50** - watchdog waited out the full 200min threshold with no way to distinguish this from a real outage.
- **20:50** - watchdog ran a real, intentional clean shutdown (`sudo shutdown`, per its armed config) - this is the watchdog working correctly, not a bug.
- **20:50-23:00** - `xero` off. Pi-hole down with it → LAN-wide DNS outage for the full window. Neither BIOS AC-restore nor the Pi's WoL sender fired, for the reason above.
- **23:00** - brought back by physically reinserting xero's power cable.

**Fix:** none needed for the shutdown/DNS-outage itself - root cause was human error (the extender switch), not a watchdog bug; the watchdog's carrier-loss logic is working as designed and correctly can't distinguish this class of event from a real outage with its current signal. Note for next time this happens: since xero's outlet never actually lost power in this scenario, `Wake-on: g` would have stayed live the whole time - a plain `wakeonlan 68:1D:EF:38:8C:72` from the Pi or any other LAN box likely would have brought it back immediately, without needing to touch the power cable at all.

Two real follow-ups opened from this incident (both in PROJECTS.md under Power-outage watchdog):
1. **Carrier-loss/restore email notifications** - `cron/watchdog_power.sh` now emails on the two transition moments it already logs, so a future false-positive-driven wait/shutdown is visible immediately instead of only discovered after the fact. Explicitly a trial, being evaluated for signal-vs-noise before deciding to keep it long-term.
2. **Power-watchdog HA sensor** - `power_on_battery` / `power_down_minutes` added to the existing MQTT healthcheck publish, so this state is visible on the dashboard in real time rather than only in the log file.

**Prevention:** the watchdog still can't distinguish "extender switched off" from "real outage" - that's an inherent limitation of carrier-loss-on-`enp1s0` as the only signal, not something either follow-up above actually fixes. The two action items make a repeat of this class of event visible sooner (email at the moment of carrier-loss, not just after a 200min wait) and give a faster manual recovery path (a plain `wakeonlan` instead of a physical cable reseat), but don't prevent the underlying false trigger from happening again.
