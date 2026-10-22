#!/bin/sh
# Export the per-device byte counters of lan-gateway.nft for node-exporter's
# textfile collector. Runs as root (reading nft needs CAP_NET_ADMIN) from
# lan-gateway-usage.timer, every minute. Same shape as
# services/node-exporter/zpool_textfile.sh.
#
# Counters live in the kernel and restart at 0 when the table is reloaded or
# xero reboots; Prometheus' rate()/increase() handle that reset.
#
# Names go in a separate info metric, homelab_lan_device_info{ip,device}, which
# the dashboard joins on ip: renaming a device then relabels its history
# instead of starting a new counter series. A name comes from, in order:
#   1. device-names (gitignored, see device-names.example) by MAC
#   2. Tailscale: a peer whose direct connection comes from this LAN IP, named
#      by its MagicDNS label (device-names can map that label to a nicer name)
#   3. device-names by IP
#   4. the router's DHCP hostname (reverse DNS at 192.168.1.1), cached an hour
#   5. the IP itself
# Devices behind the TP-Link extender all show the extender's MAC and the
# extender's DHCP hostname, so for them only 2 and 3 work. Tailscale only
# shows a peer's LAN IP while a direct connection is up, so the last one seen
# is remembered in /run (cleared on reboot, which is also when the router
# tends to reshuffle IPs).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
dir="$here/../../services/node-exporter/textfile"
names="$here/device-names"
cache=/run/lan-gateway-ptr.cache
macs=/run/lan-gateway-mac.cache   # last MAC seen per IP, for devices gone from ip neigh
tsnames=/run/lan-gateway-tailscale.cache   # last Tailscale name seen per IP
tmp="$dir/lan_gateway.prom.$$"

counters=$(for d in up down; do
  nft -j list set ip lan_gateway "$d" |
    jq -r --arg d "$d" '.nftables[] | select(.set) | .set.elem[]? | "\(.elem.val) \($d) \(.elem.counter.bytes)"'
done)

# Drop the router-hostname cache hourly, so new or changed hostnames show up.
[ -n "$(find "$cache" -mmin -60 2>/dev/null)" ] || : > "$cache"

# Tailscale peers with a direct connection from the LAN: "ip label" lines.
# A fresh sighting replaces any older line for that IP or that name.
tailscale status --json 2>/dev/null | jq -r '.Peer[]? | select((.CurAddr // "") | startswith("192.168.1."))
  | "\(.CurAddr | split(":")[0]) \(.DNSName | split(".")[0])"' | while read -r ip label; do
  { awk -v ip="$ip" -v n="$label" '$1 != ip && $2 != n' "$tsnames" 2>/dev/null || true; echo "$ip $label"; } > "$tsnames.tmp"
  mv "$tsnames.tmp" "$tsnames"
done

lookup() {  # $1 = key (ip, mac or tailscale label) -> name from device-names
  [ -f "$names" ] && awk -v k="$1" '/^[[:space:]]*(#|$)/ { next }
    tolower($1) == tolower(k) { $1 = ""; sub(/^ +/, ""); print; exit }' "$names"
}

name_for() {  # $1 = ip
  mac=$(ip neigh show "$1" | awk '{for (i = 1; i < NF; i++) if ($i == "lladdr") print $(i + 1)}')
  if [ -n "$mac" ]; then
    { grep -v "^$1 " "$macs" 2>/dev/null || true; echo "$1 $mac"; } > "$macs.tmp" && mv "$macs.tmp" "$macs"
  else
    mac=$(awk -v ip="$1" '$1 == ip { print $2 }' "$macs" 2>/dev/null)
  fi
  n=
  [ -n "$mac" ] && n=$(lookup "$mac")
  if [ -z "$n" ]; then
    ts=$(awk -v ip="$1" '$1 == ip { print $2 }' "$tsnames" 2>/dev/null)
    [ -n "$ts" ] && { n=$(lookup "$ts"); n=${n:-$ts}; }
  fi
  [ -n "$n" ] || n=$(lookup "$1")
  if [ -z "$n" ]; then
    if grep -q "^$1 " "$cache"; then
      n=$(grep "^$1 " "$cache" | cut -d' ' -f2-)
    # dig prints a timeout as ";; communications error ..." on stdout, so keep
    # only a hostname line, and cache only an answer (a timeout retries next run).
    elif ptr=$(dig +short +time=1 +tries=1 -x "$1" @192.168.1.1 2>/dev/null); then
      n=$(echo "$ptr" | grep -m1 '^[A-Za-z0-9_-][A-Za-z0-9._-]*\.$' | sed 's/\.$//' || true)
      echo "$1 $n" >> "$cache"
    fi
  fi
  case "$n" in *';'*) n= ;; esac   # a bad entry cached before 2026-10-22's fix
  echo "${n:-$1}"
}

{
  echo "# HELP homelab_lan_gateway_bytes_total Bytes a LAN device sent (up) or received (down) through xero as its gateway."
  echo "# TYPE homelab_lan_gateway_bytes_total counter"
  echo "$counters" | awk 'NF == 3 { printf "homelab_lan_gateway_bytes_total{ip=\"%s\",direction=\"%s\"} %s\n", $1, $2, $3 }'
  echo "# HELP homelab_lan_device_info Display name of a LAN device IP (device-names, Tailscale, the router's hostname, else the IP)."
  echo "# TYPE homelab_lan_device_info gauge"
  # Name every IP with a counter now, plus every IP device-names or Tailscale
  # knows: the dashboard joins names as of now, so a device that is quiet
  # since the last reboot (counters gone) would otherwise show history by IP.
  for ip in $( { echo "$counters" | awk 'NF == 3 { print $1 }'
                 awk '$1 ~ /^192\.168\.1\.[0-9]+$/ { print $1 }' "$names" "$tsnames" 2>/dev/null; } | sort -u); do
    n=$(name_for "$ip" | sed 's/[\\"]//g')
    echo "homelab_lan_device_info{ip=\"$ip\",device=\"$n\"} 1"
  done
} > "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$dir/lan_gateway.prom"
