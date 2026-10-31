#!/bin/sh
# Export the per-device byte counters of lan-gateway.nft for node-exporter's
# textfile collector. Runs as root (reading nft needs CAP_NET_ADMIN) from
# lan-gateway-usage.timer, every minute. Same shape as
# services/node-exporter/zpool_textfile.sh.
#
# Counters live in the kernel and restart at 0 when the table is reloaded or
# xero reboots; Prometheus' rate()/increase() handle that reset.
#
# The kernel counts per IP, but the router hands an IP to another device once
# the first leaves (2026-10-31: .10 was an Android phone for a week, then a
# guest's laptop, and the dashboard filed it all under the laptop). So each
# minute the growth of every IP's counter is added to the device holding that
# IP right then, in homelab_lan_device_bytes_total{id,direction}. The id is
#   - its MAC, unless several IPs share it (the TP-Link extender's clients)
#   - else "ts:<label>" when Tailscale saw it on that IP
#   - else "ip:<ip>"
# Running totals live in /run/lan-gateway-bytes.state and restart at 0 on a
# reboot, like the kernel's. The per-IP counter is still written for the old
# dashboard (homelab_lan_gateway_bytes_total{ip,direction}).
#
# Names go in separate info metrics, homelab_lan_device_name{id,device} and
# homelab_lan_device_info{ip,device}, which the dashboards join on: renaming a
# device then relabels its history instead of starting a new counter series.
# A name comes from, in order:
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
shared=/run/lan-gateway-shared.cache   # MACs seen on more than one IP at once (the extender)
state=/run/lan-gateway-bytes.state     # per-device totals, see above
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

# A MAC on two live IPs at once stands for several devices; remember it, as
# the extender's clients come and go.
ip neigh show dev enp1s0 | awk '{for (i = 1; i < NF; i++) if ($i == "lladdr") print $(i + 1)}' |
  sort | uniq -d | cat - "$shared" 2>/dev/null | sort -u > "$shared.tmp" || true
mv "$shared.tmp" "$shared"

lookup() {  # $1 = key (ip, mac or tailscale label) -> name from device-names
  [ -f "$names" ] && awk -v k="$1" '/^[[:space:]]*(#|$)/ { next }
    tolower($1) == tolower(k) { $1 = ""; sub(/^ +/, ""); print; exit }' "$names"
}

name_for() {  # $1 = ip
  mac=$(ip neigh show "$1" | awk '{for (i = 1; i < NF; i++) if ($i == "lladdr") print $(i + 1)}')
  if [ -n "$mac" ]; then
    old=$(awk -v ip="$1" '$1 == ip { print $2 }' "$macs" 2>/dev/null || true)
    if [ -n "$old" ] && [ "$old" != "$mac" ]; then
      # Another device has this IP now: forget the last one's names for it.
      for f in "$cache" "$tsnames"; do
        { grep -v "^$1 " "$f" 2>/dev/null || true; } > "$f.tmp" && mv "$f.tmp" "$f"
      done
    fi
    { grep -v "^$1 " "$macs" 2>/dev/null || true; echo "$1 $mac"; } > "$macs.tmp" && mv "$macs.tmp" "$macs"
  else
    mac=$(awk -v ip="$1" '$1 == ip { print $2 }' "$macs" 2>/dev/null || true)
  fi
  grep -qxF "$mac" "$shared" 2>/dev/null && mac=
  ts=$(awk -v ip="$1" '$1 == ip { print $2 }' "$tsnames" 2>/dev/null || true)
  # the device's id, for the per-device counters (see the header)
  if [ -n "$mac" ]; then id=$mac; elif [ -n "$ts" ]; then id="ts:$ts"; else id="ip:$1"; fi
  n=
  [ -n "$mac" ] && n=$(lookup "$mac")
  if [ -z "$n" ] && [ -n "$ts" ]; then
    n=$(lookup "$ts"); n=${n:-$ts}
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
  echo "$id ${n:-$1}"
}

# Every IP with a counter now, plus every IP device-names or Tailscale knows:
# the old dashboard joins names as of now, so a device that is quiet since the
# last reboot (counters gone) would otherwise show history by IP.
# Lines: "ip id name".
named=$(for ip in $( { echo "$counters" | awk 'NF == 3 { print $1 }'
                       awk '$1 ~ /^192\.168\.1\.[0-9]+$/ { print $1 }' "$names" "$tsnames" 2>/dev/null; } | sort -u); do
  echo "$ip $(name_for "$ip" | sed 's/[\\"]//g')"
done)

# Devices not on any IP right now keep their last name, unless device-names
# has a newer one for their MAC or Tailscale label.
renamed=$(awk '$1 == "n" { print $2 }' "$state" 2>/dev/null | while read -r id; do
  n=$(lookup "${id#ts:}" | sed 's/[\\"]//g')
  if [ -n "$n" ]; then echo "n $id $n"; fi
done)

# Add each IP's growth since last minute to the device holding it now. With
# no state yet (first run, or after a reboot) the counters only set the
# baseline. A device's first minute is held back a run, so its series starts
# at 0 and increase() counts that minute too.
{ awk '{ print "s", $0 }' "$state" 2>/dev/null || true
  echo "$renamed"
  echo "$named" | awk 'NF >= 3 { ip = $1; id = $2; $1 = $2 = ""; sub(/^ +/, ""); print "i", ip, id; print "n", id, $0 }'
  echo "$counters" | awk 'NF == 3 { print "c", $0 }'
} | awk '
  $1 == "s" { have = 1; t = $2; key = $3 " " $4
              if (t == "k") last[key] = $5
              else if (t == "t") tot[key] = $5
              else if (t == "p") paid[key] = $5   # held back last run, add now
              else if (t == "n") { id = $3; $1 = $2 = $3 = ""; sub(/^ +/, ""); name[id] = $0 }
              next }
  $1 == "n" { id = $2; $1 = $2 = ""; sub(/^ +/, ""); name[id] = $0; next }
  $1 == "i" { idof[$2] = $3; next }
  $1 == "c" { ip = $2; key = ip " " $3; k[key] = $4
              if (!have) next
              p = (key in last) ? last[key] : 0
              d = ($4 >= p) ? $4 - p : $4       # below last: the table was reloaded
              key = ((ip in idof) ? idof[ip] : "ip:" ip) " " $3
              if (key in tot) tot[key] += d
              else { tot[key] = 0; pend[key] += d }
              next }
  END { for (x in paid) tot[x] += paid[x]
        for (x in k) print "k", x, k[x]
        for (x in tot) print "t", x, tot[x]
        for (x in pend) print "p", x, pend[x]
        for (x in name) print "n", x, name[x] }' > "$state.tmp"
mv "$state.tmp" "$state"

{
  echo "# HELP homelab_lan_gateway_bytes_total Bytes a LAN device IP sent (up) or received (down) through xero as its gateway."
  echo "# TYPE homelab_lan_gateway_bytes_total counter"
  echo "$counters" | awk 'NF == 3 { printf "homelab_lan_gateway_bytes_total{ip=\"%s\",direction=\"%s\"} %s\n", $1, $2, $3 }'
  echo "# HELP homelab_lan_device_info Display name of the device on a LAN IP now (device-names, Tailscale, the router's hostname, else the IP)."
  echo "# TYPE homelab_lan_device_info gauge"
  echo "$named" | awk 'NF >= 3 { ip = $1; $1 = $2 = ""; sub(/^ +/, ""); printf "homelab_lan_device_info{ip=\"%s\",device=\"%s\"} 1\n", ip, $0 }'
  echo "# HELP homelab_lan_device_bytes_total Bytes a LAN device sent (up) or received (down) through xero, whichever IP it had."
  echo "# TYPE homelab_lan_device_bytes_total counter"
  awk '$1 == "t" { printf "homelab_lan_device_bytes_total{id=\"%s\",direction=\"%s\"} %s\n", $2, $3, $4 }' "$state"
  echo "# HELP homelab_lan_device_name Display name of a device id (as for homelab_lan_device_info)."
  echo "# TYPE homelab_lan_device_name gauge"
  awk '$1 == "n" { id = $2; $1 = $2 = ""; sub(/^ +/, ""); printf "homelab_lan_device_name{id=\"%s\",device=\"%s\"} 1\n", id, $0 }' "$state"
} > "$tmp"
chmod 644 "$tmp"
mv "$tmp" "$dir/lan_gateway.prom"
