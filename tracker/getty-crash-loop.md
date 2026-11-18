# getty@tty1 crash-loop
**Status:** Done

**Why:** the console font setup baked a single hardcoded font choice into a static `getty@.service.d` drop-in from a one-time probe; a reboot that negotiated a different video mode broke it and crash-looped the console.
**Outcome:** fixed by making the drop-in try fonts largest-to-smallest at every getty start instead - now installed automatically by `new_machine_setup.sh`'s N5105 block. The standalone recovery script for this incident was removed once the preventive fix landed; recoverable from git history if it ever recurs.

#### Notes worth keeping
Initially, and wrongly, thought this was *why* the white-noise bug surfaced that day - it wasn't; see the correction in memory/git history.
