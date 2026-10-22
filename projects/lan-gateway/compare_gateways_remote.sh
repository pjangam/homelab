#!/bin/bash
# Runs ON the device, as root, sent by compare_gateways.sh. Args: rounds url.
set -u
rounds=$1 url=$2
trap 'ip route replace default via 192.168.1.1; echo; echo "Left on the router (192.168.1.1)."' EXIT
for r in $(seq "$rounds"); do
  for gw in 192.168.1.1 192.168.1.123; do
    ip route replace default via "$gw"
    name=router; [ "$gw" = 192.168.1.123 ] && name=xero
    bps=$(curl -sS -m 60 -o /dev/null -w '%{speed_download}' "$url" 2>/dev/null || echo 0)
    ping -c 20 -i 0.2 -W 2 1.1.1.1 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | sort -n |
      awk -v r="$r" -v n="$name" -v bps="$bps" '{t[NR]=$1}
        END{c=NR; p50=c?t[int((c+1)/2)]:0; p95=c?t[int(c*0.95+0.999)]:0; mx=c?t[c]:0
            printf "round %d  %-6s  %5.1f Mbps   ping p50 %5.1f  p95 %5.1f  max %5.1f ms  (%d/20 replies)\n",
                   r, n, bps*8/1e6, p50, p95, mx, c}'
  done
done
