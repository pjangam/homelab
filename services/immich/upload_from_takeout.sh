#!/usr/bin/env bash
# Upload to Immich photos and videos that are in the Google Takeout zips but
# not in Immich, as found by verify_takeout.py. Run on xero:
#   IMMICH_API_KEY=<key> upload_from_takeout.sh rows.tsv [--dry-run]
# rows.tsv holds report rows from verify_takeout.py (sha1, size, same_name,
# zip, entry); pick the ones to upload, e.g. with awk, instead of passing the
# whole report. The API key must belong to the user whose library the photos
# go in (Account Settings -> API Keys), not admin's unless they are admin's.
#
# Each entry is extracted from its zip into a staging folder on datapool,
# kept only if its SHA-1 matches the report, then the folder goes up with
# immich-go from-folder (dates from EXIF, or from the file name). The June
# 2026 import used from-google-photos, which reads the JSON sidecars, but the
# files it left unfinished (90 "pending", mostly big GoPro videos) had no
# usable sidecar anyway. The staging folder is removed afterwards.
set -euo pipefail

rows=${1:?usage: IMMICH_API_KEY=<key> $0 rows.tsv [--dry-run]}
shift
: "${IMMICH_API_KEY:?set IMMICH_API_KEY}"
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
  unzip -p "$ZIPS/$zip" "$entry" > "$out"
  if [[ $(sha1sum < "$out" | cut -d' ' -f1) != "$sum" ]]; then
    echo "SHA-1 mismatch, skipped: $entry"; rm -f "$out"; continue
  fi
  n=$((n + 1))
done < <(tr '\t' '\037' < "$rows")
echo "$n files staged ($(du -sh "$stage" | cut -f1))"
[[ $n -gt 0 ]] || exit 0

~/bin/immich-go upload from-folder --no-ui --on-errors=continue \
  --server=http://localhost:2283 --api-key="$IMMICH_API_KEY" \
  --log-file="$HOME/immich-go-takeout-$(date +%F).log" "$@" "$stage"
