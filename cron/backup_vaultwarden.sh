#!/usr/bin/env bash
# Backs up vw-data, encrypts with GPG, uploads via rclone.
# Requires:
#   - BACKUP_PASSPHRASE env var (or set in .env.backup)
#   - rclone configured with a remote named "backup" (run: rclone config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
DATA_DIR="$SCRIPT_DIR/vw-data"
RCLONE_REMOTE="backup:vaultwarden"
KEEP_COUNT=7
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
# Guard the restart before stopping. Under `set -euo pipefail`, a failure in the
# tar/gpg steps below would otherwise exit with vaultwarden still stopped - and
# `docker stop` also sets Docker's HasBeenManuallyStopped flag, so
# `restart: unless-stopped` would leave it down through the next reboot as well,
# not just until someone noticed. That is exactly how caddy went missing on
# 2026-09-06 (see incidents/). The trap fires on every exit path, success or not;
# `docker start` on an already-running container is a harmless no-op, so it stays
# correct alongside the explicit start below.
trap 'docker start vaultwarden >/dev/null 2>&1 || true' EXIT
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

echo "[$(date)] Keeping $KEEP_COUNT most recent local backups..."
ls -1t "$BACKUP_DIR"/vaultwarden_*.tar.gz.gpg 2>/dev/null | tail -n +"$((KEEP_COUNT + 1))" | xargs -r rm -v

echo "[$(date)] Keeping $KEEP_COUNT most recent remote backups..."
rclone lsf "$RCLONE_REMOTE" --format "tp" | sort | head -n -"$KEEP_COUNT" | awk -F';' '{print $NF}' | \
  while IFS= read -r f; do
    echo "[$(date)] Removing old remote backup: $f"
    rclone deletefile "$RCLONE_REMOTE/$f"
  done

echo "[$(date)] Backup complete: $(basename "$BACKUP_FILE")"
