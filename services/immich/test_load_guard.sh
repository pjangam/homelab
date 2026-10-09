#!/usr/bin/env bash
# Exercises load_guard.sh with fake readings and a fake docker, so nothing
# real is stopped: each case feeds one limit past its threshold and checks
# that the guard trips, stops the immich_* containers ML-first and leaves
# the others alone.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

cat > "$t/docker" <<EOF
#!/usr/bin/env bash
case \$1 in
  ps)   printf 'immich_postgres\nimmich_machine_learning\nimmich_server\nimmich_redis\n' ;;
  stop) echo "\$2" >> "$t/stopped" ;;
esac
EOF
chmod +x "$t/docker"

fail=0
run_case() {  # name temp_c mem_kb busy(0/1) expect_trip
  local name=$1 temp=$2 mem=$3 busy=$4 expect=$5
  rm -f "$t/stopped" "$t/tripped"
  echo "$((temp * 1000))" > "$t/temp"
  echo "MemAvailable: $mem kB" > "$t/meminfo"
  echo "cpu  0 0 0 1000 0 0 0 0 0 0" > "$t/stat"
  # Advance /proc/stat between samples: all busy or all idle.
  ( n=0; while sleep 0.2; do n=$((n + 100))
      if [ "$busy" = 1 ]; then echo "cpu  $n 0 0 1000 0 0 0 0 0 0"
      else echo "cpu  0 0 0 $((1000 + n)) 0 0 0 0 0 0"; fi > "$t/stat.new"
      mv "$t/stat.new" "$t/stat"; done ) & local ticker=$!
  INTERVAL=1 TEMP_SAMPLES=2 MEM_SAMPLES=2 CPU_SAMPLES=2 NTFY_HEALTH_TOKEN= \
    TEMP_FILE=$t/temp MEMINFO=$t/meminfo STAT=$t/stat DOCKER=$t/docker \
    TRIP_FILE=$t/tripped HOME=$t timeout 4 "$here/load_guard.sh" > "$t/log" 2>&1
  kill $ticker 2>/dev/null; wait $ticker 2>/dev/null
  local got=no; [ -f "$t/tripped" ] && got=yes
  if [ "$got" != "$expect" ]; then
    echo "FAIL $name: tripped=$got, expected $expect"; cat "$t/log"; fail=1; return
  fi
  if [ "$expect" = yes ] && [ "$(head -1 "$t/stopped")" != immich_machine_learning ]; then
    echo "FAIL $name: ML was not stopped first"; cat "$t/stopped"; fail=1; return
  fi
  echo "ok   $name"
}

run_case "normal load"        70 20000000 0 no
run_case "hot CPU"            96 20000000 0 yes
run_case "low memory"         70 500000   0 yes
run_case "CPU pinned"         70 20000000 1 yes
exit $fail
