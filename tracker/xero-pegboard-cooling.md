# xero cooling on the Skadis pegboard
**Status:** Backlog
**Priority:** P2
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod, by December:** buy standoffs and a USB fan locally for the CPU side (the SSD move is its own entry: "Move xero's datapool SSD out of the case"; the SSD fan is deferred, see "SSD fan (deferred)" below)
- [ ] **Together:** CPU - standoffs + USB fan, or stand xero on its edge
- [ ] **Claude:** use the cool months for heavy jobs (Bhakti's Takeout import, transcodes to `copies=1`)

**Why:** xero runs hot where it is mounted. memtest86+ hit 103°C there on 2026-10-08 (a RAM bit flipped), against 86°C on the desk with the fan side in open air. Mounted with the fan side facing the board, the only gap was its rubber feet. Idle on the pegboard is 55-68°C, high for an N5105. **The SSD runs hot too:** the Kingston SA400 (datapool) reaches 81-87°C, against a 70°C rating, under long disk jobs (2026-10-22, 2026-10-26), and **85°C on 2026-11-08** under the monthly ZFS scrub. It is screwed into the plastic bottom cover, away from the CPU blower, so nothing moves air over it.
**State:** nothing built. Since the fan side was turned to face the room, the CPU has open air but the bottom cover, where the SSD is, faces the board with only the rubber feet for a gap. **The two sides compete for the open air:** whichever faces the board runs hot. Two stopgaps tried on 2026-10-08 (a makeshift stopper wedged between xero and the board for a gap - fragile; the room AC turned down - not bearable as a permanent setting); neither stays. **Deadline: before February 2027** (noted 2026-11-02): winter room temperatures hide the problem now, and it comes back with the Feb-March warm-up. The parts are cheap commodity items untouched by the chip-price spike, no reason to wait for prices.

#### Options
User, 2026-10-08: an external fan and better mounting are both on the table. Updated 2026-10-26 to cover the SSD as well: a mount has to give **both** sides air.
- **SSD: move it out of the case (main SSD option, 2026-10-26).** Zip-tie it to the Skadis in open air, on the stock cable plus an extension. Split out 2026-11-08 as its own P1 entry, "Move xero's datapool SSD out of the case". Fixes the SSD without changing how xero itself is mounted.
- **CPU: standoffs + USB fan.** Keep the fan side facing the room, push xero 3-4cm off the board, and have a USB fan blow through the gap across the bottom cover (the SSD side). Cools the SSD without taking air from the CPU.
- **Alternative: stand xero on its edge** on a Skadis shelf, held by a bracket or bookend so it cannot tip, so neither face touches the board. Both sides get open air, maybe no fan needed. It no longer hangs from its mounting holes, so it has to be held securely.
- **Ruled out: flipping xero so the SSD side faces the room.** That puts the CPU fan side back against the board, the setup that hit 103°C.
- **Not worth it:** a fan inside the case (no room, and the blower uses the only fan header); heatsinks or thermal pads on the SSD (the plastic cover has nowhere to send the heat); cutting vents in the cover.
- **Software limit: built 2026-11-08** as `projects/ssd-temp-guard/` (own entry, "datapool SSD temperature guard"), and more general than the rule sketched here: it clamps ZFS's `zfs_vdev_max_active` while the drive is over 70°C, so it catches **every** bulk job - scrub, backups, the S3 archive, an ffmpeg run - not just Immich. Pausing Immich alone would have missed the 2026-11-08 scrub entirely. Not installed yet (needs root).
- **Long term:** a Samsung 870 EVO or Crucial MX500 as the mirror's second SSD (see "ZFS mirror"). **The thermal gain is the metal case and real thermal throttling, not the DRAM cache** (corrected 2026-11-08): the SA400 has a plastic shell, which insulates the controller's heat in a bay that already has no airflow, and no meaningful thermal management, so it sails to 85°C instead of throttling around 70°C. The DRAM cache matters for random writes (ZFS metadata, Immich's Postgres), not for the sequential reads that caused both hot spells - a faster drive would run the same scrub at ~550 MB/s, drawing more power over a shorter burst, so it is **not** obviously cooler on this job. Buy it for uptime, endurance and power-loss protection; treat cooler peaks as a secondary benefit.
- **Sturdy standoffs** between xero and the board: M3/M4 nylon or brass standoffs, 3-4 cm, in xero's mounting holes (check the thread), or a Skadis shelf with xero standing on it, fan side out. Replaces the stopper.
- **External USB fan** (user: manageable, 2026-10-08): a 5V 80-120mm USB fan (roughly ₹300-800) clipped to the pegboard, moving air through the gap behind xero - ideally pulling the hot exhaust out rather than blowing at the case. Powered from one of xero's USB ports, so it is on whatever UPS xero is on and runs whenever xero does. Pick a quiet one (low RPM or with a speed switch); it is in the room.
- **New thermal paste** on the CPU (never redone; the 2026-08-21 clean was dust only). Likely the biggest single gain if idle stays in the 60s with good airflow.
- ~~**Turn the vented side away from the board**~~ - done before 2026-10-22 (the user turned the fan side to face the room). It moved the problem to the SSD side, see State.

#### SSD outside the case
Moved to its own entry, "Move xero's datapool SSD out of the case" (2026-11-08).

#### SSD fan (deferred 2026-11-17)
**Decision (user, 2026-11-17):** stay with `ssd-temp-guard` for now. Reconsider a fan if the drive causes an incident (guard alerts, SMART errors, a summer scrub it cannot hold) or once higher-priority work is done.
- **Why a fan might be wanted:** in open air a full scrub still reaches 70°C after ~7 min; the guard holds it at 69-72°C for ~20 min and slows the scrub (28 vs 18 min). SMART lifetime max is 90°C (before the move). Summer room temperatures are unmeasured.
- **Not an always-on fan** (user, 2026-11-17): it runs only when hot. Why: an always-on fan draws power all day and makes constant noise, both for nothing - the SSD is only hot during long bulk jobs (a monthly scrub, big imports).
- **A manual switch does not fit:** the hot jobs run unattended (the scrub at 04:00, imports overnight), and a fan left on after one is the always-on fan again.
- **A relay alone is not enough:** something has to read the temperature and decide.
- **xero cannot switch USB power:** both root hubs report "No power switching" (`sudo lsusb -v -s 1:1` and `2:1`, 2026-11-17), so `uhubctl` is out.

| Setup | Reads temperature | Decides | Needs xero? | Notes |
|---|---|---|---|---|
| **Thermostat module** (W1209, or a USB inline controller) + 5V USB fan | its own probe on the SSD | its own chip | No | Recommended. W1209 ~₹100-150 but runs on 12V (add a 5V-12V boost); USB inline controllers are mostly sold abroad. Fan ~₹200. Set ~60°C on |
| **xero + USB-TTL adapter (on hand) + MOSFET** | the drive's own sensor, already read by the guard | `ssd-temp-guard` toggles the adapter's RTS pin | Yes | Uses parts on hand, no probe. Off when xero is down (but then nothing is scrubbing) |
| **ESP32/ATtiny + DS18B20 + relay or MOSFET** | DS18B20 on the SSD | our firmware | No | A whole build for one fan; only if combined with another box (e.g. the USB charge switch) |
| Ready-made thermostat fan kit | built-in probe | built-in | No | ₹3,500+ (Amicikart 120mm) - too dear for this |

#### Done when
A full-load run (memtester 2 x 10G or a build) on the pegboard, at normal room temperature, stays under ~85°C, **and** a 20GB datapool read keeps the Kingston under ~70°C (`node_hwmon_temp_celsius{chip="target0:0:0_0:0:0:0"}` in Prometheus). The 90°C healthcheck alert covers it until then.

#### Log
- 2026-08-21: CPU cleaned (dust only, thermal paste not redone).
- 2026-10-08: memtest86+ hit 103°C on the pegboard (a RAM bit flipped), against 86°C on the desk. A memtester run that evening (2 x 10G, pegboard) climbed to 92-95°C even with both stopgaps in place.
- 2026-10-26: a 4GB GoPro upload, plus Immich's conversion and ML that followed, took the Kingston to 81-82°C for ~5 min (12:10-12:15). Photos show the SSD in the plastic bottom cover, which now faces the board. Flipping xero over ruled out (it puts the CPU back against the board). Options updated: standoffs + USB fan, or standing it on edge. Immich transcode policy set to `required` the same day to cut the disk load (see "Immich re-enablement").
- 2026-10-26 (later): main SSD option is now moving it out of the case onto the Skadis on a 22-pin SATA extension (see "SSD outside the case"). Baseline recorded: 6.0 Gbps link, no ATA errors this boot.
- 2026-11-08: the SSD move split out as its own entry at P1 (user), after the monthly scrub took the Kingston to 85°C.
- 2026-11-08: the software limit sketched above was built as `projects/ssd-temp-guard/` (own entry), throttling ZFS rather than pausing Immich so it catches every bulk job. The drive-choice note was corrected: the thermal argument for an 870 EVO/MX500 is the metal case and real throttling, not the DRAM cache.
- 2026-11-17: guard measured on the 2026-11-11 scrub: SSD in open air still reached 70°C after ~7 min; `CLAMP=4` held it at 69-72°C for 20 min. Details on "datapool SSD temperature guard".
- 2026-11-17: SSD fan deferred (user): `ssd-temp-guard` is enough for now. Options and the USB-switching test recorded under "SSD fan (deferred)".
