#!/usr/bin/env bash
# Show or change when Ubuntu's zfsutils-linux cron runs the monthly ZFS TRIM
# (first Sunday) and scrub (second Sunday). Both default to 00:24; the scrub
# reads the whole pool and takes the Kingston to ~85°C (PROJECTS.md, "Move
# xero's datapool SSD out of the case"), so it is moved to 04:00, a slot no other job uses (tools/zfs/README.md).
#
#   tools/zfs/scrub_time.sh                 # show the current lines
#   sudo tools/zfs/scrub_time.sh set 04:00  # move both jobs (real terminal)
#
# The file is a dpkg conffile: a package upgrade keeps this edit, or asks.
set -euo pipefail

CRON=/etc/cron.d/zfsutils-linux
BACKUP=/root/zfsutils-linux.cron.orig   # not in /etc/cron.d: cron would run it

show() { grep -E '/usr/lib/zfs-linux/(trim|scrub)' "$CRON"; }

case "${1:-show}" in
  show) show ;;
  set)
    [[ "${2:-}" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] || { echo "usage: $0 set HH:MM" >&2; exit 2; }
    h=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]}))
    [ "$(id -u)" -eq 0 ] || { echo "needs sudo" >&2; exit 1; }
    [ -e "$BACKUP" ] || cp -p "$CRON" "$BACKUP"
    sed -i -E "/\/usr\/lib\/zfs-linux\/(trim|scrub)/ s/^[0-9]+ [0-9]+ /$m $h /" "$CRON"
    show
    ;;
  *) echo "usage: $0 [show | set HH:MM]" >&2; exit 2 ;;
esac
