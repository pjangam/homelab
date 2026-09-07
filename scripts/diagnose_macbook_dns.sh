#!/usr/bin/env bash
# Run this ON the household MacBook (192.168.1.9).
#
# Pi-hole's logs show this machine stopped sending DNS from its LAN address on
# 2026-08-28 (the day of the xero shutdown incident) and has only trickled
# queries in over Tailscale since. The server side is healthy on all three
# paths, so this reports what the Mac itself is actually configured to use.
set -u

echo "=== active network service ==="
SVC=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
echo "default interface: ${SVC:-unknown}"
networksetup -listnetworkserviceorder 2>/dev/null | grep -B1 "Device: ${SVC}" | head -4

echo
echo "=== manually-configured DNS per service (the usual culprit) ==="
# "There aren't any DNS Servers set" == good, means DHCP is being used.
networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while read -r s; do
  printf '  %-28s %s\n' "$s" "$(networksetup -getdnsservers "$s" 2>/dev/null | tr '\n' ' ')"
done

echo
echo "=== what the resolver stack actually uses ==="
scutil --dns 2>/dev/null | grep -E "nameserver|if_index|flags" | head -20

echo
echo "=== DHCP-supplied DNS (what the router is handing out) ==="
ipconfig getpacket "${SVC:-en0}" 2>/dev/null | grep -i "domain_name_server" || echo "  (none seen)"

echo
echo "=== Tailscale DNS state ==="
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
[ -x "$TS" ] || TS=$(command -v tailscale)
if [ -n "${TS:-}" ] && [ -x "$TS" ]; then
  "$TS" status 2>&1 | tail -5
  echo "--- dns status ---"
  "$TS" dns status 2>&1 | head -25
else
  echo "  tailscale CLI not found"
fi

echo
echo "=== live resolution tests ==="
for s in 192.168.1.123 100.70.215.25 100.100.100.100 192.168.1.1; do
  printf '  @%-16s ' "$s"
  r=$(dig +time=3 +tries=1 "@$s" google.com +short 2>&1 | head -1)
  echo "${r:-TIMEOUT/FAIL}"
done
printf '  %-17s ' "system resolver:"
r=$(dig +time=3 +tries=1 google.com +short 2>&1 | head -1); echo "${r:-TIMEOUT/FAIL}"

echo
echo "=== raw scutil --dns (find where stale/off-subnet resolvers come from) ==="
scutil --dns 2>/dev/null

echo
echo "=== network locations (a stale location can carry old DNS) ==="
networksetup -listlocations 2>/dev/null
echo "current: $(networksetup -getcurrentlocation 2>/dev/null)"

echo
echo "=== DHCP lease + any search domains ==="
ipconfig getpacket en0 2>/dev/null | grep -iE "domain_name|server_identifier|router"

echo
echo "=== configuration profiles / DNS payloads (MDM or a VPN app can inject these) ==="
profiles show 2>/dev/null | grep -iE "name|dns" | head -20 || echo "  (needs sudo, or none installed)"

echo
echo "=== reachability of every resolver actually configured ==="
# Anything outside this LAN's 192.168.1.0/24 can't be reached from here, so a
# stale entry from another network shows up as UNREACHABLE and explains DNS
# that hangs rather than fails fast.
scutil --dns 2>/dev/null | awk '/nameserver\[/{print $3}' | sort -u | while read -r s; do
  case "$s" in *:*) continue ;; esac   # skip IPv6
  printf '  %-16s ' "$s"
  ping -c1 -W1500 "$s" >/dev/null 2>&1 && echo "reachable" || echo "UNREACHABLE"
done
