# ZFS `copies=2` on Immich datasets
**Status:** Done

**Why:** found real, previously-unnoticed data corruption in `datapool` (6 blocks, from a 2026-07-12 scrub that was never surfaced) while building the ZFS check in the healthcheck entry.
**Outcome:** set `copies=2` on `datapool/immich-upload` and `datapool/immich-db` - free, uses existing hardware, gives real self-healing for isolated corruption (exactly what was found) going forward. Does not fix the already-corrupted blocks (still recoverable from the intact Takeout zips whenever needed) or protect against full-disk failure (needs the real mirror project).
