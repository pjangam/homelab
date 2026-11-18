# Docker/Tailscale CVE patching + auto-update
**Status:** Done

**Why:** found real CVEs unpatched because `unattended-upgrades` only covers Ubuntu's own archive by default: Docker BuildKit command injection (fixed in 29.6.2) and a Tailscale SSH privilege-escalation bug, TS-2026-009 (fixed in 1.98.9).
**Outcome:** patched via a one-off dated script (since removed - the patch is applied, nothing left to re-run). The ongoing fix, extending the twice-daily `unattended-upgrades` run to also cover the Docker and Tailscale repos, is now installed automatically by `new_machine_setup.sh` instead of a separate cron job.
