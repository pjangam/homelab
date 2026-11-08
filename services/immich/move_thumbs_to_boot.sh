#!/usr/bin/env bash
# Moves Immich's thumbnails off datapool onto the boot disk (user, 2026-11-08).
# See "datapool storage headroom" in PROJECTS.md.
#
#   sudo services/immich/move_thumbs_to_boot.sh check     # sizes, space, state
#   sudo services/immich/move_thumbs_to_boot.sh run       # stop, copy, switch, start
#   sudo services/immich/move_thumbs_to_boot.sh finish    # after a spot-check: destroy the old dataset
#   sudo services/immich/move_thumbs_to_boot.sh rollback  # undo run (before finish)
#
# Needs split_regenerable.sh `finish` first: it expects thumbs.old to be gone.
#
# `run` stops immich-server only, copies datapool/immich-upload/thumbs to
# /var/lib/immich-thumbs, compares file counts and bytes, then adds
# IMMICH_THUMBS_LOCATION to .env and recreates the container, so
# docker-compose.yml's thumbs bind mount points at the new folder. Without that
# line the mount falls back to the datapool path. The old dataset is kept until
# `finish`.
#
# `finish` has to stop Immich too: the container's recursive mount of
# immich-upload keeps the old dataset busy, so zfs cannot destroy it.
#
# Thumbnails can be regenerated (Administration -> Jobs), and ext4 has no
# checksums, so a bad block here means a bad thumbnail, not a lost photo.
#
# For a dry test: DEST, POOL_DIR, DATASET, ENV_FILE, ZFS, COMPOSE, DOCKER and
# DRY_TEST can be set from the environment; see test_move_thumbs.sh.
set -euo pipefail

DEST=${DEST:-/var/lib/immich-thumbs}
POOL_DIR=${POOL_DIR:-/datapool/immich-upload}
DATASET=${DATASET:-datapool/immich-upload/thumbs}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
ENV_FILE=${ENV_FILE:-$REPO/.env}
ZFS=${ZFS:-zfs}
COMPOSE=${COMPOSE:-docker compose --project-directory $REPO}
DOCKER=${DOCKER:-docker}
CONTAINER=${CONTAINER:-immich_server}
MIN_FREE_GB=${MIN_FREE_GB:-20}
WAIT_S=${WAIT_S:-60}

SRC=$POOL_DIR/thumbs
KEY=IMMICH_THUMBS_LOCATION
MARKER=.on-boot-disk
IN_CONTAINER=/usr/src/app/upload/thumbs

log() { echo "$(date '+%F %T') $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" = 0 ] || [ -n "${DRY_TEST:-}" ] || die "run with sudo (Immich's files are root's)"; }
moved() { grep -q "^$KEY=" "$ENV_FILE"; }
has_ds() { $ZFS list -H -o name "$DATASET" >/dev/null 2>&1; }
files() { find "$1" -type f ! -name "$MARKER" | wc -l; }
# File bytes only: du also counts directories, which differ between ZFS and ext4.
bytes() { find "$1" -type f ! -name "$MARKER" -printf '%s\n' | awk '{ s += $1 } END { printf "%d\n", s }'; }
gib() { awk -v b="$1" 'BEGIN { printf "%.1fG", b / 2^30 }'; }
free_gb() { df -BG --output=avail "$(dirname "$DEST")" | tail -1 | tr -dc 0-9; }
stop_immich() { log "stopping immich-server"; $COMPOSE stop immich-server; }
start_immich() { log "starting immich-server"; $COMPOSE up -d --no-deps immich-server; }

# Is the marker file visible inside the running container?
in_container() {
  local i
  for ((i = 0; i < WAIT_S; i += 2)); do
    $DOCKER exec "$CONTAINER" test -f "$IN_CONTAINER/$MARKER" 2>/dev/null && return 0
    sleep 2
  done
  return 1
}

# Rewrites in place, so .env keeps its owner and mode when run under sudo.
drop_env_line() {
  local kept
  kept=$(grep -v "^$KEY=" "$ENV_FILE" || true)
  printf '%s\n' "$kept" > "$ENV_FILE"
}

cmd_check() {
  if moved; then
    echo "already moved: .env has $KEY"
    echo "dataset $DATASET: $(has_ds && echo 'still there, run finish after a spot-check' || echo 'destroyed')"
    return
  fi
  has_ds && echo "source: $DATASET" || echo "source: $DATASET NOT FOUND"
  echo "to copy: $(gib "$(bytes "$SRC")") in $(files "$SRC") files"
  echo "space: $(free_gb)G free on the boot disk, keeps at least ${MIN_FREE_GB}G"
  if [ -d "$POOL_DIR/thumbs.old" ]; then
    echo "BLOCKED: thumbs.old exists; run split_regenerable.sh finish first"
  fi
}

cmd_run() {
  need_root
  moved && { echo "already moved: .env has $KEY"; return; }
  [ ! -d "$POOL_DIR/thumbs.old" ] || die "thumbs.old exists: spot-check, then run split_regenerable.sh finish first"
  has_ds || die "$DATASET not found: has split_regenerable.sh run?"
  if [ -z "${DRY_TEST:-}" ]; then
    [ "$(stat -c %d "$(dirname "$DEST")")" = "$(stat -c %d /)" ] || die "$DEST is not on the boot disk"
  fi
  local need=$(( $(bytes "$SRC") / 2**30 + 1 + MIN_FREE_GB )) have
  have=$(free_gb)
  [ "$have" -ge "$need" ] || die "boot disk has ${have}G free, needs ${need}G"

  stop_immich
  mkdir -p "$DEST"
  chown --reference="$SRC" "$DEST"
  chmod --reference="$SRC" "$DEST"
  log "copying to $DEST"
  ionice -c3 nice rsync -aHAX --delete "$SRC/" "$DEST/" || { start_immich; die "rsync failed; Immich is back on datapool"; }

  local fs fd bs bd
  fs=$(files "$SRC"); fd=$(files "$DEST"); bs=$(bytes "$SRC"); bd=$(bytes "$DEST")
  if [ "$fs" != "$fd" ] || [ "$bs" != "$bd" ]; then
    start_immich
    die "copy differs ($fs files / $bs bytes vs $fd / $bd); Immich is back on datapool"
  fi
  log "copied and verified: $fd files, $(gib "$bd")"

  touch "$DEST/$MARKER"
  if [ -n "$(tail -c1 "$ENV_FILE")" ]; then echo >> "$ENV_FILE"; fi
  echo "$KEY=$DEST" >> "$ENV_FILE"
  start_immich
  if in_container; then
    echo
    echo "Done. Spot-check in the web UI: thumbnails load (scroll the timeline),"
    echo "and a new upload gets one. Then:"
    echo "  sudo $0 finish     # destroys the old dataset"
    echo "If anything is off:  sudo $0 rollback"
  else
    die "the container does not see $DEST. Run: sudo $0 rollback"
  fi
}

cmd_finish() {
  need_root
  moved || die "not moved yet: nothing to finish"
  in_container || die "the container does not see $DEST: rollback instead"
  has_ds || { echo "$DATASET is already gone"; return; }
  stop_immich
  local rc=0
  log "destroying $DATASET"
  $ZFS destroy "$DATASET" || rc=$?
  start_immich
  [ "$rc" = 0 ] || die "zfs destroy failed (is something else holding it?); Immich is running from the boot disk, nothing lost"
  in_container || die "Immich does not see $DEST after the restart: look at docker logs $CONTAINER"
  log "done: thumbnails are on the boot disk"
  echo "Record it: the outcome goes in \"datapool storage headroom\" (PROJECTS.md)."
}

cmd_rollback() {
  need_root
  moved || die "not moved: nothing to roll back"
  has_ds || die "$DATASET is gone (finish already ran): recreate it by hand, or regenerate thumbnails"
  stop_immich
  # Keeps thumbnails made since the move.
  ionice -c3 nice rsync -aHAX --exclude="$MARKER" "$DEST/" "$SRC/"
  drop_env_line
  start_immich
  rm -rf -- "${DEST:?}"
  log "Immich is back on $DATASET"
}

case "${1:-}" in
  check) cmd_check ;;
  run) cmd_run ;;
  finish) cmd_finish ;;
  rollback) cmd_rollback ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
