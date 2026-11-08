# ssd-temp-guard

Throttles ZFS while the `datapool` SSD is over its temperature rating, and
lets go once it cools. Runs on **xero** as the system unit
`ssd-temp-guard.service`.

## Why

- The Kingston SA400 (`sda`, `datapool`) is **rated to 70°C** and goes well
  past it on any sustained bulk read or write:
  - **2026-11-08, 85°C** - Ubuntu's monthly ZFS scrub (`/etc/cron.d/zfsutils-linux`,
    second Sunday 00:24) read all 305G in 17m53s, ~284 MB/s flat out.
  - **2026-10-22, 84-87°C for 20-50 min** - SHA-1 over 43G of zips plus
    ffmpeg over 82 videos.
- `healthcheck.sh` **alerts** on this (warn 75°C, urgent 85°C) but nothing
  **acts** on it. `immich-load-guard` is the nearest thing and watches CPU
  temperature, memory and CPU% only - never disk temperature, and it can
  only stop Immich.
- The drive is screwed label-down into the **plastic bottom cover with no
  airflow** (`docs/images/xero/ram-8gb-and-data-ssd.jpg`), which is why it
  idles ~10°C above the boot SSD lying beside the fan.

## What it does

| | |
|---|---|
| Sensor | `drivetemp` `temp1_input` for the disk whose model matches `KINGSTON` (found by model, so `sda`/`sdb` swapping at boot does not matter) |
| Clamp | `>= 70°C` held for 2 samples (30s) -> `zfs_vdev_max_active` = **4** |
| Release | `< 62°C` -> restored to **1000** (the stock default) |
| Interval | 15s |
| Alerts | ntfy `homelab-health` on clamp (priority 4) and release (priority 2) |

The gap between 70 and 62 is **hysteresis** - a drive sitting right on the
limit would otherwise flap between fast and slow every sample.

## Why it throttles the whole vdev, not the job

On this box the usual per-process levers do nothing to ZFS:

| Lever | Works? | Why |
|---|---|---|
| `ionice` | **No** | Needs CFQ/BFQ; ZFS bypasses the block scheduler for its vdevs (`sda` is on `mq-deadline`, unused by ZFS) |
| systemd `IOReadBandwidthMax` (cgroup v2 `io`) | **No** | The controller is loaded, but ZFS issues the real block I/O from its own kernel taskqueues, not the calling process's cgroup |
| `zfs_vdev_max_active` | **Yes** | ZFS's own I/O scheduler - the only layer that sees every source |

So it is deliberately blunt: while clamped, **everything on `datapool` is
slower** - scrub, Immich, Postgres, the nightly backups, the S3 archive run,
and anything you type at a prompt. That is the trade for catching sources
nobody tagged in advance. It only engages while the drive is actually hot.

## Files

| File | What |
|---|---|
| `ssd_temp_guard.sh` | the daemon; thresholds overridable from the environment |
| `ssd-temp-guard.service` | the system unit (`/etc/systemd/system/`) |
| `test_ssd_temp_guard.sh` | plays temperature sequences against a fake sensor and a fake tunable - no root, no ZFS, no hot disk needed. **Run it on xero**: it needs GNU `timeout`, which macOS lacks |

## Install / re-run after a change

A **system** unit, not `systemd --user` like `immich-load-guard`: writing
`/sys/module/zfs/parameters` needs root. The unit hardcodes the repo path
`/home/pramod/code/homelab/projects/ssd-temp-guard/`, so moving the folder
means editing it and re-running the install.

```sh
# on xero, after a git pull
sudo cp projects/ssd-temp-guard/ssd-temp-guard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ssd-temp-guard
systemctl status ssd-temp-guard
journalctl -u ssd-temp-guard -f
```

Editing `ssd_temp_guard.sh` alone needs only `sudo systemctl restart ssd-temp-guard`.

## Traps

- **Stopping the unit must not leave the pool throttled.** The script traps
  `TERM`/`INT`/`EXIT` and restores `zfs_vdev_max_active` on the way out;
  the unit gives it `TimeoutStopSec=30` to do so. If you ever kill it with
  `-9`, put the value back by hand:
  `echo 1000 | sudo tee /sys/module/zfs/parameters/zfs_vdev_max_active`.
- **Restarting mid-hot-spell** would otherwise record the clamp value as
  "normal" and never restore properly. The script falls back to 1000 when
  the value it reads at startup is already at or below the clamp.
- **The tunable is not persistent** - it resets to 1000 on reboot, which is
  the safe direction. Nothing is needed in `/etc/modprobe.d/zfs.conf` (that
  file holds the ARC cap only).
- **It only covers ZFS**, so the Biwin boot drive is outside it. That drive
  peaked at 54°C during the same scrub, so it does not need protecting.
- **It is not the fix.** Airflow is - the drive sits in a sealed plastic
  pocket. This stops the peaks; it does not make the bay cooler. See the
  `PROJECTS.md` entry for the airflow options.
- **`CLAMP=4` is a starting value, not a measured one.** What throughput it
  actually yields on this drive has to be checked against a real scrub.

## Related

- `projects/healthcheck/README.md` - the 75/85°C alerts this acts on
- `services/immich/README.md` - `immich-load-guard`, the same pattern for CPU/memory
- `PROJECTS.md` "datapool SSD runs hot" - the story, the airflow options and the measurements
