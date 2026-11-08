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
# Two traps this script exists to avoid, both found the hard way on
# 2026-11-08 when the first version reported a meaningless 51°C peak:
#   - `dd` counts BLOCKS, not bytes, and a pipe returns short reads, so
#     `count=N bs=1M` stops long before N megabytes. Reads go straight from
#     a file with `iflag=fullblock`, and the total is summed from file sizes.
#   - `tar` over a photo library walks hundreds of thousands of small files
#     and managed 19 MB/s. Reading whole large files instead gives 500+ MB/s,
#     which is the load that actually heats the drive.
#
# ARC: xero's cap is 8 GiB, so a 20GB run is mostly uncached, but the first
# GB or so may come from RAM. The peak is what matters, and it lands late.
#
# ssd-temp-guard is left alone on purpose - if the drive reaches 70°C the
# guard clamps ZFS, which is exactly the behaviour worth observing. The
# summary says whether it engaged.
set -uo pipefail

GB_TO_READ=${GB_TO_READ:-20}
SAMPLE=${SAMPLE:-5}
ABORT_C=${ABORT_C:-88}        # above healthcheck's 85 urgent, below the worst seen
READ_FROM=${READ_FROM:-/datapool/immich-upload}
MIN_FILE_MB=${MIN_FILE_MB:-50}
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
active_now() { cat "$PARAM_FILE" 2>/dev/null || echo 1000; }

target=$(( GB_TO_READ * 1024 * 1024 * 1024 ))
echo "finding files over ${MIN_FILE_MB}MB under $READ_FROM ..."
mapfile -t FILES < <(find "$READ_FROM" -type f -size +${MIN_FILE_MB}M 2>/dev/null)
[ "${#FILES[@]}" -gt 0 ] || { echo "no files over ${MIN_FILE_MB}MB to read" >&2; exit 1; }
avail=$(for f in "${FILES[@]}"; do stat -c %s "$f" 2>/dev/null; done | awk '{s+=$1} END{print s+0}')
if [ "$avail" -lt "$target" ]; then
  echo "only $(( avail / 1073741824 ))GB available in files over ${MIN_FILE_MB}MB; reading that instead" >&2
  target=$avail
fi

mkdir -p "$RESULTS"
out=$RESULTS/disk-thermal-$(date +%Y-%m-%d-%H%M).txt
progress=$(mktemp); echo 0 > "$progress"
trap 'rm -f "$progress"' EXIT

start_c=$(temp_now)
{
  echo "datapool disk thermal test - $(date '+%F %T %Z')"
  echo "reading $(( target / 1073741824 ))GB from $READ_FROM (${#FILES[@]} files over ${MIN_FILE_MB}MB)"
  echo "sampling every ${SAMPLE}s, abort at ${ABORT_C}°C"
  echo "start: ${start_c}°C, zfs_vdev_max_active=$(active_now)"
  echo
} | tee "$out"

# Reader: whole files, straight to /dev/null, no pipe in the way.
( got=0
  for f in "${FILES[@]}"; do
    [ "$got" -ge "$target" ] && break
    dd if="$f" of=/dev/null bs=4M iflag=fullblock status=none 2>/dev/null
    got=$(( got + $(stat -c %s "$f" 2>/dev/null || echo 0) ))
    echo "$got" > "$progress"
  done ) &
reader=$!
began=$SECONDS

peak=$start_c; peak_at=0; guard_fired=no; aborted=no
printf '%6s  %7s  %9s  %s\n' "t(s)" "temp" "read" "zfs_vdev_max_active" | tee -a "$out"
while kill -0 $reader 2>/dev/null; do
  sleep "$SAMPLE"
  c=$(temp_now); a=$(active_now); got=$(cat "$progress" 2>/dev/null || echo 0)
  el=$(( SECONDS - began ))
  [ "$a" -le 8 ] && guard_fired=yes
  [ "$c" -gt "$peak" ] && { peak=$c; peak_at=$el; }
  printf '%6s  %6s°C  %6sGB  %s%s\n' "$el" "$c" "$(( got / 1073741824 ))" "$a" \
    "$([ "$a" -le 8 ] && echo '  <- CLAMPED')" | tee -a "$out"
  if [ "$c" -ge "$ABORT_C" ]; then
    aborted=yes; echo "ABORT: ${c}°C >= ${ABORT_C}°C, stopping" | tee -a "$out"
    kill $reader 2>/dev/null; pkill -P $reader dd 2>/dev/null; break
  fi
done
wait $reader 2>/dev/null
took=$(( SECONDS - began )); read_bytes=$(cat "$progress" 2>/dev/null || echo 0)

echo | tee -a "$out"
echo "--- cool-down ---" | tee -a "$out"
for i in 1 2 3 4; do sleep "$SAMPLE"; printf '%6s  %6s°C\n' "+$((i * SAMPLE))" "$(temp_now)" | tee -a "$out"; done

{
  echo
  printf 'read:        %.1fGB in %ss = %s MB/s\n' \
    "$(awk -v b="$read_bytes" 'BEGIN{print b/1073741824}')" "$took" \
    "$(awk -v b="$read_bytes" -v t="$took" 'BEGIN{printf "%.0f", (t>0)? b/t/1048576 : 0}')"
  echo "start:       ${start_c}°C"
  echo "PEAK:        ${peak}°C at ${peak_at}s"
  echo "guard fired: $guard_fired"
  echo "aborted:     $aborted"
  echo
  echo "Reference: 85°C under the 2026-11-08 scrub (305G at ~284 MB/s) and"
  echo "84-87°C on 2026-10-22, both with the SSD inside the plastic bottom"
  echo "cover. Rated 70°C. A run that stays under 70°C at a comparable"
  echo "MB/s is the bar in \"Move xero's datapool SSD out of the case\"."
} | tee -a "$out"
echo
echo "saved: $out"
