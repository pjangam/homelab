#!/usr/bin/env bash
# Run this ON the household MacBook (192.168.1.102).
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
echo "=== manually-configured DNS per service (NOT the usual culprit - see below) ==="
# "There aren't any DNS Servers set" does NOT mean the resolver is clean. This
# asks `networksetup`, which reads the on-disk SCPreferences file, and the bug
# that broke this Mac six times never reaches that file. It answered "There
# aren't any DNS Servers set on Wi-Fi" throughout every occurrence. Read the
# "WHO owns the DNS setting" section below instead; this one is kept only to
# catch a genuine hand-set override.
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

echo
echo "=== WHO owns the DNS setting: Setup: vs State: vs the on-disk file ==="
# This is the question that decides whether it is safe to clear, and the earlier
# version of this comment had it backwards - which cost a month (2026-08-28 to
# 2026-09-30, six occurrences). What is actually true:
#   Setup:  in configd's LIVE store. Usually written by System Settings /
#           `networksetup` - but OpenVPN Connect's root agent writes here too,
#           directly, on every tunnel connect. So "it is in Setup:" does NOT
#           mean a human set it.
#   State:  written at runtime by DHCP or a VPN client.
#   the on-disk file (/Library/Preferences/SystemConfiguration/preferences.plist)
#           is what `networksetup` reads. A Setup: key present live but absent
#           here was written straight into the dynamic store and never persisted
#           - that is this bug's fingerprint, and why `networksetup` called the
#           broken state clean six times running.
# So: compare all three. Live-Setup-but-not-on-disk = a VPN client holding the
# resolver in memory; on-disk = a real manual override.
for k in $(scutil <<< "list" 2>/dev/null | awk '/Network\/Service\/.*\/DNS$/{print $NF}'); do
  case "$k" in
    Setup:*) layer="Setup (live store)" ;;
    State:*) layer="State (runtime: DHCP or VPN)" ;;
    *)       layer="?" ;;
  esac
  servers=$(scutil <<< "show $k" 2>/dev/null | awk '/^ *[0-9]+ *:/{printf "%s ", $NF}')
  [ -n "$servers" ] && printf '  %-30s %s\n' "$layer" "$servers"
done

echo
echo "--- every Setup: DNS dictionary, VERBATIM (the writer signs its work) ---"
# OpenVPN Connect leaves OpenVPNConnectOrig{ServerAddresses,SearchDomains,
# SearchOrder} in the dictionary as its own backup of what it overwrote; the
# sentinel OpenVPNConnectDeleteValue means "there was nothing here, delete the
# key when you put it back". Seeing those keys names the culprit outright.
setup_keys=$(scutil <<< "list" 2>/dev/null | awk '/Setup:.*\/DNS$/{print $NF}')
if [ -n "$setup_keys" ]; then
  for k in $setup_keys; do
    echo "  $k"
    scutil <<< "show $k" 2>/dev/null | sed 's/^/    /'
  done
else
  echo "  (no Setup: DNS key - healthy)"
fi

echo
echo "--- the same services in the ON-DISK store (what networksetup reads) ---"
plutil -extract NetworkServices xml1 -o - \
  /Library/Preferences/SystemConfiguration/preferences.plist 2>/dev/null \
  | python3 -c '
import plistlib, sys
try:
    d = plistlib.loads(sys.stdin.buffer.read())
except Exception as e:
    print("    (unreadable: %s)" % e); raise SystemExit
for k, v in sorted(d.items(), key=lambda kv: str(kv[1].get("UserDefinedName"))):
    print("    %-22s %s" % (v.get("UserDefinedName"), v.get("DNS")))
' 2>/dev/null || echo "    (could not read preferences.plist)"

echo
echo "=== ovpnagent's own log: every DNS write it has made ==="
# /var/log/ovpnagent.log prints each dynamic-store dictionary it touches as
# "*** DSDict <key>" with ORIG/MODIFIED around it. A write with no matching
# restore is this bug. "has exited, destroy tun" as the last line of a session
# is the crash path that skips the restore.
OVPNLOG=/var/log/ovpnagent.log
SUMMARIZE="$(dirname "$0")/summarize_ovpnagent_dns.sh"
if [ ! -r "$OVPNLOG" ]; then
  echo "  ($OVPNLOG not readable)"
elif [ -x "$SUMMARIZE" ]; then
  echo "  log last written: $(stat -f '%Sm' "$OVPNLOG" 2>/dev/null)"
  "$SUMMARIZE" --tail 8 | sed 's/^/  /'
else
  # A bare grep is much less use than the summariser - it cannot tell a write
  # from a restore, which is the only thing worth knowing here.
  echo "  log last written: $(stat -f '%Sm' "$OVPNLOG" 2>/dev/null)"
  grep -nE 'DSDict Setup:.*/DNS|has exited, destroy tun' "$OVPNLOG" 2>/dev/null \
    | tail -6 | sed 's/^/  /'
  echo "  ($SUMMARIZE missing - re-run setup-mac-dns-recorder.sh to fetch it)"
fi

echo
echo "=== configured VPN services ==="
scutil --nc list 2>/dev/null || echo "  (none)"

echo
echo "=== running VPN clients ==="
# Whole command line: "openvpn --config" alone does not say which config, nor
# whether it is OpenVPN Connect's own core or the separate homebrew CLI.
# Match on the executable path ($2) only. Matching anywhere in the line means a
# grep or sed of this very investigation reports itself as a running VPN client.
ps -Ao pid,command 2>/dev/null | awk 'NR>1 && tolower($2) ~ /openvpn|ovpnagent|ovpnhelper|tunnelblick|viscosity|anyconnect|globalprotect|zscaler|wireguard|nordvpn|expressvpn/ {print "  " $0}' \
  || echo "  (none running)"

echo
echo "=== tunnel interfaces present ==="
ifconfig 2>/dev/null | awk '/^(utun|ppp|ipsec|tun)[0-9]*:/{iface=$1} /inet /{if(iface){print "  " iface " " $2; iface=""}}'
