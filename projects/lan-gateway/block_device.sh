#!/usr/bin/env bash
# Temporarily cut a LAN device off the internet at xero, the gateway.
# Written 2026-10-31 for an unknown laptop (192.168.1.10, hostname
# p3blap-d141lmlh) seen on the Network usage dashboard.
#
#   sudo block_device.sh block 192.168.1.10        # by IP (or a MAC aa:bb:..)
#   sudo block_device.sh unblock 192.168.1.10
#   sudo block_device.sh list                      # blocked, with drop counts
#
# Works only for devices whose gateway is xero (DHCP devices; see README.md):
# their forwarded traffic is dropped, LAN traffic is untouched. A separate
# table from lan_gateway.nft so the usage counters keep running. Not
# persistent: a reboot or `sudo nft delete table ip lan_block` clears it.
# Blocking by IP stops working if the router hands the device a new address;
# `list` shows the MAC xero last saw for each blocked IP, so block that too.
set -euo pipefail

table() {
  nft list table ip lan_block >/dev/null 2>&1 && return
  nft -f - <<'EOF'
table ip lan_block {
	set ips { type ipv4_addr; counter; }
	set macs { type ether_addr; counter; }
	chain forward {
		type filter hook forward priority filter - 10; policy accept;
		iifname "enp1s0" ip saddr @ips drop
		iifname "enp1s0" ether saddr @macs drop
	}
}
EOF
}

set_for() { [[ $1 == *:* ]] && echo macs || echo ips; }

case "${1:-}" in
  block)   table; nft add element ip lan_block "$(set_for "$2")" "{ $2 }"; echo "blocked $2" ;;
  unblock) nft delete element ip lan_block "$(set_for "$2")" "{ $2 }"; echo "unblocked $2" ;;
  list)
    nft list set ip lan_block ips 2>/dev/null | grep -A20 elements || echo "no IPs blocked"
    nft list set ip lan_block macs 2>/dev/null | grep -A20 elements || echo "no MACs blocked"
    for ip in $(nft -j list set ip lan_block ips 2>/dev/null | grep -o '"[0-9.]*\.[0-9]*"' | tr -d '"'); do
      echo "$ip last seen as: $(ip neigh show "$ip" | awk '{print $5}')"
    done ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
