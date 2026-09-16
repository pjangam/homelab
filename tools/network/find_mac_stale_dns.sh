#!/usr/bin/env bash
# Hunt for the Mac's bogus resolver pair in the places that SURVIVE the repair.
# RUNS ON THE MAC. Read-only - it changes nothing.
#
# Why this exists: the MacBook's DNS has broken three times the same way
# (2026-08-28, 2026-09-10, 2026-09-16) with en0 resolving against 192.168.0.2 +
# 192.169.0.2. Every existing tool here assumes you catch it live:
# diagnose_macbook_dns.sh reads the running config, and mac-dns-recorder.sh has
# to already be installed when it breaks. Neither helps once fix_macbook_dns.sh
# has toggled accept-dns and the runtime (State:) layer is clean again - which
# is how all three occurrences have ended.
#
# So this one is the cold case. It looks only at things the toggle does not
# touch: the persistent Setup: layer for EVERY location and service (not just
# the current one), remembered Wi-Fi networks, configuration profiles, VPN
# configs on disk, and the unified log's record of who changed DNS.
#
# The point of the per-location sweep: `networksetup -getdnsservers Wi-Fi`
# reads the CURRENT location's Wi-Fi service only. A stale override parked on
# another location, or on a service no longer in the service order, is
# invisible to it and has answered "there aren't any DNS Servers set" all three
# times while the bad pair sat in the plist.
#
#   find_mac_stale_dns.sh            # sweep, skipping the slow log search
#   find_mac_stale_dns.sh --logs     # include the unified log (slow: minutes)
#   find_mac_stale_dns.sh --pattern '10\.0\.0\.1'   # hunt a different address
set -u

# Unlike mac-dns-recorder.sh, this addresses macOS tools by bare name rather
# than absolute path. That script runs under launchd, where PATH is minimal and
# a missing tool silently empties a section; this one is run by hand from a
# normal shell, and bare names let the test harness stub it on Linux.

PATTERN="${PATTERN:-192\.168\.0\.2|192\.169\.0\.2}"
WANT_LOGS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --logs)    WANT_LOGS=1 ;;
    --pattern) shift; PATTERN="${1:-}" ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# Overridable only so the test harness can point them at fixtures; in normal
# use the defaults are the point.
SCPREF="${SCPREF:-/Library/Preferences/SystemConfiguration/preferences.plist}"
NETIF="${NETIF:-/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist}"

hits=0
# Every section reports one of three verdicts, never silence: a hit, a clean
# check, or an explicit "could not look". An empty section would otherwise read
# as "clean" when it really meant "this Mac does not have that file".
found()   { hits=$((hits+1)); printf '  >>> FOUND  %s\n' "$*"; }
clean()   { printf '  clean      %s\n' "$*"; }
skipped() { printf '  SKIPPED    %s\n' "$*"; }

hr() { printf '\n=== %s ===\n' "$*"; }

echo "hunting for: $PATTERN"
echo "host:        $(hostname 2>/dev/null)  $(sw_vers -productVersion 2>/dev/null)"
echo "date:        $(date '+%Y-%m-%d %H:%M:%S %Z')"

# ---------------------------------------------------------------------------
hr "the persistent store, across EVERY location and service"
# This is the file `networksetup` edits. Dumping the whole thing catches
# services and locations the current service order never mentions.
if [ -r "$SCPREF" ]; then
  dump=$(plutil -p "$SCPREF" 2>/dev/null)
  if [ -z "$dump" ]; then
    skipped "$SCPREF unreadable as a plist (try with sudo)"
  elif printf '%s' "$dump" | grep -qE "$PATTERN"; then
    found "in $SCPREF"
    # Show enough context to name the owning service/set, which is the
    # whole question: which location, which service.
    printf '%s' "$dump" | grep -nE -B25 "$PATTERN" \
      | grep -E "UserDefinedName|ServerAddresses|\"(Set|Service)[^\"]*\"|$PATTERN" \
      | tail -40 | sed 's/^/      /'
  else
    clean "no match anywhere in $SCPREF"
  fi
else
  skipped "$SCPREF not readable"
fi

# ---------------------------------------------------------------------------
hr "each network location's DNS, by name"
locs=$(networksetup -listlocations 2>/dev/null)
if [ -z "$locs" ]; then
  skipped "could not list locations"
else
  cur=$(networksetup -getcurrentlocation 2>/dev/null)
  echo "  current location: ${cur:-unknown}"
  echo "$locs" | while IFS= read -r loc; do
    [ -n "$loc" ] || continue
    mark=" "; [ "$loc" = "$cur" ] && mark="*"
    printf '  %s %s\n' "$mark" "$loc"
  done
  echo "  (a non-current location's services are covered by the plist dump above;"
  echo "   switching locations to read them would change live network state)"
fi

# ---------------------------------------------------------------------------
hr "network interface records"
if [ -r "$NETIF" ]; then
  if plutil -p "$NETIF" 2>/dev/null | grep -qE "$PATTERN"; then
    found "in $NETIF"
  else
    clean "no match in $NETIF"
  fi
else
  skipped "$NETIF not readable"
fi

# ---------------------------------------------------------------------------
hr "remembered Wi-Fi networks (a lease from another SSID can persist here)"
wifi_found=0; wifi_checked=0
for p in \
  /Library/Preferences/com.apple.wifi.known-networks.plist \
  /Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist
do
  [ -r "$p" ] || continue
  wifi_checked=1
  if plutil -p "$p" 2>/dev/null | grep -qE "$PATTERN"; then
    found "in $p"; wifi_found=1
  fi
done
if [ "$wifi_checked" = 0 ]; then
  skipped "no readable Wi-Fi network store (these need sudo on recent macOS)"
elif [ "$wifi_found" = 0 ]; then
  clean "no match in the readable Wi-Fi network stores"
fi

# ---------------------------------------------------------------------------
hr "configuration profiles (MDM or an app can inject a DNS payload)"
prof=$(profiles show 2>/dev/null)
if [ -z "$prof" ]; then
  skipped "profiles show returned nothing (needs sudo, or none installed)"
elif printf '%s' "$prof" | grep -qE "$PATTERN"; then
  found "in an installed configuration profile"
  printf '%s' "$prof" | grep -nE -B10 "$PATTERN" | sed 's/^/      /'
else
  clean "no match in installed profiles"
fi

# ---------------------------------------------------------------------------
hr "VPN configs on disk (dhcp-option DNS pushes)"
vpn_hits=0
for d in "$HOME/Library/Application Support/Tunnelblick" /Library/Application\ Support/Tunnelblick \
         "$HOME/.openvpn" /etc/openvpn "$HOME/Library/Application Support/Viscosity"
do
  [ -d "$d" ] || continue
  m=$(grep -rlE "$PATTERN" "$d" 2>/dev/null)
  [ -n "$m" ] && { found "in VPN config: $m"; vpn_hits=1; }
done
scutil --nc list 2>/dev/null | sed 's/^/  nc: /'
[ "$vpn_hits" = 0 ] && clean "no match in any VPN config directory found on disk"

# ---------------------------------------------------------------------------
hr "Tailscale's own state"
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
[ -x "$TS" ] || TS=$(command -v tailscale 2>/dev/null)
if [ -n "${TS:-}" ] && [ -x "$TS" ]; then
  if "$TS" dns status 2>&1 | grep -qE "$PATTERN"; then
    found "in the tailnet DNS config - fix it in the admin console, not here"
  else
    clean "tailnet DNS config carries no match"
  fi
else
  skipped "tailscale CLI not found"
fi

# ---------------------------------------------------------------------------
hr "the unified log: who set DNS, and when"
if [ "$WANT_LOGS" = 0 ]; then
  skipped "not searched - re-run with --logs (takes minutes)"
else
  echo "  searching the last 7 days of configd/SystemConfiguration activity..."
  echo "  (retention is volume-driven; an old occurrence may already be gone)"
  out=$(log show --last 7d --style compact \
          --predicate 'process == "configd" OR subsystem == "com.apple.SystemConfiguration"' \
          2>/dev/null | grep -nE "$PATTERN" | head -40)
  if [ -n "$out" ]; then
    found "in the unified log"
    printf '%s\n' "$out" | sed 's/^/      /'
  else
    clean "no match in the last 7 days of configd/SystemConfiguration log"
  fi
fi

# ---------------------------------------------------------------------------
hr "what the resolver looks like right now, for comparison"
scutil --dns 2>/dev/null | grep -E 'nameserver|if_index' | sed 's/^/  /' | head -20

printf '\n===================================================================\n'
if [ "$hits" -gt 0 ]; then
  echo "$hits place(s) still hold the bad pair - that is the source, and it"
  echo "persists across the accept-dns toggle. Fix it there, not with the toggle."
else
  echo "Nothing persistent holds it. That means it is written at runtime and"
  echo "only exists while DNS is broken - so the recorder is the only way to"
  echo "catch it. Install it: setup-mac-dns-recorder.sh (run on this Mac)."
fi
echo "Sections marked SKIPPED were not checked - re-run under sudo to cover them."
