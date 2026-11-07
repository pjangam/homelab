# zfs

ZFS settings on xero, applied by hand with sudo (from a real terminal).

| Script | What it does |
|---|---|
| `arc_max.sh` | sets xero's ZFS ARC cap, live and across reboots, or prints the counters used to judge it. The cap was 1 GiB from the 8GB-stick days; see "Use xero's spare RAM" in `PROJECTS.md` for why it is 8 GiB now |
| `scrub_time.sh` | shows or moves the time of the monthly TRIM (first Sunday) and scrub (second Sunday) in Ubuntu's `/etc/cron.d/zfsutils-linux`; default 00:24, moved to 04:00 |

```bash
tools/zfs/arc_max.sh stats            # no sudo needed
sudo tools/zfs/arc_max.sh set 8       # GiB
tools/zfs/scrub_time.sh               # show the TRIM and scrub lines
sudo tools/zfs/scrub_time.sh set 04:00
```

Traps:
- **The scrub heats the SSD.** It reads the whole pool at ~300MB/s and took the Kingston to 85°C on 2026-11-08 (00:24-00:42). 04:00 keeps it off the hours someone is awake; it does not make it cooler. The fix is "Move xero's datapool SSD out of the case" in `PROJECTS.md`.
- **04:00 is the free slot on a scrub Sunday (8th-14th)**, checked 2026-11-08. Taken around it:

  | Time | Job |
  |---|---|
  | 02:00 | Vaultwarden backup |
  | 03:00 | HA backup; Immich integrity check (15% a night) |
  | ~03:10, Sundays | `e2scrub_all.timer` (boot drive) |
  | 03:30, 03:45 | hardware.md and documents backups |
  | 04:00, 1st of the month only | Glacier archive (`archive_to_glacier.sh`) |
  | 04:30 | Spotify song sync (seconds) |
  | 05:00 | cert renewal |

  The scrub takes ~18 min today and grows with the pool; past ~30 min it reaches the 04:30 sync. The TRIM (first Sunday) meets the Glacier archive only when the 1st is a Sunday; TRIM on an SSD is light.
- `/etc/cron.d/zfsutils-linux` is a dpkg conffile: an upgrade keeps the edit or asks. The original is saved to `/root/zfsutils-linux.cron.orig`, not next to it, because cron would run a second copy in `/etc/cron.d`.
