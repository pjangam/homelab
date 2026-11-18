# Check if server RAM is expandable
**Status:** Done

**Why:** Immich re-enablement was blocked specifically on 8GB RAM being insufficient with ML enabled, then parked "at least a couple quarters" waiting for a full hardware upgrade due to the chip-price spike. If this Beelink Mini PC's RAM is actually expandable (a free/accessible SO-DIMM slot, not soldered), adding RAM alone could be a much cheaper and faster path back to Immich than waiting out the price spike for a whole new machine - but many ultra-compact fanless mini PCs in this class have soldered, non-expandable RAM, so this isn't guaranteed.
**Outcome:** **confirmed expandable (2026-08-21)** - RAM is a removable SO-DIMM (8GB DDR4 2666MHz), and xero has **one** SO-DIMM slot. A 32GB Crucial DDR4 SO-DIMM replaced the failing 8GB stick; it was cleared by memtester on 2026-10-09 (strong evidence, not a full clearance - see Log).
- Left open: one full clean pass on the UPS, then mount xero with the fan side facing open air, and plan new thermal paste (86°C at full load is high). Cooling is tracked in "xero cooling on the Skadis pegboard".
- The Immich parking decision was re-evaluated against this: with the 32GB stick in, Immich has run again since 2026-10-09 (see "Immich re-enablement"), with no wait for a whole new machine.
- Left open: 128GB is small for a boot drive running 7+ containers - worth keeping an eye on free space, though not urgent unless it becomes one.

#### Hardware found inside
- RAM: removable SO-DIMM, 8GB DDR4 2666MHz (the failing 8GB "Kingsotin", see `docs/incidents/2026-09-23-xero-kernel-oops-during-rust-build.md`). One slot only, so an upgrade is a swap to a larger single stick, not a straight add.
- Boot SSD: Biwin NP202 128GB.
- Intel lists the N5105 at 16GB max, but 32GB single sticks are widely run in N5105 mini PCs.

#### Temperature alerting
`healthcheck.sh` takes the peak of the HA System Monitor processor temperature sensor's history over its 15-minute window (plus sysfs `x86_pkg_temp`, so it works with HA down) and warns at 90°C, urgent at 98°C; `projects/healthcheck/test_cpu_temp_check.sh` exercises it. memtest86+ readings never reach HA (Ubuntu is not running).

#### Log
- 2026-08-21: opened the case. RAM is a removable SO-DIMM: 8GB DDR4 2666MHz. Also noted while inside: the boot SSD is a Biwin NP202 128GB.
- Next step at the time (was): price a second/replacement DDR4 2666MHz SO-DIMM (check whether the second slot is free for a straight add, or occupied meaning it'd need a swap to a larger single stick) and re-evaluate the Immich parking decision against that cost. Done as the 32GB replacement stick below; the slot question was answered by there being one slot.
- 2026-10-06: HA's history shows the heat happened in Ubuntu too: the System Monitor processor temperature sat at 85-103°C from about 20:45 to 22:45 IST, the evening the ESPHome compile on xero segfaulted in gcc, with the old stick still in. Before that the highest in 30 days was 86°C; back on the pegboard (tilted) it idles about 55-68°C.
- 2026-10-08: **replacement stick fails memtest.** A new 32GB Crucial DDR4 SO-DIMM, tested alone with memtest86+ 8.10 (`tools/memtest/boot_memtest_once.sh`), failed on the first pass: test 6 (moving inversions, 64-bit pattern), CPU 3, address `0x171beada0` (5.77GB), expected `...efff` found `...6fff` - one bit (bit 15) reading 0. Only error so far at pass 44%. With one slot there is no other slot to compare. The error is at 5.77GB, well inside 16GB, so capacity is not the lead.
  - Plan then: finish the pass, reseat, run two more full passes. The same address and bit again = a bad cell on the stick, return it. Different addresses or bits = contact, heat or the board.
  - **The CPU read 103°C during memtest** (N5105 TjMax 105°C; xero idles at 65-70°C, high for this chip), so heat became the lead suspect for this error and possibly for the 2026-09-23 crash under full-core load too. Next then: check the fan spins, re-test with the case open and a desk fan on it; consider new thermal paste.
- 2026-10-08, second run the same day: xero moved from its Skadis pegboard (fan side facing the board, gap only the rubber feet) to the desk with the fan side in open air; peaked at 86°C and ran clean through tests 0-9, including test 6, before a power cut stopped it (xero was off the UPS for the test; memtest does not touch the disks, so no ZFS risk). Suggests heat, **not confirmed**: no full pass had completed on this stick (a memtester run in Ubuntu the same afternoon was also cut short, by the UPS dying, at 0 errors).
- 2026-10-08: **alerting added** (see "Temperature alerting").
- 2026-10-09: ~~Open: a fresh memtest86+ run~~ **cleared by memtester instead (user's choice):** 2 copies x 10G, 2 loops each, all 18 tests ok in every loop, 0 failures, 21:32 -> 00:46 on the pegboard, on the router's UPS. CPU 89-95°C on sysfs (HA peak 97°C), with a makeshift stopper for a gap and the AC turned down - so the stick is clean in the low-to-mid 90s, where the first memtest86+ error came at 103°C. memtester covers only free memory (20 of 32GB), so this is strong evidence, not a full clearance; a recurrence of segfaults or speech-to-phrase hangs would mean testing again.
