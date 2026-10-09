#!/usr/bin/env bash
# Stops Immich's containers if xero runs too hot, too short of memory or
# pinned at full CPU for too long. Written 2026-10-09, when Immich came back
# on the new 32GB stick with ~12k photos of ML backlog ahead of it: the N5105
# reached 103°C under memtest86+ (TjMax 105) and the old RAM corrupted
# memory under sustained full-core load, so a long unattended ML run is
# exactly the load that has gone wrong on this box before.
#
# Samples every INTERVAL seconds. A limit trips only when it holds for
# several samples in a row, so a single spike does nothing:
#   temperature  x86_pkg_temp >= TEMP_MAX °C        for TEMP_SAMPLES samples
#   memory       MemAvailable  < MEM_MIN_MB          for MEM_SAMPLES samples
#   CPU          all-core busy >= CPU_MAX %          for CPU_SAMPLES samples
# When one trips it stops every running container named immich_* (only
# those - HA, Pi-hole and the rest keep running), sends an urgent ntfy push
# and writes TRIP_FILE. While that file exists the guard keeps Immich
# stopped, including after a reboot, when `restart: always` would otherwise
# bring it straight back. Re-arm it once the cause is dealt with:
#   services/immich/load_guard.sh --reset && docker compose up -d
#
# Runs as the systemd --user unit immich-load-guard.service (see the unit
# file next to this script). Thresholds can be overridden from the
# environment; TEMP_FILE, MEMINFO and STAT exist so the test can feed it
# fake readings.
set -uo pipefail

INTERVAL=${INTERVAL:-15}
TEMP_MAX=${TEMP_MAX:-93}        # healthcheck warns at 90, memtest86+ erred at 103
TEMP_SAMPLES=${TEMP_SAMPLES:-4}  # 1 minute
MEM_MIN_MB=${MEM_MIN_MB:-1536}
MEM_SAMPLES=${MEM_SAMPLES:-4}
CPU_MAX=${CPU_MAX:-95}
CPU_SAMPLES=${CPU_SAMPLES:-40}   # 10 minutes
TRIP_FILE=${TRIP_FILE:-$HOME/.cache/immich-load-guard/tripped}
MEMINFO=${MEMINFO:-/proc/meminfo}
STAT=${STAT:-/proc/stat}
DOCKER=${DOCKER:-docker}

SCRIPT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/.env.ntfy" ] && { set -a; . "$SCRIPT_DIR/.env.ntfy"; set +a; }
# shellcheck source=../../tools/notify/push_ntfy.sh
. "$SCRIPT_DIR/tools/notify/push_ntfy.sh"

if [ "${1:-}" = --reset ]; then
  rm -f "$TRIP_FILE" && echo "re-armed; start Immich with: docker compose up -d"
  exit 0
fi

if [ -z "${TEMP_FILE:-}" ]; then
  for zone in /sys/class/thermal/thermal_zone*; do
    [ "$(cat "$zone/type")" = x86_pkg_temp ] && TEMP_FILE=$zone/temp
  done
fi
[ -n "${TEMP_FILE:-}" ] || { echo "no x86_pkg_temp thermal zone" >&2; exit 1; }

log() { echo "$(date '+%F %T') $*"; }

stop_immich() {
  local running
  running=$($DOCKER ps --filter name=^immich_ --format '{{.Names}}')
  [ -n "$running" ] || return 0
  # ML first: it is the load. Postgres gets a normal stop, so it shuts down clean.
  local c
  for c in immich_machine_learning immich_server $(grep -vx 'immich_machine_learning\|immich_server' <<< "$running"); do
    grep -qx "$c" <<< "$running" && $DOCKER stop "$c" >/dev/null && log "stopped $c"
  done
}

trip() {
  log "TRIPPED: $1"
  mkdir -p "$(dirname "$TRIP_FILE")"
  echo "$(date '+%F %T') $1" > "$TRIP_FILE"
  stop_immich
  push_ntfy "xero: Immich stopped by load guard" \
    "$1"$'\n'"Immich stays stopped until: services/immich/load_guard.sh --reset && docker compose up -d" \
    5 rotating_light
}

read_cpu() { awk '/^cpu /{idle=$5+$6; t=0; for(i=2;i<=NF;i++) t+=$i; print t, idle}' "$STAT"; }

temp_n=0 mem_n=0 cpu_n=0
read -r prev_total prev_idle < <(read_cpu)
log "watching: temp >= ${TEMP_MAX}°C x$TEMP_SAMPLES, mem < ${MEM_MIN_MB}MB x$MEM_SAMPLES, cpu >= ${CPU_MAX}% x$CPU_SAMPLES, every ${INTERVAL}s"

while :; do
  if [ -f "$TRIP_FILE" ]; then
    stop_immich   # keeps it down after a reboot or a manual start
  fi

  sleep "$INTERVAL"

  temp=$(( $(cat "$TEMP_FILE") / 1000 ))
  mem_mb=$(awk '/^MemAvailable:/{print int($2/1024)}' "$MEMINFO")
  read -r total idle < <(read_cpu)
  dt=$(( total - prev_total )); di=$(( idle - prev_idle ))
  cpu=$(( dt > 0 ? 100 * (dt - di) / dt : 0 ))
  prev_total=$total prev_idle=$idle

  [ "$temp" -ge "$TEMP_MAX" ] && temp_n=$((temp_n + 1)) || temp_n=0
  [ "$mem_mb" -lt "$MEM_MIN_MB" ] && mem_n=$((mem_n + 1)) || mem_n=0
  [ "$cpu" -ge "$CPU_MAX" ] && cpu_n=$((cpu_n + 1)) || cpu_n=0

  # One status line a minute is plenty for the journal.
  [ $(( SECONDS % 60 )) -lt "$INTERVAL" ] && log "temp ${temp}°C, mem avail ${mem_mb}MB, cpu ${cpu}%"

  [ -f "$TRIP_FILE" ] && { temp_n=0 mem_n=0 cpu_n=0; continue; }
  if [ "$temp_n" -ge "$TEMP_SAMPLES" ]; then
    trip "CPU at ${temp}°C for $((temp_n * INTERVAL))s (limit ${TEMP_MAX}°C)"
  elif [ "$mem_n" -ge "$MEM_SAMPLES" ]; then
    trip "only ${mem_mb}MB memory available for $((mem_n * INTERVAL))s (limit ${MEM_MIN_MB}MB)"
  elif [ "$cpu_n" -ge "$CPU_SAMPLES" ]; then
    trip "CPU ${cpu}% busy for $((cpu_n * INTERVAL / 60)) min (limit ${CPU_MAX}%)"
  fi
done
