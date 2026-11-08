#!/usr/bin/env bash
# Repeatable disk cooling benchmark for xero's datapool SSD: read GB_TO_READ
# gigabytes off the pool as fast as it will go, sampling the drive's
# temperature, then print the peak and the curve. The disk counterpart of
# thermal_load_test.sh, and the measurement "Move xero's datapool SSD out of
# the case" is closed against.
#
# Why it exists: the Kingston SA400 is rated to 70°C and kept passing 80°C on
# long reads while it was screwed into the plastic bottom cover with no
# airflow (84-87°C on 2026-10-22, 85°C under the 2026-11-08 scrub). A 20GB
# sequential read reproduces that load in about a minute instead of waiting
# a month for the next scrub.
#
#   tools/host-stats/disk_thermal_test.sh              # 20GB, the standard run
#   GB_TO_READ=40 tools/host-stats/disk_thermal_test.sh
#
# Run it on xero. Reads are read-only and safe on live data, but they are
# real load: do not run it during a scrub or the nightly backups.
#
# ssd-temp-guard is left alone on purpose - if the drive reaches 70°C the
# guard clamps ZFS, which is exactly the behaviour worth observing. The
# summary says whether it engaged.
set -uo pipefail

GB_TO_READ=${GB_TO_READ:-20}
SAMPLE=${SAMPLE:-5}
ABORT_C=${ABORT_C:-88}        # below healthcheck's 85 urgent + headroom
READ_FROM=${READ_FROM:-/datapool/immich-upload}
DISK_MODEL=${DISK_MODEL:-KINGSTON}
PARAM_FILE=${PARAM_FILE:-/sys/module/zfs/parameters/zfs_vdev_max_active}
here=$(cd "$(dirname "$0")" && pwd)
RESULTS=${RESULTS:-$here/results}

for dev in /sys/block/sd*; do
  grep -qi "$DISK_MODEL" "$dev/device/model" 2>/dev/null || continue
  for t in "$dev"/device/hwmon/hwmon*/temp1_input; do [ -r "$t" ] && TEMP_FILE=$t; done
done
[ -n "${TEMP_FILE:-}" ] || { echo "no drivetemp sensor matching '$DISK_MODEL'" >&2; exit 1; }
[ -d "$READ_FROM" ] || { echo "$READ_FROM is not there" >&2; exit 1; }

temp_now() { echo $(( $(cat "$TEMP_FILE") / 1000 )); }
clamped_now() { [ "$(cat "$PARAM_FILE" 2>/dev/null || echo 1000)" -le 8 ] && echo yes || echo no; }

mkdir -p "$RESULTS"
stamp=$(date +%Y-%m-%d-%H%M)
out=$RESULTS/disk-thermal-$stamp.txt

start_c=$(temp_now)
echo "datapool disk thermal test - $(date '+%F %T %Z')" | tee "$out"
echo "reading ${GB_TO_READ}GB from $READ_FROM, sampling every ${SAMPLE}s, abort at ${ABORT_C}°C" | tee -a "$out"
echo "start: ${start_c}°C, zfs_vdev_max_active=$(cat "$PARAM_FILE" 2>/dev/null)" | tee -a "$out"
echo | tee -a "$out"

# Read real files sequentially into /dev/null, stopping once dd has eaten
# enough. tar walks the tree so we are not relying on one huge file existing.
tar -cf - "$READ_FROM" 2>/dev/null | dd of=/dev/null bs=1M count=$((GB_TO_READ * 1024)) 2>"$out.dd" &
dd_pid=$!

peak=$start_c; peak_at=0; guard_fired=no; elapsed=0; aborted=no
printf '%6s  %6s  %s\n' "t(s)" "temp" "guard" | tee -a "$out"
while kill -0 $dd_pid 2>/dev/null; do
  sleep "$SAMPLE"; elapsed=$((elapsed + SAMPLE))
  c=$(temp_now); g=$(clamped_now)
  [ "$g" = yes ] && guard_fired=yes
  [ "$c" -gt "$peak" ] && { peak=$c; peak_at=$elapsed; }
  printf '%6s  %5s°C  %s\n' "$elapsed" "$c" "$g" | tee -a "$out"
  if [ "$c" -ge "$ABORT_C" ]; then
    aborted=yes
    echo "ABORT: ${c}°C >= ${ABORT_C}°C, stopping the read" | tee -a "$out"
    kill $dd_pid 2>/dev/null; break
  fi
done
wait $dd_pid 2>/dev/null
# tar keeps going once dd has had its fill; it exits when the pipe closes.
pkill -P $$ tar 2>/dev/null

rate=$(grep -oE '[0-9.]+ [MG]B/s' "$out.dd" | tail -1)
echo | tee -a "$out"
echo "--- cool-down ---" | tee -a "$out"
for i in 1 2 3 4; do sleep "$SAMPLE"; printf '%6s  %5s°C\n' "+$((i * SAMPLE))" "$(temp_now)" | tee -a "$out"; done

{
  echo
  echo "read rate:   ${rate:-unknown}"
  echo "start:       ${start_c}°C"
  echo "PEAK:        ${peak}°C at ${peak_at}s"
  echo "guard fired: $guard_fired"
  echo "aborted:     $aborted"
  echo
  echo "Reference: 85°C under the 2026-11-08 scrub and 84-87°C on 2026-10-22,"
  echo "both with the SSD inside the plastic bottom cover. Rated 70°C."
} | tee -a "$out"
rm -f "$out.dd"
echo
echo "saved: $out"
