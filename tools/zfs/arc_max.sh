#!/usr/bin/env bash
# Sets xero's ZFS ARC cap, live and across reboots, or prints the ARC counters
# used to judge it. The cap was 1 GiB from the 8GB-stick days; see "Use xero's
# spare RAM" in PROJECTS.md for why 8 GiB.
#
# Usage:
#   tools/zfs/arc_max.sh stats          # no sudo needed
#   sudo tools/zfs/arc_max.sh set 8     # GiB; needs a real terminal for sudo
set -euo pipefail

CONF=/etc/modprobe.d/zfs.conf
PARAM=/sys/module/zfs/parameters/zfs_arc_max
ARCSTATS=/proc/spl/kstat/zfs/arcstats

stats() {
    awk '
        /^(hits|misses|demand_metadata_hits|demand_metadata_misses|mru_ghost_hits|mfu_ghost_hits) / { v[$1] = $3 }
        /^(size|c_max) / { printf "%-24s %6.2f GiB\n", $1, $3 / 2^30 }
        END {
            printf "%-24s %6.2f %%\n", "hit rate", 100 * v["hits"] / (v["hits"] + v["misses"])
            printf "%-24s %6.2f %%\n", "metadata hit rate",
                100 * v["demand_metadata_hits"] / (v["demand_metadata_hits"] + v["demand_metadata_misses"])
            printf "%-24s %d\n", "ghost hits (mru+mfu)", v["mru_ghost_hits"] + v["mfu_ghost_hits"]
        }' "$ARCSTATS"
    echo "uptime                   $(uptime -p)"
}

set_max() {
    local gib=${1:?usage: arc_max.sh set <GiB>}
    [[ $gib =~ ^[0-9]+$ ]] && (( gib >= 1 && gib <= 16 )) || { echo "GiB must be 1-16" >&2; exit 1; }
    [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
    local bytes=$(( gib * 1024 * 1024 * 1024 ))

    echo "$bytes" > "$PARAM"
    echo "options zfs zfs_arc_max=$bytes" > "$CONF"
    update-initramfs -u    # zfs loads from the initramfs, so the conf alone is not enough

    echo "zfs_arc_max now $(cat "$PARAM") (live) and in $CONF:"
    cat "$CONF"
}

case ${1:-} in
    stats) stats ;;
    set)   set_max "${2:-}" ;;
    *)     echo "usage: $0 stats | set <GiB>" >&2; exit 1 ;;
esac
