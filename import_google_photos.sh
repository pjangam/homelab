#!/usr/bin/env bash
set -euo pipefail

# Import Google Photos into Immich from Google Takeout zip files.
#
# Steps:
#   1. Go to takeout.google.com → deselect all → select Google Photos → export as .zip
#   2. Download the zip files to TAKEOUT_DIR (default: /datapool/immich-upload/google-takeout)
#   3. Generate an Immich API key: Account Settings → API Keys → New API Key
#   4. Run this script
#
# Usage:
#   export IMMICH_API_KEY=your-key
#   ./import_google_photos.sh              # dry run (default)
#   ./import_google_photos.sh --for-real   # actual import

TAKEOUT_DIR="/datapool/immich-upload/google-takeout"
IMMICH_SERVER="http://192.168.1.123:2283"
IMMICH_GO="$HOME/bin/immich-go"
DRY_RUN="--dry-run"

if [[ "${1:-}" == "--for-real" ]]; then
    DRY_RUN=""
    echo "=== LIVE RUN ==="
else
    echo "=== DRY RUN (pass --for-real to import) ==="
fi

command -v "$IMMICH_GO" &>/dev/null || { echo "ERROR: immich-go not found at $IMMICH_GO"; exit 1; }

if [[ -z "${IMMICH_API_KEY:-}" ]]; then
    echo "ERROR: IMMICH_API_KEY not set."
    echo "Generate one in Immich: Account Settings → API Keys → New API Key"
    echo "Then: export IMMICH_API_KEY=your-key"
    exit 1
fi

mkdir -p "$TAKEOUT_DIR"

ZIP_COUNT=$(find "$TAKEOUT_DIR" -maxdepth 1 -name '*.zip' | wc -l)
if [[ "$ZIP_COUNT" -eq 0 ]]; then
    echo "ERROR: No .zip files found in $TAKEOUT_DIR"
    echo "Download your Google Takeout zip files there first."
    exit 1
fi

echo "Found $ZIP_COUNT takeout zip file(s) in $TAKEOUT_DIR"
echo ""

echo "=== Uploading to Immich ==="
"$IMMICH_GO" upload from-google-photos \
    --server "$IMMICH_SERVER" \
    --api-key "$IMMICH_API_KEY" \
    --manage-raw-jpeg StackCoverJPG \
    --manage-heic-jpeg StackCoverHeic \
    --on-errors continue \
    -l "$TAKEOUT_DIR/immich-go.log" \
    $DRY_RUN \
    "$TAKEOUT_DIR"/takeout-*.zip

echo ""
echo "=== Done ==="
echo "Log: $TAKEOUT_DIR/immich-go.log"
