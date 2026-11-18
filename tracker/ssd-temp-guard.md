# datapool SSD temperature guard
**Status:** Done
**Priority:** P2

#### Open items
- Nothing open. Airflow for summer is on "xero cooling on the Skadis pegboard".

**Why:** the Kingston SA400 (`sda`, `datapool`) is rated to 70°C and goes past it on any sustained bulk read or write - **85°C on 2026-11-08** (the monthly ZFS scrub), 84-87°C for 20-50 min on 2026-10-22 (SHA-1 over 43G plus ffmpeg). `healthcheck.sh` alerts at 75/85°C but nothing acts, and `immich-load-guard` watches CPU temperature only and can only stop Immich. This is the "Software limit" option from "xero cooling on the Skadis pegboard", built more generally: it throttles **every** source, not just Immich.
**State:** **live on xero since 2026-11-08 11:30** - enabled, active, watching `/sys/block/sda/device/hwmon/hwmon1/temp1_input`, idling at 45°C with the tunable at 1000. All six test cases pass on xero. `CLAMP=4` is still a starting value, not a measured one.
**Superseded as the fix, kept as the safety net (2026-11-08):** the SSD moved into open air the same day and now peaks at 60°C under the load that used to make 85°C, so the guard has nothing to do in normal operation. **Wrong for scrubs (2026-11-11):** a full scrub still reached 70°C and the guard held it there for 20 min. It stays because it covers what the move does not: a hotter room, a fuller pool, the drive going back in a case, or any future bulk job on a drive that is still rated 70°C and still has no mirror.
**Next scrub: Wed 2026-11-11 04:00** (moved there by `tools/zfs/scrub_time.sh`, see "Move xero's datapool SSD out of the case"). Installing the guard before then turns that scrub into the measurement for free. The two fix different halves: moving the SSD into open air is the cure, this guard is the limiter for every bulk job that is not a scrub.

#### Why it throttles the vdev, not the job
On this box the usual per-process levers do nothing to ZFS, checked on xero 2026-11-08:

| Lever | Works? | Why |
|---|---|---|
| `ionice` | No | Needs CFQ/BFQ; ZFS bypasses the block scheduler for its vdevs |
| systemd `IOReadBandwidthMax` (cgroup v2 `io`) | No | ZFS issues the real block I/O from its own kernel taskqueues, not the calling process's cgroup |
| `zfs_vdev_max_active` | **Yes** | ZFS's own I/O scheduler - the only layer that sees every source |

So it clamps `zfs_vdev_max_active` 1000 -> 4 at >=70°C and restores at <62°C. Blunt on purpose: while clamped everything on `datapool` is slower, which is the price of catching jobs nobody tagged in advance.

#### Log
- 2026-11-08: the monthly scrub (`/etc/cron.d/zfsutils-linux`, second Sunday 00:24) read all 305G in 17m53s, ~284 MB/s flat out, and took the Kingston to **85°C** at 00:45 - healthcheck's URGENT threshold. Guard written, unit-tested, not installed.
- 2026-11-08 11:30: installed and enabled by the user (needed a real terminal for sudo). Recorded in `docs/hardware.md` under a new "systemd system units" line. Waiting on the Wed 2026-11-11 04:00 scrub for the first real measurement.
- 2026-11-17 (read late; due after 2026-11-11): **First real scrub after the move (Wed 2026-11-11 04:00, 305G):** 34°C -> 69°C in ~7 min, guard clamped at 04:08:29 (`zfs_vdev_max_active` 1000 -> 4), then held **69-72°C for 20 min** until the scrub ended at 04:28 and the guard released. Scrub took 28m08s (17m53s unclamped on 2026-11-08), 0 errors. Open air alone is not enough for a full scrub: the 60°C test was a 20GB / ~75s read, too short to heat-soak. `CLAMP=4` stops the climb but does not cool the drive below 70°C.
- 2026-11-17: SMART read (user): **lifetime max 90°C** - so the drive went past the 85°C we saw at least once, before the move. Otherwise healthy: 0 reallocated, 0 uncorrectable, 0 program/erase fails, 99% life left, 1279 GiB host writes. 125 unsafe shutdowns (power cuts). Full numbers in `docs/hardware.md`.
- 2026-11-17: **Done** (user). The guard holds a full scrub at 69-72°C, which is acceptable; it stays running as the limiter. A fan for summer is wanted but **not a dumb always-on one** (user): moved to "xero cooling on the Skadis pegboard".
