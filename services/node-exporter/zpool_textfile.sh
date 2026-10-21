#!/bin/sh
# Export ZFS pool usage for node-exporter's textfile collector (cron, every minute).
#
# node-exporter only sees per-dataset statfs numbers: each dataset's "size" is
# its own data plus the shared free space, and snapshots count nowhere, so no
# sum of them gives how full the pool really is. `zfs list` on the pool root
# does: used includes children and snapshots, avail is after ZFS's ~1/32 slop
# reserve, so used / (used + avail) reaches 100% exactly when writes stop.
#
# Also each vdev's read/write/checksum error counts (what `zpool status`
# shows; they hold until `zpool clear`), since 2026-10-21 when datapool's
# SSD stalled for 44s and logged 5 read and 2 write errors.
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
  echo "# HELP homelab_zpool_vdev_errors I/O errors on a vdev since the last zpool clear (zpool status counts)."
  echo "# TYPE homelab_zpool_vdev_errors gauge"
  for pool in $(zpool list -H -o name); do
    zpool get -Hp read_errors,write_errors,checksum_errors "$pool" all-vdevs |
      while read -r vdev prop value _source; do
        echo "homelab_zpool_vdev_errors{zpool=\"$pool\",vdev=\"$vdev\",type=\"${prop%_errors}\"} $value"
      done
  done
} > "$tmp"
mv "$tmp" "$dir/zpool.prom"
