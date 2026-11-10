#!/usr/bin/env bash
# Runs `unzip -tq` on every Takeout zip in a folder, paced by the datapool SSD's
# temperature: bulk reads push the Kingston past its 70C rating, so it pauses
# above HOT (default 65C) until it cools to COOL (default 55C).
#   services/immich/test_takeout_zips.sh [dir]   # default /datapool/google-takeout/bhakti
# Prints "ok <zip>" or "BAD <zip>" per part and a summary; exits 1 if any is bad.
# Results also go to <dir>/zip-test.log, so a re-run skips parts already ok.
set -uo pipefail

DIR=${1:-/datapool/google-takeout/bhakti}
HOT=${HOT:-65}
COOL=${COOL:-55}
SSD_FILE=${SSD_FILE:-$(ls /sys/block/sda/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)}
LOG=$DIR/zip-test.log
touch "$LOG"

temp() { [ -n "$SSD_FILE" ] && echo $(( $(cat "$SSD_FILE") / 1000 )) || echo 0; }
cool_down() {
  local t; t=$(temp)
  [ "$t" -lt "$HOT" ] && return
  echo "$(date +%H:%M) ssd ${t}C, pausing until ${COOL}C"
  while [ "$(temp)" -gt "$COOL" ]; do sleep 30; done
}

bad=0 n=0
for z in "$DIR"/*.zip; do
  name=$(basename "$z")
  if grep -qx "ok $name" "$LOG"; then n=$((n + 1)); continue; fi
  cool_down
  if nice -n 19 ionice -c3 unzip -tq "$z" >/dev/null 2>&1; then
    echo "ok $name" | tee -a "$LOG"
  else
    echo "BAD $name" | tee -a "$LOG"; bad=$((bad + 1))
  fi
  n=$((n + 1))
done
echo "tested $n zips, $bad bad, ssd $(temp)C at $(date +%H:%M)"
[ "$bad" = 0 ]
