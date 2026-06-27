#!/usr/bin/env bash
# Uploads Home Assistant backups to Dropbox via rclone.
# HA already encrypts its backups — no need to re-encrypt.
# Requires rclone configured with a remote named "backup" (run: rclone config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HA_BACKUP_DIR="$SCRIPT_DIR/HOMEASSISTANT_CONFIG/backups"
RCLONE_REMOTE="backup:homeassistant"
KEEP_COUNT=7

echo "[$(date)] Syncing HA backups to $RCLONE_REMOTE..."
rclone copy "$HA_BACKUP_DIR" "$RCLONE_REMOTE"

echo "[$(date)] Keeping $KEEP_COUNT most recent remote backups..."
rclone lsf "$RCLONE_REMOTE" --format "tp" | sort | head -n -"$KEEP_COUNT" | awk -F';' '{print $NF}' | \
  while IFS= read -r f; do
    echo "[$(date)] Removing old remote backup: $f"
    rclone deletefile "$RCLONE_REMOTE/$f"
  done

echo "[$(date)] Keeping $KEEP_COUNT most recent local HA backups..."
ls -1t "$HA_BACKUP_DIR"/*.tar 2>/dev/null | tail -n +"$((KEEP_COUNT + 1))" | xargs -r rm -v

echo "[$(date)] Done."
