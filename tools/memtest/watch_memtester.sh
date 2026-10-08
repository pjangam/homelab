#!/bin/bash
# Watch a memtester run on xero from another machine: once a minute, print the
# CPU package temperature, the peak so far, how many memtester processes are
# left and the FAILURE count in ~/memtester-[1-4].log. Stops when they have
# all finished, at the first failure, or at 95°C (it does not kill memtester -
# that needs sudo on xero: `sudo pkill memtester`).
#   tools/memtest/watch_memtester.sh [ssh-target]   # default pramod@xero
set -uo pipefail
target=${1:-pramod@xero}
peak=0
while true; do
  read -r temp running failures < <(ssh "$target" '
    echo $(( $(cat /sys/class/thermal/thermal_zone1/temp) / 1000 )) \
         $(pgrep -c memtester) \
         $(cat ~/memtester-[1-4].log 2>/dev/null | grep -a -c FAILURE)')
  [ "$temp" -gt "$peak" ] && peak=$temp
  echo "$(date +%H:%M) temp=${temp}°C peak=${peak}°C running=$running failures=$failures"
  if [ "$failures" -gt 0 ]; then echo "STOP: memory errors found"; break; fi
  if [ "$running" -eq 0 ]; then echo "DONE: all memtester runs finished"; break; fi
  if [ "$temp" -ge 95 ]; then echo "STOP: 95°C reached - consider sudo pkill memtester"; break; fi
  sleep 60
done
