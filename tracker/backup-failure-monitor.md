# Monitor for silent backup failures
**Status:** Done

**Why:** `backup_vaultwarden.sh`/`backup_homeassistant.sh` run daily via cron and log to `backup.log`, but nothing checked whether they actually succeeded - an expired rclone token or full remote could fail them silently for weeks.
**Outcome:** extended `healthcheck.sh` to check the age of the last success line for each (>=30h flags a problem - daily cadence plus slack, not tied to time-of-day). Tested against the real log (correctly clean), a simulated stale log, and a missing-log case.
