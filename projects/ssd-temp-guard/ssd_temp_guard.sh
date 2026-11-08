#!/usr/bin/env bash
# Throttles ZFS when the datapool SSD gets too hot, and lets go once it cools.
#
# Written 2026-11-08, after the monthly ZFS scrub took the Kingston SA400 to
# 85°C - its rating is 70°C, and healthcheck's URGENT line is 85. The scrub
# read all 305G in 17m53s (~284 MB/s, flat out) and nothing slowed it down.
# The same shape had already happened on 2026-10-22 (SHA-1 over 43G of zips
# plus ffmpeg over 82 videos, 84-87°C for 20-50 minutes), so this is not
# about scrubs: it is about any sustained bulk read or write.
#
# Why it throttles at the vdev queue rather than per job: on this box the
# usual per-process levers do nothing to ZFS.
#   - ionice needs CFQ/BFQ. ZFS bypasses the block scheduler for its vdevs.
#   - systemd IOReadBandwidthMax (cgroup v2 io) does not reach it either:
#     ZFS issues the real block I/O from its own kernel taskqueues, not from
#     the calling process's cgroup.
# zfs_vdev_max_active caps how many I/Os ZFS will have in flight to a vdev
# at once. Lowering it slows everything on the pool - scrub, Immich imports,
# the nightly backups, the S3 archive run, whatever you type at a prompt -
# without needing to know which job is the one cooking the disk.
#
# Because that is a blunt instrument, it is applied only while the drive is
# actually hot, and taken off again when it cools:
#   >= CLAMP_AT °C for CLAMP_SAMPLES samples  -> zfs_vdev_max_active = CLAMP
#   <  RELEASE_AT °C                          -> restored to NORMAL
# The gap between the two is hysteresis, so a drive sitting right at the
# limit does not flap between fast and slow every sample.
#
# This does NOT replace fixing the airflow. The drive is screwed label-down
# into the plastic bottom cover with no airflow over it (docs/images/xero/),
# which is why it idles ~10°C above the boot SSD lying next to the fan. This
# guard stops the peaks; it does not make the bay any cooler.
#
# Runs as the SYSTEM unit ssd-temp-guard.service, not a --user one like
# immich-load-guard: writing /sys/module/zfs/parameters needs root.
#
# Thresholds can be overridden from the environment. TEMP_FILE, PARAM_FILE
# and DRY_RUN exist so the test can feed it fake readings and a fake knob.
set -uo pipefail

INTERVAL=${INTERVAL:-15}
CLAMP_AT=${CLAMP_AT:-70}          # the SA400's rated maximum
RELEASE_AT=${RELEASE_AT:-62}      # hysteresis: well clear before letting go
CLAMP_SAMPLES=${CLAMP_SAMPLES:-2} # 30s; the drive takes minutes to heat, so
                                  # this only filters out a single bad read
CLAMP=${CLAMP:-4}                 # zfs_vdev_max_active while hot
DISK_MODEL=${DISK_MODEL:-KINGSTON}
PARAM_FILE=${PARAM_FILE:-/sys/module/zfs/parameters/zfs_vdev_max_active}

SCRIPT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/.env.ntfy" ] && { set -a; . "$SCRIPT_DIR/.env.ntfy"; set +a; }
# shellcheck source=../../tools/notify/push_ntfy.sh
. "$SCRIPT_DIR/tools/notify/push_ntfy.sh"

log() { echo "$(date '+%F %T') $*"; }

# The drivetemp sensor for the datapool disk, found by model so it survives
# sda/sdb swapping around at boot. Same match healthcheck.sh uses.
if [ -z "${TEMP_FILE:-}" ]; then
  for dev in /sys/block/sd*; do
    grep -qi "$DISK_MODEL" "$dev/device/model" 2>/dev/null || continue
    for t in "$dev"/device/hwmon/hwmon*/temp1_input; do
      [ -r "$t" ] && TEMP_FILE=$t
    done
  done
fi
[ -n "${TEMP_FILE:-}" ] || {
  echo "no drivetemp sensor for a disk matching '$DISK_MODEL'" >&2
  echo "is the drivetemp module loaded? /etc/modules-load.d/drivetemp.conf" >&2
  exit 1
}
[ -r "$PARAM_FILE" ] || { echo "cannot read $PARAM_FILE - is this running as root?" >&2; exit 1; }

# What to restore to. Read it live so a hand-tuned value is respected, but if
# we are starting up while already clamped (a restart mid-hot-spell) that
# reading would pin NORMAL at the clamp value - so fall back to the stock
# default instead of remembering the throttle as normal.
if [ -z "${NORMAL:-}" ]; then
  NORMAL=$(cat "$PARAM_FILE")
  [ "$NORMAL" -le "$CLAMP" ] && NORMAL=1000
fi

set_active() {  # value
  if [ -w "$PARAM_FILE" ]; then
    echo "$1" > "$PARAM_FILE"
  else
    log "WARNING: $PARAM_FILE not writable, cannot set $1"
    return 1
  fi
}

clamped=0
release() {
  [ "$clamped" = 1 ] || return 0
  set_active "$NORMAL" && log "released: zfs_vdev_max_active back to $NORMAL"
  clamped=0
}
# A guard that leaves the pool throttled behind it is worse than no guard, so
# restore on any exit - stop, restart, reboot, crash.
trap 'release; exit 0' TERM INT EXIT

hot_n=0
log "watching $TEMP_FILE: clamp at >=${CLAMP_AT}°C x$CLAMP_SAMPLES to $CLAMP, release below ${RELEASE_AT}°C to $NORMAL, every ${INTERVAL}s"

while :; do
  sleep "$INTERVAL"

  temp=$(( $(cat "$TEMP_FILE") / 1000 ))
  [ "$temp" -ge "$CLAMP_AT" ] && hot_n=$((hot_n + 1)) || hot_n=0

  if [ "$clamped" = 0 ] && [ "$hot_n" -ge "$CLAMP_SAMPLES" ]; then
    if set_active "$CLAMP"; then
      clamped=1
      log "CLAMPED: ${temp}°C for $((hot_n * INTERVAL))s (>=${CLAMP_AT}°C), zfs_vdev_max_active $NORMAL -> $CLAMP"
      push_ntfy "xero: datapool SSD throttled at ${temp}°C" \
        "Held >=${CLAMP_AT}°C (rated 70°C), so ZFS is capped to $CLAMP in-flight I/Os until it drops below ${RELEASE_AT}°C."$'\n'"Everything on datapool is slower meanwhile. Check what is doing bulk I/O: scrub, Immich, backups." \
        4 thermometer
    fi
  elif [ "$clamped" = 1 ] && [ "$temp" -lt "$RELEASE_AT" ]; then
    release
    push_ntfy "xero: datapool SSD cooled to ${temp}°C" \
      "Below ${RELEASE_AT}°C, so ZFS is back to $NORMAL in-flight I/Os." 2 white_check_mark
  fi

  # One line a minute when all is well; every sample while clamped, since
  # that is the window worth being able to reconstruct afterwards.
  if [ "$clamped" = 1 ] || [ $(( SECONDS % 60 )) -lt "$INTERVAL" ]; then
    log "${temp}°C$([ "$clamped" = 1 ] && echo " (clamped)")"
  fi
done
