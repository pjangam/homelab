#!/usr/bin/env bash
# Print the Google Photos link and capture time of a file in the Takeout
# zips, from its sidecar JSON, so a copy that is damaged in the zip can be
# downloaded again by hand. Run on xero:
#   takeout_photo_url.sh IMG_4352.MOV [more names...]
# A script cannot fetch the file itself: since 2025-03-31 the Google Photos
# Library API only reads media the calling app uploaded.
set -euo pipefail

ZIPS=/datapool/google-takeout
for name in "$@"; do
  found=
  for z in "$ZIPS"/*.zip; do
    while IFS= read -r e; do
      found=1
      unzip -p "$z" "$e" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
print(d["title"], "|", d["photoTakenTime"]["formatted"], "|", d["url"])'
    done < <(unzip -Z1 "$z" | grep -F "/$name." | grep '\.json$' || true)
  done
  [[ -n $found ]] || echo "$name: no sidecar in the zips"
done
