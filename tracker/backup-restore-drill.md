# Backup restore drill
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Together:** pull a recent backup down and restore it to a scratch location (needs the backup passphrase) to confirm it works

**Why:** Vaultwarden and HA config are backed up daily to Dropbox via rclone, but the restore path has never actually been tested - only that the upload step succeeds. "Untested backups aren't backups."
**State:** not started, explicitly for later. Never restore over production.
