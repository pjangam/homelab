#!/usr/bin/env bash
# Download a Google Takeout export to xero, resumably, without wasting any of
# Google's 5 download attempts per part. Run on xero, inside tmux:
#   takeout_download.sh <cookies.txt> '<download-url-with-i=N>' <parts> <out-dir>
#
# Why: the 2026-06 export of the admin library was downloaded by browser, one
# click per part. Slow, broken downloads used up all 5 attempts on part 019,
# which was then lost for good (docs/google_takeout_missing.md).
#
# What it does differently, per part:
# - A part that is already in <out-dir> and passes `unzip -tq` is skipped,
#   so re-running only fetches what is missing or broken.
# - It asks Takeout for the part once (that is the "attempt") and keeps the
#   signed storage URL it redirects to. Every retry and resume after that goes
#   to the storage URL with a byte-range request, not back to Takeout.
# - It asks Takeout again only if the storage URL stops working (expired),
#   and at most MAX_ASKS times per part per run (default 2).
# - If Takeout answers with a page instead of a redirect, the cookies need
#   refreshing (Google's "verify it's you" lasts minutes). It stops there,
#   before any download starts.
# - When the bytes are in, it checks them with `unzip -tq` before renaming
#   the file to its final name.
# Every Takeout request is logged to <out-dir>/takeout-asks.log, so you can
# see how many of the 5 attempts each part has used.
#
# Inputs, from a browser signed in as the exporting account:
# - cookies.txt: Netscape-format cookies for takeout.google.com, from a
#   "cookies.txt" export extension, made right after re-entering the password
#   on the Takeout download page. Treat it like a password: keep it out of the
#   repo and delete it when done.
# - the URL: right-click "Download" on part 1 -> copy link. It has `&i=0`;
#   the script swaps in each part's index.
set -euo pipefail

cookies=$1 url=$2 parts=$3 out=$4
MAX_ASKS=${MAX_ASKS:-2}
mkdir -p "$out"
log="$out/takeout-asks.log"

ask_takeout() {  # part index -> prints the signed storage URL, or fails
  local i=$1 loc code
  read -r code loc < <(curl -s -o /dev/null -b "$cookies" \
    -w '%{http_code} %{redirect_url}\n' "${url/i=0/i=$i}")
  echo "$(date '+%F %T') part $i: HTTP $code -> ${loc%%\?*}" >> "$log"
  if [[ $code != 30[0-9] || -z $loc || $loc == *accounts.google.com* || $loc == *takeout.google.com* ]]; then
    echo "part $i: Takeout did not hand over the file (HTTP $code). Refresh cookies.txt and re-run." >&2
    return 1
  fi
  echo "$loc"
}

for ((i = 0; i < parts; i++)); do
  final=$(printf '%s/takeout-%03d.zip' "$out" $((i + 1)))
  if [[ -f $final ]] && unzip -tq "$final" >/dev/null 2>&1; then
    echo "part $((i + 1))/$parts: already here and tests OK"; continue
  fi
  tmp=$final.partial
  asks=0 done=
  while [[ -z $done ]]; do
    if ((asks >= MAX_ASKS)); then
      echo "part $((i + 1)): asked Takeout $asks times this run, stopping. See $log." >&2; exit 1
    fi
    signed=$(ask_takeout "$i") || exit 1
    asks=$((asks + 1))
    # Resume against the signed URL until curl succeeds or the URL dies.
    for try in $(seq 1 50); do
      if curl -fL -C - --retry 5 --retry-all-errors --retry-delay 10 \
           --speed-limit 20000 --speed-time 120 -o "$tmp" "$signed"; then
        done=1; break
      fi
      code=$(curl -s -o /dev/null -r 0-0 -w '%{http_code}' "$signed" || echo 000)
      [[ $code == 401 || $code == 403 || $code == 404 || $code == 410 ]] && break  # expired: ask again
      echo "part $((i + 1)): transfer broke (try $try), resuming in 30s" >&2; sleep 30
    done
  done
  if unzip -tq "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$final"
    echo "part $((i + 1))/$parts: $(du -h "$final" | cut -f1), tests OK"
  else
    mv "$tmp" "$tmp.bad"
    echo "part $((i + 1)): downloaded but fails unzip -t; kept as $tmp.bad. Re-run to fetch it again." >&2
    exit 1
  fi
done
echo "all $parts parts present and tested in $out"
