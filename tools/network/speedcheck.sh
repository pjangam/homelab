#!/usr/bin/env bash
# Compare domestic vs international throughput to tell "my line is slow" apart
# from "my ISP's international transit is congested".
#
# Written 2026-09-23, when fast.com showed 1.9 Mbps while an in-country
# Cloudflare PoP pulled ~38 Mbps. A router restart did nothing, because the
# problem was never the local link. Re-run this before and after talking to the
# ISP - the domestic/international gap is the whole argument.
#
# Usage: tools/network/speedcheck.sh [seconds_per_target]   (default 12)

set -u
CAP="${1:-12}"

mbps() { awk -v b="$1" 'BEGIN{printf "%.1f", b*8/1000000}'; }

row() {  # label url
  local label="$1" url="$2" speed
  speed=$(curl -sS -o /dev/null --max-time "$CAP" \
            -w '%{speed_download}' "$url" 2>/dev/null) || true
  speed=${speed:-0}
  printf '  %-34s %8s Mbps\n' "$label" "$(mbps "${speed%.*}")"
}

echo "== Link =="
system_profiler SPAirPortDataType 2>/dev/null \
  | sed -n '/Current Network/,/^ *$/p' \
  | grep -iE "PHY Mode|Channel|Signal|Transmit Rate" | head -4
route -n get default 2>/dev/null | grep -E "interface|gateway" | sed 's/^/ /'

echo
echo "== Where Cloudflare puts us =="
curl -sS --max-time 10 https://speed.cloudflare.com/cdn-cgi/trace 2>/dev/null \
  | grep -E "^(ip|colo|loc)=" | sed 's/^/  /'

echo
echo "== Throughput (${CAP}s per target) =="
row "domestic  (Cloudflare edge)"  "https://speed.cloudflare.com/__down?bytes=50000000"
row "intl US   (Hetzner Ashburn)"  "https://ash-speed.hetzner.com/100MB.bin"
row "intl DE   (Hetzner Falkenst)" "https://fsn1-speed.hetzner.com/100MB.bin"
row "intl SG   (Hetzner Singapore)" "https://sin-speed.hetzner.com/100MB.bin"

echo
echo "== DNS (fresh names, no cache) =="
for r in "$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')" 1.1.1.1; do
  [ -n "$r" ] || continue
  t=$(dig +tries=1 +time=5 "@$r" "x$RANDOM.example.com" A 2>/dev/null \
        | awk '/Query time/{print $4}')
  printf '  %-34s %8s ms\n' "resolver $r" "${t:-timeout}"
done
sys=$( { time -p dscacheutil -q host -a name "x$RANDOM.example.com" >/dev/null 2>&1; } 2>&1 \
       | awk '/^real/{printf "%.0f", $2*1000}')
printf '  %-34s %8s ms\n' "system resolver (mDNSResponder)" "${sys:-?}"

echo
echo "== Loss under load =="
# The decisive test, 2026-09-23: Airtel showed 0% loss idle and 12.5% loss on
# the international path *while downloading*. Loss only appears once the
# inbound pipe is actually loaded, which is why idle pings always looked clean
# and why "restart the router" never changed anything.
loadtest() {  # label host url
  local label="$1" host="$2" url="$3" idle busy
  idle=$(ping -c 12 -i 0.3 "$host" 2>/dev/null | awk -F'%' '/packet loss/{print $1}' | awk '{print $NF}')
  curl -sS -o /dev/null --max-time 20 "$url" & local pid=$!
  sleep 1
  busy=$(ping -c 30 -i 0.3 "$host" 2>/dev/null | awk -F'%' '/packet loss/{print $1}' | awk '{print $NF}')
  kill "$pid" 2>/dev/null; wait 2>/dev/null
  printf '  %-30s idle %4s%% loss   loaded %4s%% loss\n' "$label" "${idle:-?}" "${busy:-?}"
}
loadtest "domestic (CF edge)"  speed.cloudflare.com   "https://speed.cloudflare.com/__down?bytes=200000000"
loadtest "intl DE  (Hetzner)"  fsn1-speed.hetzner.com "https://fsn1-speed.hetzner.com/100MB.bin"

echo
echo "== Where the international leg starts =="
traceroute -q 2 -w 2 -m 8 fsn1-speed.hetzner.com 2>&1 | tail -6
