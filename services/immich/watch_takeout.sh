#!/usr/bin/env bash
# Watches browser Takeout downloads on xero and exits at the first event, so
# whoever runs it (a Claude session, in the background) can notify and re-run.
#   services/immich/watch_takeout.sh [dir]
# Prints one or more lines, then exits 0:
#   FINISHED <part>   a .crdownload became a .zip
#   GONE <part>       a .crdownload vanished with no .zip (cancelled or failed)
#   STALLED <part>    no growth for STALL_MIN minutes (default 15)
#   BROWSER_DOWN      the takeout-browser container is not running
#   ALL_DONE          nothing left downloading
# Files whose mtime is older than STALE_H hours (default 6) at start are old
# leftovers (e.g. a replaced -2-003 attempt) and are ignored.
set -uo pipefail

DIR=${1:-/datapool/google-takeout/bhakti}
STALL_MIN=${STALL_MIN:-15}
STALE_H=${STALE_H:-6}
EVERY=${EVERY:-60}
cd "$DIR" || exit 1

part() { basename "$1" .zip.crdownload; }
active() { find . -maxdepth 1 -name '*.crdownload' -mmin -$((STALE_H * 60)) -printf '%f\n' | sort; }

declare -A size still
watch=$(active)
[ -n "$watch" ] || { echo ALL_DONE; exit 0; }

while :; do
  events=()
  docker ps --filter name=takeout-browser --filter status=running -q | grep -q . || events+=(BROWSER_DOWN)
  left=0
  for f in $watch; do
    z=${f%.crdownload}
    if [ ! -e "$f" ]; then
      if [ -e "$z" ]; then events+=("FINISHED $(part "$f") $(du -h "$z" | cut -f1)")
      else events+=("GONE $(part "$f")"); fi
      continue
    fi
    left=$((left + 1))
    s=$(stat -c %s "$f")
    if [ "$s" = "${size[$f]:-}" ]; then still[$f]=$(( ${still[$f]:-0} + 1 )); else still[$f]=0; fi
    size[$f]=$s
    if [ $(( still[$f] * EVERY )) -ge $(( STALL_MIN * 60 )) ]; then
      events+=("STALLED $(part "$f") at $(du -h "$f" | cut -f1)")
    fi
  done
  if [ ${#events[@]} -gt 0 ]; then
    printf '%s\n' "${events[@]}"
    [ "$left" = 0 ] && echo ALL_DONE
    echo "still downloading: $left, zips: $(ls -1 ./*.zip 2>/dev/null | wc -l), at $(date +%H:%M)"
    exit 0
  fi
  sleep "$EVERY"
done
