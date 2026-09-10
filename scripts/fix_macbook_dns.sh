#!/usr/bin/env bash
# Run this ON the household MacBook (192.168.1.102). Needs sudo.
#
# Undoes the DNS overrides left behind by the 2026-08-28 outage:
#   - Wi-Fi had a manual "8.8.8.8 1.1.1.1", which bypassed Pi-hole entirely.
#   - en0 was resolving against 192.168.0.2 plus a second entry in public
#     192.169/16 space - neither on this LAN (192.168.1.x), so both are
#     unreachable and queries sent to them just time out.
# Afterwards the Mac takes DNS from DHCP (192.168.1.123 = Pi-hole), and
# Tailscale's MagicDNS keeps layering on top of that per the documented design.
set -u

echo "=== before ==="
networksetup -getdnsservers "Wi-Fi"
scutil --dns | grep -A2 "if_index : 14" | grep nameserver

echo
echo "=== 1. clearing the manual DNS override on Wi-Fi (fall back to DHCP) ==="
sudo networksetup -setdnsservers "Wi-Fi" Empty
# Also clear any other service carrying a stale override.
for svc in "USB 10/100/1000 LAN" "Thunderbolt Bridge" "iPhone USB"; do
  cur=$(networksetup -getdnsservers "$svc" 2>/dev/null)
  case "$cur" in
    *aren\'t*) ;;                                   # already clean
    "") ;;
    *) echo "  clearing stale override on $svc: $cur"
       sudo networksetup -setdnsservers "$svc" Empty ;;
  esac
done

echo
echo "=== 2. flushing the macOS resolver cache ==="
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
echo "  done"

echo
echo "=== 3. re-applying Tailscale's DNS config ==="
# MagicDNS was answering from its own cache rather than forwarding to Pi-hole,
# so toggling accept-dns forces tailscaled to rewrite the resolver config.
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
[ -x "$TS" ] || TS=$(command -v tailscale)
if [ -n "${TS:-}" ] && [ -x "$TS" ]; then
  "$TS" set --accept-dns=false && "$TS" set --accept-dns=true
  echo "  toggled"
else
  echo "  tailscale CLI not found - toggle 'Use Tailscale DNS' in the menu bar instead"
fi

echo
echo "=== after ==="
networksetup -getdnsservers "Wi-Fi"
echo "--- active resolvers ---"
scutil --dns | grep nameserver | sort -u
echo "--- DHCP is offering ---"
ipconfig getpacket en0 2>/dev/null | grep -i domain_name_server

echo
echo "=== 4. proof it now goes through Pi-hole ==="
MARKER="macbook-fixed-$RANDOM.example.com"
dig +time=4 +tries=1 "$MARKER" >/dev/null 2>&1
echo "  sent marker: $MARKER"
echo "  On xero, confirm it arrived:"
echo "    docker exec pihole grep '$MARKER' /var/log/pihole/pihole.log"
