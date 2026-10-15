#!/bin/sh
# Export ZFS pool usage for node-exporter's textfile collector (cron, every minute).
#
# node-exporter only sees per-dataset statfs numbers: each dataset's "size" is
# its own data plus the shared free space, and snapshots count nowhere, so no
# sum of them gives how full the pool really is. `zfs list` on the pool root
# does: used includes children and snapshots, avail is after ZFS's ~1/32 slop
# reserve, so used / (used + avail) reaches 100% exactly when writes stop.
set -eu
dir="$(dirname "$0")/textfile"
mkdir -p "$dir"
tmp="$dir/zpool.prom.$$"
{
  echo "# HELP homelab_zpool_used_bytes Bytes used by the pool, incl. children and snapshots (zfs list used)."
  echo "# TYPE homelab_zpool_used_bytes gauge"
  echo "# HELP homelab_zpool_avail_bytes Bytes still writable, after the slop reserve (zfs list avail)."
  echo "# TYPE homelab_zpool_avail_bytes gauge"
  zfs list -Hp -d 0 -o name,used,avail | while read -r name used avail; do
    echo "homelab_zpool_used_bytes{zpool=\"$name\"} $used"
    echo "homelab_zpool_avail_bytes{zpool=\"$name\"} $avail"
  done
} > "$tmp"
mv "$tmp" "$dir/zpool.prom"
