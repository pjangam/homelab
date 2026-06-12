#!/usr/bin/env bash
# Uploads Home Assistant backups to Dropbox via rclone.
# HA already encrypts its backups — no need to re-encrypt.
# Requires rclone configured with a remote named "backup" (run: rclone config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HA_BACKUP_DIR="$SCRIPT_DIR/HOMEASSISTANT_CONFIG/backups"
RCLONE_REMOTE="backup:homeassistant"
KEEP_DAYS=7

echo "[$(date)] Syncing HA backups to $RCLONE_REMOTE..."
rclone copy "$HA_BACKUP_DIR" "$RCLONE_REMOTE"

echo "[$(date)] Removing Dropbox copies older than $KEEP_DAYS days..."
rclone delete --min-age "${KEEP_DAYS}d" "$RCLONE_REMOTE"

echo "[$(date)] Done."
