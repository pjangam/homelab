# Move xero's datapool SSD out of the case
**Status:** Active
**Priority:** P1
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** wall hooks for the SSD - it is out in open air but resting loose, not mounted
- [ ] **Pramod:** add a dust clean to the routine now that the case stays open (the blower pulls dust straight onto the board; last clean 2026-08-21)

**Outcome so far (2026-11-08):** the SSD is **out of the case in open air** and the heat problem is **mostly** solved (a full scrub still reaches 70°C, 2026-11-11 below) - a 20.7GB read at 282 MB/s peaked at **60°C**, against **85°C** at 284 MB/s with the drive in the cover. 25°C lower at the same load, and 10°C under the 70°C rating. Not closed: the SSD is resting loose rather than mounted (wall hooks pending).
**The case stays open permanently** (user, 2026-11-08): the ribbon's 22-pin connector is far too bulky for the cover's vent slots, and notching the cover enough to pass it was not worth it. Accepted, not a pending task - do not 'fix' this later. It also helps the CPU (58°C -> 54°C idle, both faces now in open air). The cost is dust on an exposed board and blower.

**Why:** the Kingston SA400 (`sda`, the whole of `datapool`) is rated to 70°C and keeps passing 80°C under long reads: 81-87°C on 2026-10-22 and 2026-10-26, 85°C on 2026-11-08. It is screwed into xero's plastic bottom cover, which faces the Skadis board with only the rubber feet for a gap, and nothing moves air over it. Split out of "xero cooling on the Skadis pegboard" on 2026-11-08 and raised to P1 (user), because it is the cheap, independent fix and the incidents keep coming even in winter. The CPU side (standoffs, USB fan, thermal paste) stays in that entry.

#### Incidents
| Date | Peak | Cause |
|---|---|---|
| 2026-10-22 | 84-87°C | long bulk reads (Takeout SHA-1, uploads, ffmpeg checks) |
| 2026-10-26 | 81-82°C | 4GB GoPro upload, then Immich conversion and ML |
| 2026-11-08 | 85°C (00:41) | **monthly ZFS scrub**, 00:24-00:41:54, reads ~300MB/s; above 80°C for ~11 min |

- **The scrub recurs:** Ubuntu's `zfsutils-linux` cron scrubs every pool on the **second Sunday of each month**, at 00:24 by default; being moved to the second **Wednesday at 04:00** (`tools/zfs/scrub_time.sh`), when no other job runs and nobody is up. Next after the move: 2026-12-09. Each one reads all used data (~300G today, more after the Takeout import), so it will run longer and hotter as the pool fills.
- It found nothing wrong (`repaired 0B ... with 0 errors`); the heat is the only problem.

#### Plan
The stock lead is the short blue flex ribbon at the case edge (`docs/images/xero/case-open-ram-slot.jpg`), only long enough for the bottom cover to open like a lid. Running the pool off it with the cover off, or pulling it outside, risks tearing it, and datapool is a single disk with no mirror.
- **Cable:** a **22-pin SATA extension, male to female** (data and power in one cable), 20-30cm, about ₹200-400 at a local shop. A 7-pin data-only cable will not work. It plugs into the ribbon's connector, so the ribbon stays where it is. First check whether the ribbon reaches outside the case with slack and the cover closed; if it does, no extension is needed (unlikely).
- **Route:** out through a gap at the cover's edge, or a small notch if there is none. Tie the cable to the board 5-10cm from the SSD, leaving a loose loop, so a tug pulls on the tie and not on the connectors.
- **Mount:** zip-ties through two Skadis holes, one near each end of the SSD, not tight enough to flex its plastic case (velcro straps if it should come off without cutting). Upright on its long edge, about 1cm off the board, beside or below xero, out of the CPU exhaust and not above it. **Connector end down or sideways**, never up, so dust does not settle into the joint. The drive itself is sealed, so dust only needs blowing off during the regular clean, across the joint without unplugging it.
- **Do it with xero fully shut down.**
- **Baseline (2026-10-26):** the kernel log has the SATA link up at 6.0 Gbps since the 2026-10-25 boot, with no resets or errors. `UDMA_CRC_Error_Count` still to be read (`sudo smartctl -A /dev/sda`, needs a real terminal).
- **After:** confirm the link is still 6.0 Gbps with no resets in `journalctl -k`, and the CRC count has not risen (if it has, the extension is bad). Then run the 20GB datapool read and compare the Kingston's peak with 81-82°C. The mirror's second SSD can go outside the same way later.

#### Done when
- The SSD is outside the case on the Skadis, the SATA link is 6.0 Gbps with no resets, and the CRC count has not risen.
- A 20GB datapool read, or the next scrub, keeps the Kingston under ~70°C (`node_hwmon_temp_celsius{chip="target0:0:0_0:0:0:0"}` in Prometheus).
- `docs/hardware.md`'s xero entry notes the SSD's new position.

#### Log
- 2026-11-08: split out of "xero cooling on the Skadis pegboard" at P1 (user) after the monthly scrub took the SSD to 85°C. Plan moved here unchanged.
- 2026-11-08: the disk was idle (0 MB/s, 45°C) until the scrub started, so the scrub alone caused it. User asked to move it to ~03:00; `tools/zfs/scrub_time.sh` written (the 01:30-05:30 window reads under 2MB/s).
- 2026-11-08: user: no overlap with any other job. 03:00 (HA backup, Immich integrity, e2scrub) and 03:30 (backups) are taken; **04:00 chosen** (the Glacier archive at 04:00 runs on the 1st only). Job table in `tools/zfs/README.md`.
- 2026-11-08: user: Saturday or Wednesday instead of Sunday. **Wednesday 04:00** chosen (a work night); `scrub_time.sh` now takes the day too.
- 2026-11-08 02:07: user ran `set 04:00 wed`; verified both lines read `0 4 ... -eq 3`. Run before 11 Nov, so a scrub is due Wed 2026-11-11 04:00, three days after the last.
- 2026-11-08: user leaves the 11 Nov scrub as is and aims to move the SSD before then.
- 2026-11-08 12:17: **moved.** The stock flex ribbon reached outside with the case open, so **no 22-pin extension was needed** - that open item is dropped. The SSD now sits in open air; wall hooks still to do.
- 2026-11-08: **the case will not be closed.** The ribbon's 22-pin SATA connector will not pass through the cover's air vents, and cutting a notch big enough for it was rejected. The user's call, and it is a decision rather than an open item: the cover comes off for good. Keep the cover - the SSD's original mounting holes are in it, so it is the rollback path. Dust is now the maintenance item.
- 2026-11-08 12:32: **measured, and it works.** `tools/host-stats/disk_thermal_test.sh` read 20.7GB at **282 MB/s** (the 2026-11-08 scrub managed ~284 MB/s, so like for like) and peaked at **60°C**, against 85°C in the cover. Idle fell 49°C -> 33°C, now equal to the boot SSD, so the dead-air penalty is gone. `ssd-temp-guard` never fired - the drive never reached 70°C.
- 2026-11-08: post-move health all clean: SATA link still **6.0 Gbps** both links, **0** ATA errors since boot, pool ONLINE with **READ=0 WRITE=0 CKSUM=0** after the 20.7GB read. The pre-move `UDMA_CRC_Error_Count` baseline was missed, but it is moot: ZFS checksums every block, so 20.7GB read with zero CKSUM errors is a stronger proof of the SATA path than a CRC delta would have been.
- 2026-11-08: the first test run was **invalid and nearly recorded as a success** - it reported 51°C at 19 MB/s. `dd` counts blocks not bytes and a pipe short-reads, so `count=N bs=1M` stopped after ~285MB; and `tar` over a photo library managed 19 MB/s. Fixed with `iflag=fullblock` and whole-file reads. A thermal result is only meaningful next to the MB/s it was taken at.
- 2026-11-17: **First real scrub after the move (Wed 2026-11-11 04:00, 305G):** 34°C -> 69°C in ~7 min, guard clamped at 04:08:29 (`zfs_vdev_max_active` 1000 -> 4), then held **69-72°C for 20 min** until the scrub ended at 04:28 and the guard released. Scrub took 28m08s (17m53s unclamped on 2026-11-08), 0 errors. Open air alone is not enough for a full scrub: the 60°C test was a 20GB / ~75s read, too short to heat-soak. `CLAMP=4` stops the climb but does not cool the drive below 70°C. Follow-up is on "datapool SSD temperature guard".
