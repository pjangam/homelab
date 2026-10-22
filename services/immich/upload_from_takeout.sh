#!/usr/bin/env bash
# Upload to Immich photos and videos that are in the Google Takeout zips but
# not in Immich, as found by verify_takeout.py. Run on xero:
#   upload_from_takeout.sh rows.tsv [--dry-run]
# rows.tsv holds report rows from verify_takeout.py (sha1, size, same_name,
# zip, entry); pick the ones to upload, e.g. with awk, instead of passing the
# whole report. The API key is IMMICH_API_KEY, from the environment or else
# from .env; it must belong to the user whose library the photos go in
# (Account Settings -> API Keys). --dry-run stages and checks, uploads nothing.
#
# Each entry is extracted from its zip into a staging folder on datapool,
# kept only if its SHA-1 matches the report, then POSTed to /api/assets with
# curl, one file at a time. Not immich-go: 0.32 (the latest, 2026-06) cannot
# read Immich 3.3's asset list ("cannot unmarshal number into ... duration",
# simulot/immich-go#1442). Immich takes the capture date from the file's own
# EXIF or video metadata; fileCreatedAt (the zip entry's time) is only its
# fallback. The staging folder is removed afterwards.
set -euo pipefail

rows=$(realpath "${1:?usage: $0 rows.tsv [--dry-run]}")
dry=${2:-}
cd "$(dirname "$0")/../.."
: "${IMMICH_API_KEY:=$(sed -n 's/^IMMICH_API_KEY=//p' .env)}"
[[ -n $IMMICH_API_KEY ]] || { echo "IMMICH_API_KEY not set and not in .env" >&2; exit 1; }
SERVER=http://localhost:2283
ZIPS=/datapool/google-takeout
stage=$ZIPS/staging-upload
mkdir -p "$stage"
trap 'rm -rf "$stage"' EXIT

n=0
# Tabs become \037 first: read collapses runs of a whitespace IFS such as
# tab, which would drop the empty same_name column and shift the rest.
while IFS=$'\037' read -r sum _ _ zip entry; do
  [[ $sum == sha1 || $sum == bad-crc ]] && continue
  out="$stage/$(basename "$entry")"
  [[ -e $out ]] && { echo "duplicate name in list, skipped: $entry"; continue; }
  unzip -q -j "$ZIPS/$zip" "$entry" -d "$stage"   # -j keeps the entry's time
  if [[ $(sha1sum < "$out" | cut -d' ' -f1) != "$sum" ]]; then
    echo "SHA-1 mismatch, skipped: $entry"; rm -f "$out"; continue
  fi
  n=$((n + 1))
done < <(tr '\t' '\037' < "$rows")
echo "$n files staged ($(du -sh "$stage" | cut -f1))"
[[ $n -gt 0 && $dry != --dry-run ]] || exit 0

rc=0
for f in "$stage"/*; do
  when=$(date -u -r "$f" +%Y-%m-%dT%H:%M:%S.000Z)
  resp=$(curl -sS --fail-with-body -X POST "$SERVER/api/assets" \
    -H "x-api-key: $IMMICH_API_KEY" -H "x-immich-checksum: $(sha1sum < "$f" | cut -d' ' -f1)" \
    -F "assetData=@$f" -F "filename=$(basename "$f")" \
    -F "fileCreatedAt=$when" -F "fileModifiedAt=$when") || { echo "FAILED $(basename "$f"): $resp"; rc=1; continue; }
  echo "$(basename "$f"): $resp"
done
exit $rc
