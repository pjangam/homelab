#!/bin/sh
# Export the per-device byte counters of lan-gateway.nft for node-exporter's
# textfile collector. Runs as root (reading nft needs CAP_NET_ADMIN) from
# lan-gateway-usage.timer, every minute. Same shape as
# services/node-exporter/zpool_textfile.sh.
#
# Counters live in the kernel and restart at 0 when the table is reloaded or
# xero reboots; Prometheus' rate()/increase() handle that reset.
set -eu
dir="$(dirname "$0")/../../services/node-exporter/textfile"
tmp="$dir/lan_gateway.prom.$$"
{
  echo "# HELP homelab_lan_gateway_bytes_total Bytes a LAN device sent (up) or received (down) through xero as its gateway."
  echo "# TYPE homelab_lan_gateway_bytes_total counter"
  for dir_name in up down; do
    nft -j list set ip lan_gateway "$dir_name" |
      jq -r --arg d "$dir_name" '.nftables[] | select(.set) | .set.elem[]?
        | "homelab_lan_gateway_bytes_total{ip=\"\(.elem.val)\",direction=\"\($d)\"} \(.elem.counter.bytes)"'
  done
} > "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$dir/lan_gateway.prom"
