#!/usr/bin/env bash
# Records the MacBook's resolver configuration every time it changes.
# RUNS ON THE MAC, under launchd. Install with setup-mac-dns-recorder.sh.
#
# Why this exists: the Mac's DNS has broken twice now (2026-08-28, 2026-09-10)
# with en0 resolving against 192.168.0.2 + 192.169.0.2 - two servers that are
# not on this LAN and cannot be reached, so queries hang rather than fail. Both
# times the fix (toggling tailscale accept-dns) destroyed the evidence before
# anyone could ask *what wrote them*. `networksetup` showed no manual override
# and DHCP was correctly offering 192.168.1.123, so something writes those at
# the runtime (State:) layer and we still do not know what.
#
# Answered 2026-09-30, and the guess above was wrong twice over: the pair is
# written into the *Setup:* layer of configd's in-memory store (never to disk),
# by OpenVPN Connect's root agent ovpnagent, on every tunnel *connect*. See
# docs/incidents/2026-09-23-mac-dns-openvpn-connect-left-stale-servers.md. The
# recorder stays installed because the open question is now a negative one -
# which session endings skip ovpnagent's restore - and only an unattended log
# can catch the next one of those.
#
# So: snapshot on change, unattended, and keep the history. The next time DNS
# breaks, the answer is already on disk instead of being cleared to fix it.
#
# Deliberately sends no DNS queries of its own - it must not add traffic to the
# Pi-hole log that a later investigation would have to explain away.
#
#   mac-dns-recorder.sh              # the launchd loop (poll, snapshot on change)
#   mac-dns-recorder.sh --once       # force one snapshot now
#   mac-dns-recorder.sh --show [N]   # recorder health + the last N snapshots (default 1)
#   mac-dns-recorder.sh --timeline   # one line per change: when, and which resolvers
set -u

STATE_DIR="${DNS_RECORDER_DIR:-$HOME/Library/Logs/homelab/dns-recorder}"
LOG="$STATE_DIR/snapshots.log"
LAST="$STATE_DIR/.last-state"
POLLED="$STATE_DIR/.last-poll"
INTERVAL="${DNS_RECORDER_INTERVAL:-20}"
MAXSIZE=$((4 * 1024 * 1024))

# A launchd job's PATH is not your shell's, and macOS keeps every tool this
# script needs in /usr/sbin or /sbin. Address them absolutely so a wrong PATH
# degrades a single line rather than silently emptying whole sections.
# (Overridable only so the test harness can stub them; in normal use the
# defaults are the point.)
SCUTIL="${SCUTIL:-/usr/sbin/scutil}"
NETWORKSETUP="${NETWORKSETUP:-/usr/sbin/networksetup}"
IPCONFIG="${IPCONFIG:-/usr/sbin/ipconfig}"
ROUTE="${ROUTE:-/sbin/route}"
PING="${PING:-/sbin/ping}"
IFCONFIG="${IFCONFIG:-/sbin/ifconfig}"

# ---------------------------------------------------------------------------
# the cheap state: polled often, so it may not ping, resolve, or shell out far
# ---------------------------------------------------------------------------
dns_owners() {
  # Setup: = written by System Settings / networksetup, survives reboots.
  # State: = written at runtime by DHCP or a VPN client.
  # Which layer holds the bad servers is the question this whole recorder
  # exists to answer, so it is captured on every single change.
  for k in $("$SCUTIL" <<< "list" 2>/dev/null | awk '/Network\/Service\/.*\/DNS$/{print $NF}'); do
    case "$k" in
      Setup:*) layer="Setup (persistent/manual)" ;;
      State:*) layer="State (runtime: DHCP or VPN)" ;;
      *)       layer="?" ;;
    esac
    servers=$("$SCUTIL" <<< "show $k" 2>/dev/null | awk '/^ *[0-9]+ *:/{printf "%s ", $NF}')
    [ -n "$servers" ] && printf '  %-30s %-46s %s\n' "$layer" "$k" "$servers"
  done
}

cheap_state() {
  "$SCUTIL" --dns 2>/dev/null
  dns_owners
  cat /etc/resolv.conf 2>/dev/null
}

# ---------------------------------------------------------------------------
# the snapshot: only written when the cheap state actually changed, so it can
# afford to be slow and thorough
# ---------------------------------------------------------------------------
snapshot() {
  reason="$1"
  iface=$("$ROUTE" -n get default 2>/dev/null | awk '/interface:/{print $2}')
  iface="${iface:-en0}"
  {
    echo "==================================================================="
    echo "SNAPSHOT  $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "reason:   $reason"
    echo "==================================================================="

    echo
    echo "--- where this Mac is (a different network is a prime suspect) ---"
    echo "  default interface: $iface"
    echo "  address:           $("$IPCONFIG" getifaddr "$iface" 2>/dev/null || echo '(none)')"
    echo "  wi-fi network:     $("$NETWORKSETUP" -getairportnetwork "$iface" 2>/dev/null | sed 's/^Current Wi-Fi Network: //')"
    echo "  network location:  $("$NETWORKSETUP" -getcurrentlocation 2>/dev/null)"

    echo
    echo "--- WHO owns the DNS setting: Setup (persistent) vs State (runtime) ---"
    dns_owners | sed 's/^/ /' || true

    echo
    echo "--- every Setup: DNS dictionary, VERBATIM ---"
    # The ServerAddresses line above is not enough. What named the writer on
    # 2026-09-30 was the *other* keys in this dictionary: OpenVPN Connect
    # leaves OpenVPNConnectOrig{ServerAddresses,SearchDomains,SearchOrder}
    # behind as its own backup of what it overwrote. Print the dictionary
    # whole so the next occurrence names its writer without a follow-up.
    setup_keys=$("$SCUTIL" <<< "list" 2>/dev/null | awk '/Setup:.*\/DNS$/{print $NF}')
    if [ -n "$setup_keys" ]; then
      for k in $setup_keys; do
        echo "  $k"
        "$SCUTIL" <<< "show $k" 2>/dev/null | sed 's/^/    /'
      done
    else
      echo "  (no Setup: DNS key - healthy)"
    fi

    echo
    echo "--- the same services in the ON-DISK persistent store ---"
    # A Setup: key in the live store does NOT mean it was written to disk.
    # ovpnagent writes straight into configd's dynamic store, so this file
    # stays empty while scutil shows an override - which is exactly why
    # networksetup (which reads this file) called the broken state clean for a
    # month. An override here but not above is a real manual setting; above but
    # not here is a VPN client holding the resolver hostage in memory only.
    /usr/bin/plutil -extract NetworkServices xml1 -o - \
      /Library/Preferences/SystemConfiguration/preferences.plist 2>/dev/null \
      | /usr/bin/python3 -c '
import plistlib, sys
try:
    d = plistlib.loads(sys.stdin.buffer.read())
except Exception as e:
    print("    (unreadable: %s)" % e); raise SystemExit
for k, v in sorted(d.items(), key=lambda kv: str(kv[1].get("UserDefinedName"))):
    print("    %-22s %s" % (v.get("UserDefinedName"), v.get("DNS")))
' 2>/dev/null || echo "    (could not read preferences.plist)"

    echo
    echo "--- manually-configured DNS per service ---"
    # "There aren't any DNS Servers set" is the healthy answer: DHCP is in use.
    "$NETWORKSETUP" -listallnetworkservices 2>/dev/null | tail -n +2 | while read -r s; do
      printf '  %-28s %s\n' "$s" "$("$NETWORKSETUP" -getdnsservers "$s" 2>/dev/null | tr '\n' ' ')"
    done

    echo
    echo "--- DHCP is offering ---"
    "$IPCONFIG" getpacket "$iface" 2>/dev/null \
      | grep -iE "domain_name|router|server_identifier" | sed 's/^/  /' \
      || echo "  (no lease seen)"

    echo
    echo "--- reachability of every resolver actually configured ---"
    # An off-LAN entry shows up here as UNREACHABLE, which is what turns
    # "DNS is broken" into "DNS is pointed at something that cannot answer".
    "$SCUTIL" --dns 2>/dev/null | awk '/nameserver\[/{print $3}' | sort -u | while read -r s; do
      case "$s" in *:*) continue ;; esac   # skip IPv6
      printf '  %-18s ' "$s"
      "$PING" -c1 -W1500 "$s" >/dev/null 2>&1 && echo "reachable" || echo "UNREACHABLE"
    done

    echo
    echo "--- tailscale DNS ---"
    TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
    [ -x "$TS" ] || TS=$(command -v tailscale 2>/dev/null)
    if [ -n "${TS:-}" ] && [ -x "$TS" ]; then
      "$TS" dns status 2>&1 | grep -iE "Tailscale DNS:|MagicDNS:|^  - |Resolvers|Search" | sed 's/^/  /'
    else
      echo "  (tailscale CLI not found)"
    fi

    echo
    echo "--- VPN clients / tunnel interfaces (they push DNS into State: AND Setup:) ---"
    "$SCUTIL" --nc list 2>/dev/null | sed 's/^/  /' || echo "  (no configured VPN services)"
    # Whole command line, not $11 $12. Truncating it cost time on 2026-09-30:
    # the snapshots recorded "openvpn --config" and so could not say *which*
    # config, nor whether that process was OpenVPN Connect's own core or the
    # separate homebrew CLI that is also installed here.
    # Match on the executable path ($2) only - matching anywhere in the line
    # makes any grep of this log report itself as a running VPN client.
    ps -Ao pid,command 2>/dev/null \
      | awk 'NR>1 && tolower($2) ~ /openvpn|ovpnagent|ovpnhelper|tunnelblick|viscosity|anyconnect|globalprotect|zscaler|wireguard|nordvpn|expressvpn/ {print "  running: " $0}'

    "$IFCONFIG" 2>/dev/null \
      | awk '/^(utun|ppp|ipsec|tun)[0-9]*:/{i=$1} /inet /{if(i){print "  " i " " $2; i=""}}'
    echo
    echo "--- ovpnagent's own DNS bookkeeping (it logs every write it makes) ---"
    # /var/log/ovpnagent.log prints each dynamic-store dictionary it touches as
    # "*** DSDict <key>" followed by ORIG/MODIFIED, so it names the writer in
    # its own words. A write with no matching restore is this bug; a session
    # whose last line is "has exited, destroy tun" with no restore after it is
    # the crash path that strands the servers: measured 2026-09-30 over five
    # months of this log, 32 of 48 such exits had no restore anywhere near them,
    # against 441 of 444 clean disconnects that did restore.
    OVPNLOG=/var/log/ovpnagent.log
    if [ -r "$OVPNLOG" ]; then
      echo "  last written: $(/usr/bin/stat -f '%Sm' "$OVPNLOG" 2>/dev/null)"
      grep -nE 'DSDict Setup:.*/DNS|has exited, destroy tun|INSTANCE STOP' "$OVPNLOG" 2>/dev/null \
        | tail -6 | sed 's/^/  /'
    else
      echo "  ($OVPNLOG not readable)"
    fi

    echo
    echo "--- /etc/resolv.conf ---"
    sed 's/^/  /' /etc/resolv.conf 2>/dev/null || echo "  (absent)"

    echo
    echo "--- full scutil --dns ---"
    "$SCUTIL" --dns 2>/dev/null | sed 's/^/  /'
    echo
  } >> "$LOG"
}

note() { printf '\n### %s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*" >> "$LOG"; }

rotate() {
  [ -f "$LOG" ] || return 0
  size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  [ "$size" -gt "$MAXSIZE" ] && mv "$LOG" "$LOG.1"
  return 0
}

# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------
health() {
  # Same lesson as watch-peer-dns.sh: an empty log must not be ambiguous
  # between "nothing changed" and "the recorder died three weeks ago".
  echo "recorder:  $STATE_DIR"
  if [ -f "$POLLED" ]; then
    now=$(date +%s); then_=$(cat "$POLLED" 2>/dev/null || echo 0)
    age=$(( now - then_ ))
    if [ "$age" -lt $(( INTERVAL * 3 )) ]; then
      echo "state:     ALIVE - last polled ${age}s ago"
    else
      echo "state:     STALE - last polled ${age}s ago (expected every ${INTERVAL}s)"
      echo "           so any change since then went unrecorded; check:"
      echo "           launchctl list | grep dns-recorder"
    fi
  else
    echo "state:     NEVER RAN - no poll has completed yet"
  fi
  if [ -f "$LOG" ]; then
    echo "changes:   $(grep -c '^SNAPSHOT' "$LOG" 2>/dev/null) recorded in $LOG"
  else
    echo "changes:   no log yet at $LOG"
  fi
}

timeline() {
  [ -f "$LOG" ] || { echo "no snapshots recorded yet"; return 0; }
  awk '
    /^SNAPSHOT/ { ts = $2 " " $3; next }
    /^reason:/  { sub(/^reason: */, ""); why = $0; next }
    /^--- WHO owns/ { owners = 1; buf = ""; next }
    owners && /^ *$/ { next }
    owners && /^---/ {
      owners = 0
      printf "%s  %s\n", ts, why
      printf "%s\n", buf
      next
    }
    owners { buf = buf $0 "\n" }
  ' "$LOG"
}

# ---------------------------------------------------------------------------
main() {
  mkdir -p "$STATE_DIR"
  case "${1:-}" in
    --show)
      health; echo
      n="${2:-1}"
      [ -f "$LOG" ] || { echo "(no snapshots yet)"; exit 0; }
      # Print the last N snapshots by counting headers from the end.
      awk -v n="$n" '
        /^===================================================================$/ && seen { blocks++ }
        /^SNAPSHOT/ { seen = 1 }
        { line[NR] = $0 }
        END {
          c = 0
          for (i = NR; i > 0; i--) if (line[i] ~ /^SNAPSHOT/) { c++; if (c == n) { start = i - 1; break } }
          if (!start) start = 1
          for (i = start; i <= NR; i++) print line[i]
        }' "$LOG"
      ;;
    --timeline) health; echo; timeline ;;
    --once)     rotate; snapshot "forced with --once"; cheap_state > "$LAST"; echo "snapshot written to $LOG" ;;
    "")
      note "recorder started (pid $$, polling every ${INTERVAL}s)"
      if [ ! -f "$LAST" ]; then
        cheap_state > "$LAST"
        snapshot "baseline - first run, nothing to compare against yet"
      fi
      while :; do
        cheap_state > "$LAST.new"
        if ! cmp -s "$LAST" "$LAST.new"; then
          mv "$LAST.new" "$LAST"
          rotate
          snapshot "resolver configuration CHANGED"
        else
          rm -f "$LAST.new"
        fi
        date +%s > "$POLLED"
        sleep "$INTERVAL"
      done
      ;;
    *) echo "usage: $0 [--once | --show [N] | --timeline]" >&2; exit 1 ;;
  esac
}

main "$@"
