#!/usr/bin/env bash
# Backs up HOMEASSISTANT_CONFIG, encrypts with GPG, uploads via rclone.
# Requires:
#   - BACKUP_PASSPHRASE env var (or set in .env.backup)
#   - rclone configured with a remote named "backup" (run: rclone config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
DATA_DIR="$SCRIPT_DIR/HOMEASSISTANT_CONFIG"
RCLONE_REMOTE="backup:homeassistant"
KEEP_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/homeassistant_$TIMESTAMP.tar.gz.gpg"

if [[ -z "${BACKUP_PASSPHRASE:-}" && -f "$SCRIPT_DIR/.env.backup" ]]; then
  source "$SCRIPT_DIR/.env.backup"
fi

if [[ -z "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "ERROR: BACKUP_PASSPHRASE is not set. Add it to .env.backup or export it."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Stopping homeassistant..."
docker stop homeassistant

echo "[$(date)] Creating encrypted backup..."
tar -czC "$SCRIPT_DIR" HOMEASSISTANT_CONFIG | \
  gpg --batch --yes --symmetric --cipher-algo AES256 \
      --passphrase "$BACKUP_PASSPHRASE" \
      --output "$BACKUP_FILE"

echo "[$(date)] Starting homeassistant..."
docker start homeassistant

echo "[$(date)] Uploading to $RCLONE_REMOTE..."
rclone copy "$BACKUP_FILE" "$RCLONE_REMOTE"

echo "[$(date)] Cleaning up local backups older than $KEEP_DAYS days..."
find "$BACKUP_DIR" -name "homeassistant_*.tar.gz.gpg" -mtime +"$KEEP_DAYS" -delete

echo "[$(date)] Backup complete: $(basename "$BACKUP_FILE")"
