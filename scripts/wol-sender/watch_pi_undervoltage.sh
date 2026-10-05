#!/usr/bin/env bash
# Temporary watch on the wol Pi's power after the swap to the official 5.1V
# 2.5A supply (2026-10-05; PROJECTS.md "wol Pi under-voltage"). Run from xero's
# crontab every 15min: logs vcgencmd get_throttled and the boot's kernel
# under-voltage count, and pushes one ntfy alert per Pi boot the first time
# under-voltage appears. Remove the cron line once a few days including
# nights of white noise stay at 0x0.
#   bit 0  = under-voltage now        bit 16 = under-voltage since boot
#   bit 2  = throttled now            bit 18 = throttled since boot
set -u
cd "$(dirname "$0")/../.."
PI=pramod@192.168.1.124
STATE=.pi_undervoltage_alerted   # holds the Pi boot time already alerted for

out=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$PI" \
  'echo "$(vcgencmd get_throttled | cut -d= -f2) $(uptime -s | tr " " T) $(journalctl -k -b --no-pager 2>/dev/null | grep -ci under-voltage)"' 2>&1)
if [ $? -ne 0 ]; then
  echo "$(date -Is) unreachable: $out"
  exit 0
fi
read -r flags boot uv_count <<<"$out"
echo "$(date -Is) throttled=$flags boot=$boot kernel_undervoltage_lines=$uv_count"

if (( flags & 0x10001 )) || [ "${uv_count:-0}" -gt 0 ]; then
  if [ "$(cat "$STATE" 2>/dev/null)" != "$boot" ]; then
    set -a; . ./.env.ntfy; set +a
    . tools/notify/push_ntfy.sh
    push_ntfy "wol Pi under-voltage on the new 5.1V supply" \
      "get_throttled=$flags, $uv_count kernel under-voltage lines since boot $boot. The official supply did not fix it - check the cable and the Pi's load (fan, USB)." 4 "zap,warning"
    echo "$boot" > "$STATE"
    echo "$(date -Is) alert sent"
  fi
fi
