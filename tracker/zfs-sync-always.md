# ZFS `sync=always` on Immich datasets
**Status:** Done

**Why:** surfaced while brainstorming graceful-shutdown options for the power watchdog: a different strategic angle from detection entirely - instead of getting better at *detecting* power loss, reduce the *impact* when it happens anyway.
**Outcome:** set `sync=always` on `datapool/immich-upload` and `datapool/immich-db` (same scope as `copies=2`), forcing every write to commit synchronously instead of buffering, shrinking the window of in-flight data that could be corrupted by an abrupt loss.

#### Limits
- Explicitly complementary, not a replacement: still need real power-loss detection (the ESP32/power-watchdog projects), and sudden power loss can still damage hardware itself regardless of filesystem-level mitigation.
- Only applies to `datapool` - the OS root disk isn't ZFS, so this doesn't cover it.
