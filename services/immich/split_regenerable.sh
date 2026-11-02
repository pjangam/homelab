#!/usr/bin/env bash
# Moves Immich's regenerable folders - encoded-video/ (transcodes, ~56G) and
# thumbs/ (~6G) - out of datapool/immich-upload into child datasets with
# copies=1, so they stop taking twice their size on the Kingston. Originals,
# the DB dumps and everything else stay at copies=2. Written 2026-11-02, see
# "datapool storage headroom" in PROJECTS.md; the user decides when to run it
# (best: in winter, right after the @pre-v3.3.5 snapshots are destroyed -
# while a snapshot of immich-upload exists it still holds the old blocks, so
# the space only comes back once it is gone).
#
#   sudo services/immich/split_regenerable.sh check     # sizes, space, temps, what run would do
#   sudo services/immich/split_regenerable.sh run       # stop Immich, move, start, verify
#   sudo services/immich/split_regenerable.sh finish    # after a spot-check: delete the .old copies
#   sudo services/immich/split_regenerable.sh rollback  # undo run (before finish)
#
# Children of datapool/immich-upload mount at the very paths Immich uses
# (/datapool/immich-upload/encoded-video etc.), and Docker bind mounts are
# recursive, so docker-compose.yml does not change; `run` checks that the
# container really sees the new datasets.
#
# `run`: stops immich-server and immich-machine-learning (postgres and redis
# stay up), renames each folder to <name>.old, creates the dataset, and
# copies <name>.old into it with rsync, one <user>/<xx> subfolder at a time,
# waiting whenever the SSD reaches SSD_HOT (or the CPU CPU_HOT) until it is
# back under SSD_OK / CPU_OK - same limits as ml_backlog.sh. Then it compares
# file counts and bytes, starts Immich and checks the mounts. The .old copies
# are kept until `finish`, so a bad result is one `rollback` away.
# Interrupted (Ctrl-C, reboot, load guard)? Run `run` again: every step
# checks what is already done and rsync resumes.
#
# Immich is down for the copy (~62G at a paced rate: tens of minutes, more
# if the SSD runs hot). The healthcheck may report it down meanwhile.
# The S3 Deep Archive run already leaves these folders out
# (projects/immich-backup/archive_to_glacier.sh), so nothing changes there.
#
# For a dry test: POOL_DIR, DATASET, ZFS, COMPOSE and the sensors can be
# overridden from the environment.
set -euo pipefail

DIRS=${DIRS:-encoded-video thumbs}
DATASET=${DATASET:-datapool/immich-upload}
POOL_DIR=${POOL_DIR:-/datapool/immich-upload}
SSD_HOT=${SSD_HOT:-70}   SSD_OK=${SSD_OK:-62}
CPU_HOT=${CPU_HOT:-85}   CPU_OK=${CPU_OK:-70}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
ZFS=${ZFS:-zfs}
COMPOSE=${COMPOSE:-docker compose --project-directory $REPO}
SERVICES="immich-server immich-machine-learning"
CONTAINER=${CONTAINER:-immich_server}
DOCKER=${DOCKER:-docker}
IN_CONTAINER=/usr/src/app/upload   # where the container mounts POOL_DIR

if [ -z "${CPU_FILE:-}" ]; then
  for zone in /sys/class/thermal/thermal_zone*; do
    [ "$(cat "$zone/type" 2>/dev/null)" = x86_pkg_temp ] && CPU_FILE=$zone/temp
  done
fi
SSD_FILE=${SSD_FILE:-$(ls /sys/block/sda/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)}

log() { echo "$(date '+%F %T') $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
temps() { echo $(( $(cat "$CPU_FILE") / 1000 )) $(( $(cat "$SSD_FILE") / 1000 )); }
has_ds() { $ZFS list -H -o name "$DATASET/$1" >/dev/null 2>&1; }
bytes() { du -sb --apparent-size "$1" 2>/dev/null | cut -f1; }
files() { find "$1" -type f 2>/dev/null | wc -l; }
gib() { awk -v b="$1" 'BEGIN { printf "%.1fG", b / 2^30 }'; }

wait_cool() {
  local cpu ssd
  read -r cpu ssd < <(temps)
  [ "$cpu" -lt "$CPU_HOT" ] && [ "$ssd" -lt "$SSD_HOT" ] && return
  log "hot (cpu ${cpu}°C, ssd ${ssd}°C): waiting for cpu < $CPU_OK, ssd < $SSD_OK"
  until read -r cpu ssd < <(temps) && [ "$cpu" -lt "$CPU_OK" ] && [ "$ssd" -lt "$SSD_OK" ]; do sleep 30; done
  log "cooled (cpu ${cpu}°C, ssd ${ssd}°C), continuing"
}

need_root() { [ "$(id -u)" = 0 ] || [ -n "${DRY_TEST:-}" ] || die "run with sudo (Immich's files are root's, zfs create needs it)"; }
sensors() { [ -r "${CPU_FILE:-}" ] && [ -r "${SSD_FILE:-}" ] || die "temperature sensors not found"; }

# Does the running container see each dataset, not the parent's empty folder?
mounts_ok() {
  local d ok=0
  for d in $DIRS; do
    if [ "$($DOCKER exec "$CONTAINER" stat -c %d "$IN_CONTAINER/$d")" = "$($DOCKER exec "$CONTAINER" stat -c %d "$IN_CONTAINER")" ]; then
      echo "  $d: NOT a separate mount inside $CONTAINER"; ok=1
    else
      echo "  $d: mounted in $CONTAINER"
    fi
  done
  return $ok
}

snapshots() { $ZFS list -H -t snapshot -o name "$DATASET" 2>/dev/null || true; }

cmd_check() {
  local d total=0 b
  for d in $DIRS; do
    if has_ds "$d"; then
      echo "$d: already its own dataset ($($ZFS get -H -o value copies "$DATASET/$d") copies)$([ -d "$POOL_DIR/$d.old" ] && echo ", $d.old still there")"
    else
      b=$(bytes "$POOL_DIR/$d"); total=$((total + b))
      echo "$d: $(gib "$b") in $(files "$POOL_DIR/$d") files, to move"
    fi
  done
  echo "space: $($ZFS get -H -o value available "$DATASET") available on $DATASET; the move needs $(gib "$total") at copies=1"
  if [ -n "$(snapshots)" ]; then
    echo "snapshots of $DATASET (they keep the old blocks, so the space comes back only once they are destroyed):"
    snapshots | sed 's/^/  /'
  fi
  if [ -r "${SSD_FILE:-}" ] && [ -r "${CPU_FILE:-}" ]; then read -r cpu ssd < <(temps); echo "temps: cpu ${cpu}°C, ssd ${ssd}°C (pauses at ${CPU_HOT} / ${SSD_HOT})"; fi
  if pgrep -f ml_backlog.sh >/dev/null; then echo "WARNING: ml_backlog.sh is running - stop it first (systemctl --user stop immich-ml-backlog)"; fi
  if [ "$(id -u)" != 0 ]; then echo "(not root: sizes may be short - run with sudo for exact numbers)"; fi
}

copy_dir() {  # $1 = folder name; copies $1.old into the dataset, subfolder by subfolder
  local src=$POOL_DIR/$1.old dst=$POOL_DIR/$1 sub n=0 total
  total=$(find "$src" -mindepth 2 -maxdepth 2 -type d | wc -l)
  # <user>/<xx> chunks: a few hundred, each a few hundred MB, so the
  # temperature check runs often without thousands of rsync starts.
  while IFS= read -r sub; do
    n=$((n + 1))
    wait_cool
    mkdir -p "$dst/$(dirname "$sub")"
    ionice -c3 nice rsync -aHAX "$src/$sub/" "$dst/$sub/"
    if [ $((n % 25)) -eq 0 ]; then log "$1: $n/$total folders, ssd $(( $(cat "$SSD_FILE") / 1000 ))°C"; fi
  done < <(cd "$src" && find . -mindepth 2 -maxdepth 2 -type d | sed 's|^\./||' | sort)
  # whatever is left: top-level files (.immich marker), shallow folders,
  # and the owners/modes of the parent folders
  wait_cool
  ionice -c3 nice rsync -aHAX "$src/" "$dst/"
  local fs fd bs bd
  fs=$(files "$src"); fd=$(files "$dst"); bs=$(bytes "$src"); bd=$(bytes "$dst")
  [ "$fs" = "$fd" ] && [ "$bs" = "$bd" ] || die "$1: copy differs ($fs files / $bs bytes in $1.old, $fd / $bd in the dataset) - Immich left stopped; run again to resume, or rollback"
  log "$1: copied and verified, $fd files, $(gib "$bd")"
}

cmd_run() {
  need_root; sensors
  local d
  pgrep -f ml_backlog.sh >/dev/null && die "ml_backlog.sh is running - stop it first"
  for d in $DIRS; do
    has_ds "$d" && [ ! -d "$POOL_DIR/$d.old" ] && continue   # done earlier
    [ -d "$POOL_DIR/$d" ] || [ -d "$POOL_DIR/$d.old" ] || die "$POOL_DIR/$d not found"
  done
  log "stopping $SERVICES (postgres and redis stay up)"
  $COMPOSE stop $SERVICES
  trap 'log "interrupted: Immich left stopped. Run again to resume, or rollback."' INT TERM
  for d in $DIRS; do
    if has_ds "$d" && [ ! -d "$POOL_DIR/$d.old" ]; then log "$d: already done"; continue; fi
    if [ ! -d "$POOL_DIR/$d.old" ]; then
      mv "$POOL_DIR/$d" "$POOL_DIR/$d.old"
      log "$d: renamed to $d.old"
    fi
    if ! has_ds "$d"; then
      rmdir "$POOL_DIR/$d" 2>/dev/null || true   # an empty leftover from an earlier rollback
      $ZFS create -o copies=1 "$DATASET/$d"
      chown --reference="$POOL_DIR/$d.old" "$POOL_DIR/$d"
      chmod --reference="$POOL_DIR/$d.old" "$POOL_DIR/$d"
      log "$d: created $DATASET/$d (copies=1)"
    fi
    copy_dir "$d"
  done
  trap - INT TERM
  log "starting Immich"
  $COMPOSE start $SERVICES
  sleep 10
  if mounts_ok; then
    echo
    echo "Done. Spot-check in the web UI: thumbnails load (scroll the timeline),"
    echo "a few videos play, a new upload gets a thumbnail. Then:"
    echo "  sudo $0 finish     # deletes the .old copies"
    echo "If anything is off:  sudo $0 rollback"
  else
    echo "The container does not see the new datasets: Immich would write into the"
    echo "parent's empty folders. Run: sudo $0 rollback" >&2
    exit 1
  fi
}

cmd_finish() {
  need_root
  local d
  for d in $DIRS; do has_ds "$d" || die "$d is not its own dataset yet - nothing to finish"; done
  [ -n "${DRY_TEST:-}" ] || mounts_ok || die "the container does not see the new datasets; rollback instead"
  for d in $DIRS; do
    [ -d "$POOL_DIR/$d.old" ] || continue
    log "deleting $d.old"
    ionice -c3 rm -rf "$POOL_DIR/$d.old"
  done
  $ZFS list -o name,used,logicalused,copies -r "$DATASET"
  if [ -n "$(snapshots)" ]; then
    echo "Space is held until these snapshots are destroyed:"
    snapshots | sed 's/^/  sudo zfs destroy /'
  fi
  echo "Record it: the outcome goes in \"datapool storage headroom\" (PROJECTS.md)."
}

cmd_rollback() {
  need_root
  local d
  log "stopping $SERVICES"
  $COMPOSE stop $SERVICES
  for d in $DIRS; do
    [ -d "$POOL_DIR/$d.old" ] || { echo "$d: no $d.old - nothing to roll back (finish already ran?)"; continue; }
    if has_ds "$d"; then
      $ZFS destroy "$DATASET/$d"
      log "$d: destroyed $DATASET/$d"
    fi
    rmdir "$POOL_DIR/$d" 2>/dev/null || true
    [ -e "$POOL_DIR/$d" ] && die "$POOL_DIR/$d still exists and is not empty - look before moving $d.old back"
    mv "$POOL_DIR/$d.old" "$POOL_DIR/$d"
    log "$d: restored"
  done
  $COMPOSE start $SERVICES
  log "Immich started on the original folders"
}

case "${1:-}" in
  check) cmd_check ;;
  run) cmd_run ;;
  finish) cmd_finish ;;
  rollback) cmd_rollback ;;
  *) sed -n '2,38p' "$0"; exit 1 ;;
esac
