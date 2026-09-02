# 2026-07-23: getty@tty1 crash-loop

**Symptom:** `getty@tty1.service` crash-looped after a reboot and gave up entirely (`Start request repeated too quickly`) - no local console login possible on tty1. Host had rebooted twice that day (13:54 and 14:01 IST).

**Root cause:** the 2026-06-29 TTY font setup (see [`TTY console font (powerline)`](../Readme.md#tty-console-font-powerline) in the Readme) didn't install a live fallback - it probed fonts once, then baked whichever font happened to fit *that day's* video mode (`v24b`) directly into a static `getty@.service.d/powerline-font.conf` drop-in. The console's negotiated video mode isn't stable across boots (depends on whether a monitor is physically attached at boot time, among other things). After the second reboot on 2026-07-23, `v24b` no longer fit the negotiated mode, `setfont` failed with exit 71, and `getty@tty1.service` hit systemd's restart-rate-limit.

**Fix:** rewrote the generated drop-in to try fonts largest-to-smallest at *every* getty start (not a single hardcoded choice), with a trailing `; true` so getty can never crash-loop on a font again. This is now installed automatically by `new_machine_setup.sh`'s N5105-specific block, rather than living as a separate one-time script. (A standalone recovery script, `fix_getty_crashloop.sh`, existed at the time to rewrite the drop-in and reset/restart a currently-stuck unit; it was removed once the preventive fix landed - recoverable from git history if this class of bug ever recurs.)

**Correction - this did NOT cause the same-day white-noise linger bug:** initially theorized that a tty1 autologin session had been masking the white-noise `systemd --user` linger bug (see [`2026-08-31-white-noise-mqtt-reconnect-loop.md`](2026-08-31-white-noise-mqtt-reconnect-loop.md) for the unrelated MQTT bug, and `Readme.md`'s White Noise section for the linger requirement itself), and that this crash-loop is what exposed it. That's wrong, verified two ways:
1. `last -F -x | grep tty1` returned zero results, ever - tty1 has never had a logged-in session recorded; no autologin was configured on this getty at all.
2. journald showed `user@1000.service` starting/stopping in lockstep with every SSH login/logout on both 2026-07-22 and 2026-07-23 - this churn is normal, ongoing behavior with `Linger=no`, not something new that day.

The white-noise linger bug had almost certainly been present and exploitable every day since the service was created (~2026-07-13/14); 2026-07-23 is most likely just the day a toggle attempt happened to land inside one of these routine session gaps, not a day something newly broke.

**Lesson:** don't chain two coincidentally-same-day bugs into one causal story without checking log evidence for the actual mechanism. `journalctl -u user@1000.service` / `journalctl | grep "user@1000"` and `last -F -x` are the ground truth for session-accounting questions, not inference from a plausible-sounding narrative.

**Prevention / how to apply:** if any `systemd --user` service on this box mysteriously stops working, check `loginctl show-user pramod -p Linger` (should be `yes`) - that alone fully explains the failure mode, no need to involve tty1/getty. If tty1 ever shows a dead/failed getty in `who -a` or `systemctl status getty@tty1`, that's a separate, cosmetic-only (local console access) issue.
