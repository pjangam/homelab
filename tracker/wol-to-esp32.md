# Move WoL to an ESP32, put the Pi on the UPS (post-Ganapati)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹0-500 (₹0 on the bedroom satellite; a dedicated ESP32 otherwise)
**Effort:** ~1-2 evenings (firmware with the WiFi-wait fix, an outage test)

#### Open items
- [ ] **Together:** in the next real outage (or by switching off the extender and xero's UPS input), check whether the Pi's spot can still reach xero

**Why:** the wol-sender Pi has two jobs that want opposite power. Its WoL job only works *because* it is on mains, not the UPS: it has to lose power in an outage and boot when mains returns, so its boot-time packet wakes xero. Everything else it now runs does better if it stays up: the clawlight LED, the buttons, and Node-RED for the AC. Today all of that dies the moment mains drops, while xero carries on for up to 200min on its UPS. Split the jobs: a mains-only ESP32 sends WoL, and the Pi moves onto the UPS. For after Ganapati, when the aarti lights ESP32 can be freed for it.
**State:** idea only. The firmware is half there: `esp32/wol_on_boot/wol_on_boot.ino` was written for exactly this before the Pi stood in. It joins WiFi and broadcasts 3 magic packets to `192.168.1.255:9`, but needs the WiFi-wait fix below. The open question the whole idea stands on is whether the Pi can reach xero during an outage at all. If it can't, this idea mostly buys buttons and Node-RED that have nothing to talk to.

#### Firmware

**The firmware needs the lesson the Pi version already learned.** It gives up if WiFi has not connected within **30s**. After a real outage the router and extender take 60-120s to come back, often longer than the board takes to boot, which is why `update_wol_sender.sh` waits up to 2min for a real route. As written, the ESP32 would boot fast, give up and send nothing on exactly the event it exists for. It needs to wait at least as long as the Pi version does, or keep retrying until connected and then send.

**The ESP32 must stay off the UPS.** A USB charger on a plain mains socket. On a UPS it never loses power, never reboots, and never sends.

#### What staying up actually buys

Worth checking before the move, because it may be less than it looks:
- **The Pi's services all talk to xero.** The clawlight LED reads `clawlight/state` from Mosquitto on xero, the buttons publish to HA on xero, and Node-RED bridges to xero's broker. Once the watchdog shuts xero down at 200min, the Pi is up with nothing to talk to. The gain is the window **while xero is still running**, not the whole outage.
- **Can the Pi even reach xero during an outage?** The power watchdog detects an outage by `enp1s0` losing carrier, because xero's Ethernet uplink comes through the TP-Link extender, which is *not* on a UPS (proven by the 2026-08-28 false positive, when someone switched the extender off). If that link is down, the Pi on the UPS cannot reach xero at all, and the clawlight LED will just pulse "unknown". So check first how xero is reachable during a real outage, if at all. This is the question the whole idea stands on.
- **Don't break the watchdog's signal by fixing that.** If the extender gets moved onto a UPS so the LAN survives outages, `enp1s0` stops losing carrier and `watchdog_power.sh` loses the only way it knows mains is gone. That needs a replacement signal first, such as the ESP32 UPS LED monitor above or the mains-powered WoL ESP32 itself reporting that it is alive.
- **Clawlight from the Mac** also needs the router, the ISP and Tailscale, on top of xero.

**Also removes a fragile path.** The Pi no longer reboots on every outage, which is where its boot-order problems showed up (the overlayroot hang, and booting 4.5min after xero on 2026-09-06).

#### Which UPS, and what it costs

- **xero's RouterUPS:** its 288min runtime and the 200min threshold were measured with xero's load alone. The Pi plus fan is ~2.5W on top of xero's ~12W, which is roughly a fifth more load. Runtime drops by about that much, which would eat most of the ~88min margin. The threshold has to be re-measured or re-derived before the Pi goes on it, or the watchdog will shut down too late.
- **Output current:** a Pi 3B wants 2.5A at 5V. Mini-UPS USB ports are often 2A or less, and this Pi already has an undervoltage history (the wall-mount cable, fixed 2026-08-26). Confirm the port's rating and check `vcgencmd get_throttled` under load once it is moved.
- **The pegboard backlight idea** also plans to run the strip from the Pi. Its 5V supply must stay on mains, or the strip drains the UPS.

#### Verification

**Verify when built:** `scripts/wol-sender/wol_listener.py` on xero checks for a valid magic packet without shutting the server down. Do that first, then repeat the real end-to-end test from 2026-08-20: shut xero down, cut and restore mains to the ESP32 only. Also confirm a broadcast from WiFi reaches xero's wired port via the extender.

When done: `docs/hardware.md` (new board, Pi's power row, and `wol-xero.service` retired from the Pi) - see `CLAUDE.md`.

#### Parts

```parts
qty | item | est | note
1 | ESP32 dev board with USB | 400-600 | local - skip if the aarti lights board is freed after the festival
1 | 5V USB charger + cable (mains, not UPS) | 200-300 | household - likely already on hand
```

#### Log
- 2026-08-01: `esp32/wol_on_boot/wol_on_boot.ino` written for this, before the Pi stood in.
- 2026-09-16: idea noted, for after Ganapati.
- 2026-11-18: candidate board: the bedroom voice satellite (on mains, moving next to the bed; ESPHome `wake_on_lan`, wait for WiFi with no timeout). Either replacing the Pi's WoL or as a second sender. Raised in the `scene-remote.md` brainstorm; nothing decided.
- 2026-11-18: bedroom satellite **ruled out** as the WoL board (user): with battery power in the plans it would never lose power in an outage, so it would never reboot and send the packet. WoL stays on the Pi.
