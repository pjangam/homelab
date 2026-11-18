# Offsite copy of docs/hardware.md (Dropbox, encrypted)
**Status:** Done

**Why:** `docs/hardware.md` is gitignored, so the master on xero was its only copy; the Mac once had an scp'd copy, but it is gone and nothing kept it in step anyway.
**Outcome:** shipped 2026-09-30 - `projects/certs-backup/backup_hardware_md.sh` uploads a GPG-encrypted copy to Dropbox daily. Verified: first run uploaded, second skipped, and the Dropbox copy decrypts byte-identical to xero's file.
- Left open: `healthcheck.sh` checks backup freshness only for Vaultwarden and HA, not this one.

#### Design
`projects/certs-backup/backup_hardware_md.sh`, the Vaultwarden backup's shape reused: GPG with `BACKUP_PASSPHRASE` from `.env.backup`, `rclone copy` to `backup:homelab-hardware`, keep 7, and skip when the file's sha256 matches the last successful upload. Cron 03:30 daily on xero (also in `new_machine_setup.sh`), logging to `backup.log`.

#### Restore
`rclone cat backup:homelab-hardware/<newest> | gpg -d > docs/hardware.md`

#### Log
- 2026-09-30: decided to back it up to Dropbox only, and leave the Mac without a copy - no Dropbox or rclone on the work laptop. Shipped and verified the same day.
