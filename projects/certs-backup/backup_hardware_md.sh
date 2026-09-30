#!/usr/bin/env bash
# Backs up docs/hardware.md, encrypts with GPG, uploads via rclone.
# The file is gitignored (it gathers LAN addresses and service locations into
# one lookup), so xero's copy is the only one - this is its offsite copy.
# Encrypted like the Vaultwarden backup, for the same reason it is gitignored.
# Skips the upload when the file is unchanged since the last one.
# Requires:
#   - BACKUP_PASSPHRASE env var (or set in .env.backup)
#   - rclone configured with a remote named "backup" (run: rclone config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
SOURCE_FILE="$SCRIPT_DIR/docs/hardware.md"
RCLONE_REMOTE="backup:homelab-hardware"
KEEP_COUNT=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/hardware_$TIMESTAMP.md.gpg"
LAST_HASH_FILE="$BACKUP_DIR/hardware_md.last-sha256"

# Load passphrase from .env.backup if not already set
if [[ -z "${BACKUP_PASSPHRASE:-}" && -f "$SCRIPT_DIR/.env.backup" ]]; then
  source "$SCRIPT_DIR/.env.backup"
fi

if [[ -z "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "ERROR: BACKUP_PASSPHRASE is not set. Add it to .env.backup or export it."
  exit 1
fi

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "ERROR: $SOURCE_FILE not found."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

hash=$(sha256sum "$SOURCE_FILE" | cut -d' ' -f1)
if [[ -f "$LAST_HASH_FILE" && "$(cat "$LAST_HASH_FILE")" == "$hash" ]]; then
  echo "[$(date)] hardware.md unchanged since the last upload, skipping."
  echo "[$(date)] Backup complete: unchanged"
  exit 0
fi

echo "[$(date)] Creating encrypted backup..."
gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase "$BACKUP_PASSPHRASE" \
    --output "$BACKUP_FILE" "$SOURCE_FILE"

echo "[$(date)] Uploading to $RCLONE_REMOTE..."
rclone copy "$BACKUP_FILE" "$RCLONE_REMOTE"
# Recorded only after the upload succeeds, so a failed one is retried tomorrow.
echo "$hash" > "$LAST_HASH_FILE"

echo "[$(date)] Keeping $KEEP_COUNT most recent local backups..."
ls -1t "$BACKUP_DIR"/hardware_*.md.gpg 2>/dev/null | tail -n +"$((KEEP_COUNT + 1))" | xargs -r rm -v

echo "[$(date)] Keeping $KEEP_COUNT most recent remote backups..."
rclone lsf "$RCLONE_REMOTE" --format "tp" | sort | head -n -"$KEEP_COUNT" | awk -F';' '{print $NF}' | \
  while IFS= read -r f; do
    echo "[$(date)] Removing old remote backup: $f"
    rclone deletefile "$RCLONE_REMOTE/$f"
  done

echo "[$(date)] Backup complete: $(basename "$BACKUP_FILE")"
