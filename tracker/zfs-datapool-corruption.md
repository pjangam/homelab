# ZFS corruption on `datapool` fully resolved
**Status:** Done

**Why:** the 2026-07-12 scrub had found 6 corrupted blocks in `datapool`.
**Outcome:** all 6 originally-corrupted blocks dealt with. Corrupted files deleted, `zpool clear` + fresh scrub run - confirmed "0 errors", "No known data errors". The two recovered videos sit in a separate hardened dataset, `datapool/recovered-media`.

#### How each block was resolved
- 2 "library" originals were recovered earlier from intact Takeout zips.
- The remaining 4 were found via `zpool status -v`, surfaced on the new MQTT dashboard as "Homelab ZFS Pool" going red:
  - 2 were cached Immich thumbnail previews (no real data loss - deleted, Immich regenerates them automatically).
  - 2 were video originals under Immich's managed `upload/` path with no corresponding database row at all (confirmed via a temporary read-only query against a one-off `database` container started against the real `datapool/immich-db` volume) - meaning Immich had already forgotten these assets regardless of corruption.

#### Identifying the two videos
Identified which two Takeout videos they were by matching `photoTakenTime` timestamps from Takeout JSON sidecars against the corrupted files' own embedded metadata (still fully readable despite the corruption) - duration matched to the microsecond, confirming identity beyond doubt. File sizes differed substantially (Takeout originals ~1.4-3x larger) because Immich had transcoded them on upload, so the recovered copies are actually higher quality than what was lost. Moved to a new, separate, hardened dataset (`datapool/recovered-media`, `copies=2`/`sync=always`) rather than restored into the orphaned Immich path, since Immich can't reference them either way until manually re-uploaded once it's back online.
