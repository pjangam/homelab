#!/usr/bin/env bash
# Backs up vw-data, encrypts with GPG, uploads via rclone.
# Requires:
#   - BACKUP_PASSPHRASE env var (or set in .env.backup)
#   - rclone configured with a remote named "backup" (run: rclone config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
DATA_DIR="$SCRIPT_DIR/vw-data"
RCLONE_REMOTE="backup:vaultwarden"
KEEP_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/vaultwarden_$TIMESTAMP.tar.gz.gpg"

# Load passphrase from .env.backup if not already set
if [[ -z "${BACKUP_PASSPHRASE:-}" && -f "$SCRIPT_DIR/.env.backup" ]]; then
  source "$SCRIPT_DIR/.env.backup"
fi

if [[ -z "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "ERROR: BACKUP_PASSPHRASE is not set. Add it to .env.backup or export it."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Stopping vaultwarden..."
docker stop vaultwarden

echo "[$(date)] Creating encrypted backup..."
tar -czC "$SCRIPT_DIR" vw-data | \
  gpg --batch --yes --symmetric --cipher-algo AES256 \
      --passphrase "$BACKUP_PASSPHRASE" \
      --output "$BACKUP_FILE"

echo "[$(date)] Starting vaultwarden..."
docker start vaultwarden

echo "[$(date)] Uploading to $RCLONE_REMOTE..."
rclone copy "$BACKUP_FILE" "$RCLONE_REMOTE"

echo "[$(date)] Cleaning up local backups older than $KEEP_DAYS days..."
find "$BACKUP_DIR" -name "vaultwarden_*.tar.gz.gpg" -mtime +"$KEEP_DAYS" -delete

echo "[$(date)] Backup complete: $(basename "$BACKUP_FILE")"
