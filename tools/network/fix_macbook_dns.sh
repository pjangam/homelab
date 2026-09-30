#!/usr/bin/env bash
# Run this ON the household MacBook (192.168.1.102). Needs sudo.
#
# Undoes the DNS overrides left behind by the 2026-08-28 outage:
#   - Wi-Fi resolved against "8.8.8.8 1.1.1.1", which bypassed Pi-hole entirely.
#     This line used to say "a manual 8.8.8.8 1.1.1.1". It was never manual -
#     ovpnagent's log shows it writing 8.8.8.8, 1.1.1.1, 192.168.0.2, 192.169.0.2
#     on every connect from 2026-07-22 to 2026-09-02, which is the window
#     2026-08-28 falls in. Same bug as the item below, at a different setting of
#     the corporate profile.
#   - en0 was resolving against 192.168.0.2 plus a second entry in public
#     192.169/16 space - neither on this LAN (192.168.1.x), so both are
#     unreachable and queries sent to them just time out.
#
# Those two are not two problems. With a reachable public resolver in the pushed
# list you get the first symptom (working, unfiltered, unnoticed for 10 days);
# with only the two off-LAN servers you get the second (every lookup times out,
# reads as "the internet is slow"). Which one depends on the profile that day.
# Afterwards the Mac takes DNS from DHCP (192.168.1.123 = Pi-hole), and
# Tailscale's MagicDNS keeps layering on top of that per the documented design.
#
# What the 192.168.0.2/192.169.0.2 pair actually is, settled 2026-09-30 after
# six occurrences (see docs/incidents/2026-09-23-mac-dns-openvpn-connect-left-
# stale-servers.md): OpenVPN Connect's root agent writes it into the `Setup:`
# layer of configd's LIVE store on every tunnel connect, and normally clears it
# on disconnect - except when the tunnel process dies instead of disconnecting,
# which skips the restore and strands it. Two consequences for this script:
#
#   - Step 1 is the only step that cures it, and for a non-obvious reason.
#     `networksetup -setdnsservers Wi-Fi empty` commits SCPreferences, which
#     makes configd recompute the Setup: keys from disk and drop the agent's
#     in-memory override. It reads as a no-op - the on-disk file was already
#     empty, so "before" and "after" both say "There aren't any DNS Servers
#     set" - and it was written off as one five times running. It is not.
#   - Step 3 is what hid the bug for a month. Toggling tailscale accept-dns
#     makes tailscaled rewrite the resolver config so the bad pair stops being
#     *used*, without clearing it, so every repair looked like a fix and the
#     evidence went with it. It is kept because MagicDNS does sometimes need
#     the nudge, but it now runs after step 1 has been verified, not instead.
set -u

# The Wi-Fi service's UUID. Its Setup: key is where the bad pair lands, and
# `networksetup` cannot see that key - so read it with scutil, here and after.
# UserDefinedName lives on the service key itself, not on its /Interface child.
WIFI_UUID=$(scutil <<< "list" 2>/dev/null \
  | awk '/^ *subKey.*Setup:\/Network\/Service\/[^\/]+$/{print $NF}' \
  | while read -r k; do
      n=$(scutil <<< "show $k" 2>/dev/null | awk -F': *' '/UserDefinedName/{print $2}')
      [ "$n" = "Wi-Fi" ] && { echo "${k##*/}"; break; }
    done)
WIFI_DNS_KEY="Setup:/Network/Service/${WIFI_UUID:-unknown}/DNS"

show_setup_dns() {
  # This, not networksetup, is the honest answer.
  if [ -n "${WIFI_UUID:-}" ] && scutil <<< "show $WIFI_DNS_KEY" 2>/dev/null | grep -q ServerAddresses; then
    echo "  Setup: override PRESENT on Wi-Fi ($WIFI_DNS_KEY):"
    scutil <<< "show $WIFI_DNS_KEY" 2>/dev/null | sed 's/^/    /'
    return 1
  fi
  echo "  Setup: no DNS override on Wi-Fi (this is the healthy state)"
  return 0
}

echo "=== before ==="
echo "--- what networksetup thinks (it answered 'clean' through every outage) ---"
networksetup -getdnsservers "Wi-Fi" | sed 's/^/  /'
echo "--- what scutil knows ---"
show_setup_dns || true
echo "--- resolvers actually bound to en0 ---"
scutil --dns | grep -A2 "if_index : 14" | grep nameserver

echo
echo "=== 1. clearing the Setup: DNS override on Wi-Fi (fall back to DHCP) ==="
# Do not skip this because the "before" block above showed networksetup clean.
# Committing an empty list is what makes configd drop the agent's live override.
sudo networksetup -setdnsservers "Wi-Fi" Empty
if show_setup_dns; then
  echo "  cleared (verified with scutil)"
else
  echo "  STILL PRESENT after clearing - something is rewriting it right now."
  echo "  Disconnect the corporate VPN and run this again; then report it in"
  echo "  docs/incidents/2026-09-23-mac-dns-openvpn-connect-left-stale-servers.md"
fi
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
echo "--- the Setup: key (the one that matters) ---"
show_setup_dns || true
echo "--- networksetup's view ---"
networksetup -getdnsservers "Wi-Fi" | sed 's/^/  /'
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

echo
echo "=== 5. who wrote it, and whether it will come back ==="
# The repair is not a cure: the next tunnel connect writes the pair again, and
# a tunnel process that dies rather than disconnecting strands it again.
SUMMARIZE="$(dirname "$0")/summarize_ovpnagent_dns.sh"
if [ -x "$SUMMARIZE" ]; then
  "$SUMMARIZE" --tail 6
else
  echo "  ($SUMMARIZE not present - re-run setup-mac-dns-recorder.sh to fetch it)"
fi
