#!/usr/bin/env bash
# Upload local photo/video files to Immich, e.g. ones re-downloaded from
# Google Photos and dropped in phone-uploads. Run on xero:
#   upload_files.sh FILE...
# Skips a file Immich already has (same SHA-1) and an empty one (a Finder
# copy that failed leaves 0-byte files). IMMICH_API_KEY comes from the
# environment or else .env, and decides whose library the files land in.
# Immich takes the capture date from the file's EXIF or video metadata; the
# file's mtime is only its fallback. Same POST as upload_from_takeout.sh.
set -euo pipefail

[[ $# -gt 0 ]] || { echo "usage: $0 FILE..." >&2; exit 1; }
files=()
for f in "$@"; do files+=("$(realpath "$f")"); done
cd "$(dirname "$0")/../.."
: "${IMMICH_API_KEY:=$(sed -n 's/^IMMICH_API_KEY=//p' .env)}"
[[ -n $IMMICH_API_KEY ]] || { echo "IMMICH_API_KEY not set and not in .env" >&2; exit 1; }
U=$(grep ^DB_USERNAME .env | cut -d= -f2)
D=$(grep ^DB_DATABASE_NAME .env | cut -d= -f2)

rc=0
for f in "${files[@]}"; do
  name=$(basename "$f")
  [[ -s $f ]] || { echo "EMPTY, skipped: $name"; rc=1; continue; }
  sum=$(sha1sum < "$f" | cut -d' ' -f1)
  if [[ $(docker exec immich_postgres psql -U "$U" -d "$D" -tAc \
      "select count(*) from asset where encode(checksum, 'hex') = '$sum'") != 0 ]]; then
    echo "already in Immich: $name"; continue
  fi
  when=$(date -u -r "$f" +%Y-%m-%dT%H:%M:%S.000Z)
  resp=$(curl -sS --fail-with-body -X POST http://localhost:2283/api/assets \
    -H "x-api-key: $IMMICH_API_KEY" -H "x-immich-checksum: $sum" \
    -F "assetData=@$f" -F "filename=$name" \
    -F "fileCreatedAt=$when" -F "fileModifiedAt=$when") || { echo "FAILED $name: $resp"; rc=1; continue; }
  echo "$name: $resp"
done
exit $rc
