# xero's UPS (CRU12V3A) dead - xero off until it is replaced
**Status:** Active
**Priority:** P1
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** chase Resonate for the CRU12V3A warranty repair (in progress since 2026-10-22)
- [ ] **Claude:** before the router goes back on a UPS, land the watchdog's ping signal ("Pi audio move follow-ups" step 3), or the watchdog goes blind
- [ ] **Claude:** when the UPS is back, restore a measured `DOWN_THRESHOLD_MIN` (10 min for now)
- [ ] **Together:** decide on a "UPS stopped charging" alert (the ESP32 UPS LED monitor idea would cover it)

**Why:** xero's RouterUPS (model CRU12V3A, 12V 3A) failed on 2026-10-08 and took xero down uncontrolled. Without a UPS, a mains cut crashes xero uncontrolled.
**State:** the UPS is dead (all four LEDs off on mains, with a different socket and a different adapter - getting no input or failed (fuse/charger), not just a flat battery). The router's mini UPS now backs xero, and the router and ONT run with **no UPS** (user, 2026-10-22); the CRU12V3A is with Resonate under warranty and the user is chasing them. Power watchdog shutdown threshold is temporarily 10 min. Do not re-run full-load tests on the pegboard (94°C and climbing).

#### Decision while the UPS is out (user)
xero stays off rather than run without a UPS. Meanwhile: DNS falls back to the wol Pi's Pi-hole (LAN and, via the stopgap, the tailnet); HA, voice, Vaultwarden (clients keep an offline cache), ntfy, MirAIe-via-Mosquitto, cron jobs and backups are all down; healthchecks.io will alert on the missed heartbeat. (Superseded the same day - see Log: the user turned xero back on without a UPS.)

#### Shutdown threshold
`DOWN_THRESHOLD_MIN` in `watchdog_power.sh` cut 200 -> 10 min (user's call): frequent short cuts still ride through on whatever UPS xero is on; longer ones get a clean shutdown and rely on the wol Pi's WoL to boot xero after mains returns (xero's PSU never sees AC loss while a UPS holds it, so BIOS AC-restore will not). Side effect: an accidental extender switch-off (2026-08-28) now shuts xero down after 10 min instead of 200. Restore a measured threshold when the replacement UPS arrives.

#### Checks when xero is back on a UPS / after a power loss
`zpool status` (uncontrolled power loss), check containers, start `pihole` if Docker leaves it stopped.

#### Log
- 2026-10-08: a mains power cut earlier in the day (xero was off the UPS for memtest then), then xero went back on its RouterUPS. That afternoon the UPS did not charge, and at about 17:11 it cut out under a memtester full-load test, taking xero down uncontrolled (memtester had found 0 errors; the CPU was at 94°C and rising on the pegboard). Afterwards **all four of the UPS's LEDs stay off on mains**, with a different socket and a different adapter. The power watchdog could not see this: mains stayed up, and it only watches for a mains outage. Decision: xero stays off.
- 2026-10-08: shutdown threshold cut 200 -> 10 min (`DOWN_THRESHOLD_MIN`).
- 2026-10-22 (user): the CRU12V3A is out for warranty with Resonate; xero runs on the router's mini UPS, the router on none. A ~56min outage that afternoon: watchdog shut xero down cleanly after 10min; WoL failed to bring it back (fixed, see "Power-outage watchdog" Log).
- 2026-10-08 (same day): the user turned xero back on **without a UPS** at about 19:15. Checked 21:14: `zpool status -x` healthy, all 16 containers up (pihole included), every HA integration loaded - the post-power-loss checks are done for this boot. A mains cut now crashes xero uncontrolled.
