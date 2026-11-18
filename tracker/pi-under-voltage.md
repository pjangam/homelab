# wol Pi under-voltage: official 5.1V supply
**Status:** Done

**Why:** the Pi reported under-voltage and throttling, not just historically: `vcgencmd get_throttled` = `0x50005` on 2026-09-24 and again on 2026-10-02 (boot of 2026-10-01). It was `0x0` on 2026-09-23. It now plays the bedroom white noise and Spotify, and sustained low voltage risks audio glitches and SD-card corruption. The earlier fix (a new cable, 2026-08-26) did not hold.
**Outcome:** verified 2026-10-09 - the official Raspberry Pi 5.1V supply (in since 2026-10-05) fixed it. Never under-voltage since monitoring began on 2026-10-06; `docs/hardware.md` Power row updated. Ongoing watch is "wol Pi health monitoring".

#### Cause
User, 2026-10-02: it ran from a 5V phone charger. A Pi 3B wants 2.5A, and the official supply runs at 5.1V so the cable's voltage drop still leaves 5V at the board.

#### The fan is not a factor
User, 2026-10-08: the Pi's GPIO fan came off earlier, when xero became the main server, and under-voltage kept appearing without it until the 5.1V supply went in. So the supply is what fixed it, and the fan's removal does not flatter the verdict. (Lines elsewhere in this file about the fan's extra load describe the Pi before that.)

#### Parts
```parts
qty | item | est | note
1 | Official Raspberry Pi power supply, 5.1V 2.5A micro-USB | 500-800 | the Pi 3B's micro-USB one, not the USB-C supply for Pi 4/5
```

#### Log
- 2026-08-26: earlier fix, a new cable; it did not hold.
- 2026-10-05: **supply swapped** to the official Raspberry Pi 5.1V supply. Booted on it at 07:48; at 22:30 `get_throttled` = `0x0` with no kernel under-voltage lines since boot - but no night of white noise yet. A temporary cron watch started on xero.
- 2026-10-06: the temporary cron watch was replaced by permanent monitoring, "wol Pi health monitoring" below. The Pi now reports its power flags every minute to HA, and healthcheck.sh alerts (email + ntfy) once per Pi boot if under-voltage appears. The watch's 50 samples (2026-10-05 22:45 to 2026-10-06 11:00) were all `0x0`; its log is `pi-undervoltage.log` on xero.
- Planned next step (was): around 2026-10-09, open the wol Pi device in HA (or the Stats dashboard tile "Under-voltage since boot"). If it has stayed off through nights of white noise, mark this Done and update the Power row in `docs/hardware.md` to "official supply, verified". If it alerts, the supply was not the whole story - suspect the cable, then load (the GPIO fan, USB devices).
- 2026-10-09: **verified - Done.** HA history of `binary_sensor.wol_pi_under_voltage` and `..._since_boot` since monitoring began on 2026-10-06: never `on` (only off/unavailable/unknown), through three nights of white noise and a reboot after the 2026-10-08 power cut; 0 kernel under-voltage events since that boot. The 5.1V supply fixed it. `docs/hardware.md` Power row updated.
