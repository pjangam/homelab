# Use xero's spare RAM
**Status:** Active
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Claude:** after a few days of normal Immich use, run `tools/zfs/arc_max.sh stats` and compare with the Log baseline at a similar uptime; if ghost hits stop climbing and the metadata hit rate rises, set Done

**Why:** with the 32GB stick in, xero sits under about 25% memory use (2026-10-18: 7.6G used, 23G available, swap untouched), so the question is whether the idle RAM can buy anything. It mostly cannot: xero is CPU-bound (load 20 on 4 cores, 0% idle while Immich's jobs ran), not memory-bound.
**State:** ARC cap raised to 8 GiB on 2026-10-18 (live, `/etc/modprobe.d/zfs.conf` and initramfs all checked). The other options stay skipped or deferred.

#### Options
- **Raise the ZFS ARC cap to 8 GiB - worth doing.** `/etc/modprobe.d/zfs.conf` still has `zfs_arc_max=1073741824`, a leftover from the 8GB stick. The ARC is the only read cache in front of `datapool` (the Immich library, its DB, albums, phone uploads); the Linux page cache does not cover ZFS. On 2026-10-18 after 22h of uptime: ~96% hit rate, but 137k metadata misses and ~23k MRU/MFU ghost hits (reads a bigger ARC would have served). Expect quicker timeline scrolling and thumbnail loads, and fewer disk seeks during Bhakti's Takeout import - helpful, not dramatic. Stop at 8G to leave room for the import, the ML backlog and a margin, given the bad-RAM history.
  ```
  echo 8589934592 | sudo tee /sys/module/zfs/parameters/zfs_arc_max          # live
  sudo sed -i 's/zfs_arc_max=1073741824/zfs_arc_max=8589934592/' /etc/modprobe.d/zfs.conf
  sudo update-initramfs -u                                                    # survives reboot
  ```
  - ZFS 2.2 reports the ARC as "used", not cache, so memory graphs will climb to ~35-40% as it fills. That is cache, not pressure.
  - The Immich load guard (`services/immich/load_guard.sh`) trips on MemAvailable < 1.5GB, and MemAvailable leaves the ARC out; an 8G cap still leaves ~15G available.
  - Check it with `awk '/^(size|c_max|hits|misses|demand_metadata_misses|mru_ghost_hits|mfu_ghost_hits) /{print $1,$3}' /proc/spl/kstat/zfs/arcstats`.
- **Postgres memory tuning - skip.** The Immich DB is ~500M and already fits in memory.
- **A larger CLIP model for smart search - later.** It fits in RAM, but costs more CPU per asset, and ~12k assets have not yet been through ML. Reconsider once the backlog is done; switching models means re-running Smart Search on everything.
- **Local LLM / other AI on xero - no.** Ruled out already (N5105, no GPU, see "Local Qwen (Ollama) delegation experiment"); more RAM does not change that.
- **Longer Prometheus retention - not a RAM question.** It is bounded by disk (`retention.size=8GB`), not memory.

#### Log
- 2026-10-18: noted. Options reviewed; ARC cap increase recommended, the rest skipped or deferred.
- 2026-10-18: `tools/zfs/arc_max.sh` written (`stats`, and `sudo ... set <GiB>` for the live value, `/etc/modprobe.d/zfs.conf` and the initramfs). **Baseline at the 1 GiB cap**, 23h uptime: ARC 1.00 GiB full, hit rate 96.91%, metadata hit rate 98.30%, ghost hits 32,323. Compare after a few days at 8 GiB (counters reset on reboot, so compare like uptimes).
- 2026-10-18 14:33: user ran `sudo tools/zfs/arc_max.sh set 8`. Checked: live `zfs_arc_max` 8589934592, conf updated, initramfs rebuilt; ARC already 1.13 GiB, MemAvailable ~25GB.
