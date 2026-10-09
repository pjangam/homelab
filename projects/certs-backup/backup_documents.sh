#!/usr/bin/env bash
# Backs up the `documents` SMB share (/datapool/documents, see
# services/samba/README.md) as one GPG-encrypted tar, uploaded via rclone.
# This replaces keeping the documents in Dropbox as plain files: Dropbox only
# ever sees one opaque blob, file names included.
#
# Dropbox is small (2.75 GiB on the free plan), so unlike the Vaultwarden
# backup this keeps only KEEP_COUNT archives and uploads only when something in
# the share changed (by path, size and mtime). The samba recycle bin
# (.deleted/) is left out.
# No local copy is kept: it would sit on the same disk as the share itself.
#
# Restore:
#   rclone cat backup:documents-encrypted/<newest> | gpg -d | tar -xC <dir>
#
# Requires:
#   - BACKUP_PASSPHRASE env var (or set in .env.backup)
#   - rclone configured with a remote named "backup" (run: rclone config)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
SOURCE_DIR="${DOCUMENTS_DIR:-/datapool/documents}"
RCLONE_REMOTE="${RCLONE_REMOTE:-backup:documents-encrypted}"
KEEP_COUNT=2
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAME="documents_$TIMESTAMP.tar.gpg"
LAST_HASH_FILE="$BACKUP_DIR/documents.last-sha256"

# Load passphrase from .env.backup if not already set
if [[ -z "${BACKUP_PASSPHRASE:-}" && -f "$SCRIPT_DIR/.env.backup" ]]; then
  source "$SCRIPT_DIR/.env.backup"
fi

if [[ -z "${BACKUP_PASSPHRASE:-}" ]]; then
  echo "ERROR: BACKUP_PASSPHRASE is not set. Add it to .env.backup or export it."
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "ERROR: $SOURCE_DIR not found."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

hash=$(cd "$SOURCE_DIR" && find . -path ./.deleted -prune -o -printf '%P\t%s\t%T@\n' | sort | sha256sum | cut -d' ' -f1)
if [[ -f "$LAST_HASH_FILE" && "$(cat "$LAST_HASH_FILE")" == "$hash" ]]; then
  echo "[$(date)] documents unchanged since the last upload, skipping."
  echo "[$(date)] Backup complete: unchanged"
  exit 0
fi

tmp="$BACKUP_DIR/.$NAME"
trap 'rm -f "$tmp"' EXIT

echo "[$(date)] Creating encrypted backup..."
# PDFs and scans are already compressed, so tar is not gzipped. The
# passphrase goes in on fd 3 rather than argv, so ps cannot show it.
tar -cC "$SOURCE_DIR" --exclude=./.deleted . | \
  gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
      --symmetric --cipher-algo AES256 --compress-algo none \
      --output "$tmp" 3<<<"$BACKUP_PASSPHRASE"

echo "[$(date)] Uploading $NAME ($(du -h "$tmp" | cut -f1)) to $RCLONE_REMOTE..."
rclone copyto "$tmp" "$RCLONE_REMOTE/$NAME"
remote_size=$(rclone lsf --format s "$RCLONE_REMOTE/$NAME")
if [[ "$remote_size" != "$(stat -c %s "$tmp")" ]]; then
  echo "ERROR: uploaded size $remote_size does not match the local archive; keeping old backups."
  exit 1
fi
# Recorded only after the upload succeeds, so a failed one is retried tomorrow.
echo "$hash" > "$LAST_HASH_FILE"

echo "[$(date)] Keeping $KEEP_COUNT most recent remote backups..."
rclone lsf "$RCLONE_REMOTE" --format "tp" | sort | head -n -"$KEEP_COUNT" | awk -F';' '{print $NF}' | \
  while IFS= read -r f; do
    echo "[$(date)] Removing old remote backup: $f"
    rclone deletefile "$RCLONE_REMOTE/$f"
  done

echo "[$(date)] Backup complete: $NAME"
