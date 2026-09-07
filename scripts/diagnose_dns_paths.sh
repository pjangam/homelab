#!/usr/bin/env bash
# Diagnose which resolver actually answers, and whether queries reach Pi-hole.
#
# Resolution succeeding proves nothing about *which* resolver did the work, so
# this sends uniquely-named marker queries down each path and then looks for
# them in Pi-hole's query log. FTL only flushes to its SQLite DB periodically,
# so the check waits for a flush before declaring a path dead.
set -u

PIHOLE_LAN=192.168.1.123
PIHOLE_TS=100.70.215.25
MAGICDNS=100.100.100.100
STAMP=$RANDOM-$$

marker() { echo "dnsprobe-$1-$STAMP.example.com"; }

send() { # send <server> <marker>
  dig +time=4 +tries=1 "@$2" "$1" >/dev/null 2>&1
}

echo "=== sending marker queries ==="
for path in lan:$PIHOLE_LAN ts:$PIHOLE_TS magic:$MAGICDNS; do
  name=${path%%:*}; srv=${path#*:}
  m=$(marker "$name")
  send "$m" "$srv"
  echo "  $name via $srv -> $m"
done

echo
echo "=== waiting 70s for FTL to flush to its database ==="
sleep 70

echo
echo "=== which markers reached Pi-hole ==="
docker exec pihole pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db \
  "select datetime(timestamp,'unixepoch','localtime'), client, domain
     from queries where domain like 'dnsprobe-%-$STAMP%'
     order by timestamp;" 2>&1

echo
echo "=== verdict ==="
for name in lan ts magic; do
  m=$(marker "$name")
  hit=$(docker exec pihole pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db \
    "select count(*) from queries where domain='$m';" 2>/dev/null)
  if [ "${hit:-0}" -gt 0 ]; then
    echo "  $name: REACHES Pi-hole"
  else
    echo "  $name: does NOT reach Pi-hole"
  fi
done
