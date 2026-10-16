#!/usr/bin/env bash
# Repeatable cooling benchmark for xero: pin every core for DURATION seconds,
# then watch the cool-down, sampling x86_pkg_temp and average core clock.
# Compare runs before/after a cooling change (fan clean, risers, USB fan).
#
# Stops early at ABORT_C so services/immich/load_guard.sh (93°C held for a
# minute) never trips; when that happens, "time to ABORT_C" is the result
# to compare instead of the peak.
#
#   tools/host-stats/thermal_load_test.sh [label]
set -euo pipefail

DURATION=${DURATION:-300}
COOLDOWN=${COOLDOWN:-120}
INTERVAL=${INTERVAL:-5}
ABORT_C=${ABORT_C:-92}
LABEL=${1:-baseline}

for zone in /sys/class/thermal/thermal_zone*; do
  [ "$(cat "$zone/type")" = x86_pkg_temp ] && TEMP_FILE=$zone/temp
done
[ -n "${TEMP_FILE:-}" ] || { echo "no x86_pkg_temp thermal zone" >&2; exit 1; }

temp() { echo $(( $(cat "$TEMP_FILE") / 1000 )); }
mhz() { awk '/^cpu MHz/ {s+=$4; n++} END {printf "%d", s/n}' /proc/cpuinfo; }

pids=()
stop_load() { [ ${#pids[@]} -gt 0 ] && kill "${pids[@]}" 2>/dev/null; pids=(); }
trap stop_load EXIT

echo "# $LABEL $(date '+%F %T') idle=$(temp)C load=$(cut -d' ' -f1 /proc/loadavg)"
echo "phase,t_s,temp_c,avg_mhz"
for _ in $(seq "$(nproc)"); do yes >/dev/null & pids+=($!); done

start=$(date +%s) peak=0 peak_t=0 aborted=""
while :; do
  t=$(( $(date +%s) - start )) c=$(temp)
  echo "load,$t,$c,$(mhz)"
  [ "$c" -gt "$peak" ] && peak=$c peak_t=$t
  if [ "$c" -ge "$ABORT_C" ]; then aborted=$t; break; fi
  [ "$t" -ge "$DURATION" ] && break
  sleep "$INTERVAL"
done
stop_load
end_c=$(temp)

sleep_start=$(date +%s)
while :; do
  t=$(( $(date +%s) - sleep_start ))
  echo "cool,$t,$(temp),$(mhz)"
  [ "$t" -ge "$COOLDOWN" ] && break
  sleep "$INTERVAL"
done

echo "# peak=${peak}C at ${peak_t}s${aborted:+, ABORTED at ${ABORT_C}C after ${aborted}s}; end-of-load=${end_c}C; after ${COOLDOWN}s cool-down=$(temp)C"
