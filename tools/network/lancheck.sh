#!/usr/bin/env bash
# Why is a file copy to xero slow? Measures the LAN path Mac -> xero, hop by
# hop, so you can tell a bad Wi-Fi association apart from a capped wired hop
# apart from a stalled transfer.
#
# Companion to speedcheck.sh, which measures the *WAN* line. Nothing in here
# leaves the house.
#
# Written 2026-09-29, when `scp` of a 1.2 GB zip to xero ran at ~1.4 MB/s and
# then stalled outright. Three separate things were true at once:
#   - the Mac was associated at 2.4 GHz / 802.11n / 20 MHz, -69 dBm, 57 Mbps,
#     with 62 ms average and 124 ms worst-case RTT to xero on the same LAN;
#   - xero's NIC does gigabit but the link partner (the WiFi range extender it
#     is cabled into - see new_machine_setup.sh) only advertises 100baseT, so
#     that hop is capped at 100 Mb/s and always will be;
#   - the extender's wireless backhaul shares the same congested 2.4 GHz air
#     as the Mac, so both ends of the copy compete for one radio.
# The Wi-Fi association is the only one of those that is cheap to fix: a 5 GHz
# SSID was visible at -63 dBm at the time.
#
# Usage: tools/network/lancheck.sh [host] [megabytes_per_direction]
#        defaults: 192.168.1.123 (xero), 32 MB
#
# Sized in bytes rather than seconds on purpose: macOS ships no `timeout`, and
# a byte-bounded transfer gives the same answer without coreutils.

set -u
HOST="${1:-192.168.1.123}"
MB="${2:-32}"

now()  { python3 -c 'import time; print(time.time())'; }
mbps() { awk -v b="$1" -v s="$2" 'BEGIN{if(s>0) printf "%.1f", b*8/s/1000000; else print "?"}'; }
mbs()  { awk -v b="$1" -v s="$2" 'BEGIN{if(s>0) printf "%.1f", b/s/1000000; else print "?"}'; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", b-a}'; }

echo "== This Mac's link =="
system_profiler SPAirPortDataType 2>/dev/null \
  | sed -n '/Current Network/,/^ *$/p' \
  | grep -iE "PHY Mode|Channel:|Signal|Transmit Rate" | head -4 | sed 's/^ */  /'
route -n get "$HOST" 2>/dev/null | grep -E "interface|gateway" | sed 's/^ */  /'
# A 5 GHz association is the cheap fix when the line above says 2GHz. macOS
# redacts SSIDs here without Location permission, so report signal only - the
# preferred-network list names the candidate.
best5=$(system_profiler SPAirPortDataType 2>/dev/null \
  | awk '/Channel: [0-9]+ \(5GHz/{c=1} c&&/Signal \/ Noise/{print $4; c=0}' \
  | sort -n | tail -1)
echo "  best 5 GHz signal in range: ${best5:--} dBm"
/usr/sbin/networksetup -listpreferredwirelessnetworks en0 2>/dev/null \
  | grep -iE "5g|5ghz" | head -3 | sed 's/^[[:space:]]*/    known 5 GHz SSID: /'

echo
echo "== RTT and jitter to $HOST (same LAN: expect <5 ms, low stddev) =="
ping -c 20 -i 0.3 "$HOST" 2>/dev/null | tail -2 | sed 's/^/  /'

echo
echo "== $HOST's own wired link =="
# Speed is what was negotiated; "Link partner advertised" is the *other* end's
# ceiling. If the partner tops out below the NIC, the cable's far end is the cap.
ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" '
  iface=$(ip -o route get 1.1.1.1 2>/dev/null | awk "{for(i=1;i<=NF;i++) if(\$i==\"dev\") print \$(i+1)}")
  echo "interface: ${iface:-unknown}"
  ethtool "$iface" 2>/dev/null | grep -E "^\s+(Speed|Duplex|Link detected):"
  # The partner is the far end of the cable. If its ceiling is below the NIC
  # Supported modes, the switch/extender port is the cap and no NIC change helps.
  ethtool "$iface" 2>/dev/null | awk "
    /Supported link modes/  { lbl=\"NIC supports\";     sub(/.*modes:[ \t]*/,\"\"); p=1 }
    /Link partner advertised link modes/ { lbl=\"far end supports\"; sub(/.*modes:[ \t]*/,\"\"); p=1 }
    /pause frame use/ { p=0 }
    p {
      gsub(/^[ \t]+/,\"\"); if (\$0 == \"\") next
      out[lbl] = (lbl in out ? out[lbl] \" \" : \"\") \$0
    }
    END { printf \"%-17s: %s\\n\", \"NIC supports\", out[\"NIC supports\"]
          printf \"%-17s: %s\\n\", \"far end supports\", out[\"far end supports\"] }
  "
' 2>/dev/null | sed 's/^[[:space:]]*/  /'

echo
echo "== Throughput over ssh (${MB} MB each way, /dev/zero to /dev/null) =="
# Deliberately not a file copy: no disk, no compression, no resume logic - just
# what the path carries. ssh's own cipher costs a few percent on modern CPUs.
t0=$(now)
dd if=/dev/zero bs=1m count="$MB" 2>/dev/null \
  | ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" 'cat > /dev/null' 2>/dev/null
t1=$(now)
ue=$(elapsed "$t0" "$t1"); ub=$((MB * 1048576))
printf '  %-28s %8s Mbps  (%s MB/s over %ss)\n' \
  "Mac -> $HOST (upload)" "$(mbps "$ub" "$ue")" "$(mbs "$ub" "$ue")" "$ue"

t0=$(now)
db=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" \
  "dd if=/dev/zero bs=1M count=$MB 2>/dev/null" 2>/dev/null | wc -c | tr -d ' ')
t1=$(now)
de=$(elapsed "$t0" "$t1")
printf '  %-28s %8s Mbps  (%s MB/s over %ss)\n' \
  "$HOST -> Mac (download)" "$(mbps "${db:-0}" "$de")" "$(mbs "${db:-0}" "$de")" "$de"

echo "== Loss while the path is loaded =="
# Idle pings on this LAN have looked clean while a copy crawled; load the path
# and the wireless hop shows its real behaviour.
idle=$(ping -c 12 -i 0.3 "$HOST" 2>/dev/null | awk -F'%' '/packet loss/{print $1}' | awk '{print $NF}')
ssh -o ConnectTimeout=5 -o BatchMode=yes "$HOST" \
  "dd if=/dev/zero bs=1M count=$((MB * 8)) 2>/dev/null" >/dev/null 2>&1 &
loadpid=$!
sleep 1
busy=$(ping -c 30 -i 0.3 "$HOST" 2>/dev/null | awk -F'%' '/packet loss/{print $1}' | awk '{print $NF}')
kill "$loadpid" 2>/dev/null; wait 2>/dev/null
printf '  %-28s idle %4s%% loss   loaded %4s%% loss\n' "$HOST" "${idle:-?}" "${busy:-?}"

echo
echo "Copying a big file? Use rsync, not scp - scp restarts from zero after a"
echo "stall, rsync resumes:  rsync -avP --append-verify FILE $HOST:~/Downloads/"
