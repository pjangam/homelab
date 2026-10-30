#!/usr/bin/env bash
# Works through Immich's ML backlog (face detection, then smart search) in
# batches with rests in between, pausing early whenever xero or the Kingston
# datapool SSD runs hot. Written 2026-10-30: ~13k assets had never had face
# detection, because the "Missing" jobs were never queued after Immich came
# back, and an unthrottled pass is the sustained load that has gone wrong on
# this box before (see load_guard.sh).
#
# Sets both jobs' concurrency to 1 (the ML container is also capped at
# `cpus: 1` in docker-compose.yml), queues only assets missing results, and
# runs one queue at a time:
#   run RUN_MIN minutes -> pause REST_MIN minutes -> repeat
# and pauses mid-batch if x86_pkg_temp >= CPU_HOT or the SSD >= SSD_HOT,
# resuming once both are back under CPU_OK / SSD_OK. The load guard still
# stands behind it at 93°C.
#
# Stopping it (Ctrl-C, or `systemctl --user stop immich-ml-backlog` when run
# detached) leaves the current queue PAUSED, so nothing carries on
# unsupervised; run it again to continue from where it stopped. New uploads
# get no faces or smart search while a queue is paused.
#
# Detached: systemd-run --user --unit immich-ml-backlog services/immich/ml_backlog.sh
#           journalctl --user -u immich-ml-backlog -f
set -uo pipefail

RUN_MIN=${RUN_MIN:-20}
REST_MIN=${REST_MIN:-10}
CPU_HOT=${CPU_HOT:-85}   CPU_OK=${CPU_OK:-70}
SSD_HOT=${SSD_HOT:-62}   SSD_OK=${SSD_OK:-55}   # Kingston A400 is rated 70°C
INTERVAL=${INTERVAL:-15}
QUEUES=${QUEUES:-faceDetection smartSearch}
API=${API:-http://localhost:2283/api}

cd "$(dirname "$0")/../.." || exit 1
: "${IMMICH_API_KEY:=$(sed -n 's/^IMMICH_API_KEY=//p' .env)}"
[[ -n $IMMICH_API_KEY ]] || { echo "IMMICH_API_KEY not set and not in .env" >&2; exit 1; }

for zone in /sys/class/thermal/thermal_zone*; do
  [ "$(cat "$zone/type")" = x86_pkg_temp ] && CPU_FILE=$zone/temp
done
SSD_FILE=$(ls /sys/block/sda/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
grep -q KINGSTON /sys/block/sda/device/model || { echo "sda is not the Kingston" >&2; exit 1; }
[ -n "${CPU_FILE:-}" ] && [ -n "$SSD_FILE" ] || { echo "temperature sensors not found" >&2; exit 1; }

log() { echo "$(date '+%F %T') $*"; }
api() { curl -sf -H "x-api-key: $IMMICH_API_KEY" -H 'Content-Type: application/json' "$@"; }
temps() { echo $(( $(cat "$CPU_FILE") / 1000 )) $(( $(cat "$SSD_FILE") / 1000 )); }
pause() { api -X PUT "$API/queues/$1" -d "{\"isPaused\":$2}" >/dev/null; }
# waiting + active + paused jobs left in a queue. Retries while Immich is down
# (an upgrade or the load guard), so an outage never reads as "queue empty".
left() {
  local n
  until n=$(api "$API/queues/$1" | python3 -c 'import json,sys; s=json.load(sys.stdin)["statistics"]; print(s["waiting"]+s["active"]+s["paused"]+s["delayed"])' 2>/dev/null); do
    sleep 60
  done
  echo "$n"
}

current=
trap '[ -n "$current" ] && pause "$current" true && log "stopped; $current left PAUSED - run again to continue"; exit 0' INT TERM

# Concurrency 1 for every queue we touch.
api "$API/system-config" | python3 -c '
import json, sys
c = json.load(sys.stdin)
for q in sys.argv[1:]:
    c["job"][q]["concurrency"] = 1
print(json.dumps(c))' $QUEUES | api -X PUT "$API/system-config" -d @- >/dev/null \
  || { echo "could not set concurrency" >&2; exit 1; }
log "concurrency 1 for: $QUEUES"

for q in $QUEUES; do pause "$q" true; done
for q in $QUEUES; do
  current=$q
  api -X PUT "$API/jobs/$q" -d '{"command":"start","force":false}' >/dev/null || { log "could not queue $q"; exit 1; }
  sleep 5
  log "$q: $(left "$q") queued"
  while [ "$(left "$q")" -gt 0 ]; do
    pause "$q" false
    log "$q: batch start, $(left "$q") left, cpu/ssd $(temps | tr ' ' /)°C"
    end=$(( SECONDS + RUN_MIN * 60 ))
    while [ $SECONDS -lt $end ] && [ "$(left "$q")" -gt 0 ]; do
      read -r cpu ssd < <(temps)
      if [ "$cpu" -ge "$CPU_HOT" ] || [ "$ssd" -ge "$SSD_HOT" ]; then
        pause "$q" true
        log "$q: hot (cpu ${cpu}°C, ssd ${ssd}°C), paused"
        until read -r cpu ssd < <(temps); [ "$cpu" -lt "$CPU_OK" ] && [ "$ssd" -lt "$SSD_OK" ]; do sleep "$INTERVAL"; done
        log "$q: cooled (cpu ${cpu}°C, ssd ${ssd}°C), resuming"
        pause "$q" false
      fi
      sleep "$INTERVAL"
    done
    pause "$q" true
    [ "$(left "$q")" -gt 0 ] || break
    log "$q: rest ${REST_MIN}m, $(left "$q") left, cpu/ssd $(temps | tr ' ' /)°C"
    sleep $(( REST_MIN * 60 ))
  done
  pause "$q" false
  log "$q: done"
done
current=
log "ML backlog done"
