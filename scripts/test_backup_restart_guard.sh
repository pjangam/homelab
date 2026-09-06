#!/usr/bin/env bash
# Verifies the restart guard added to cron/backup_vaultwarden.sh on 2026-09-06.
#
# The guard exists because a stop/start pair around a backup is only safe if the
# start is guaranteed. Under `set -euo pipefail` an unguarded script exits on the
# first failure with the container still stopped, and since `docker stop` also
# sets Docker's HasBeenManuallyStopped flag, `restart: unless-stopped` then keeps
# it down through the next reboot too - that's how caddy went missing on
# 2026-09-06 (see incidents/2026-09-06-caddy-not-restarting-after-reboot.md).
#
# This tests the PATTERN against real Docker on a throwaway container rather than
# running the real backup (which stops the live vaultwarden, writes a GPG archive
# and uploads to the rclone remote - not something a test should do). What has to
# hold is the part that's easy to get wrong: the trap must fire on the failure
# path, and it must leave the manually-stopped flag clear.
#
# Run: ./scripts/test_backup_restart_guard.sh
set -uo pipefail
cd "$(dirname "$0")/.."

NAME=backup-guard-test
failures=0
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

flag() {  # prints True/False - Docker's internal manually-stopped bit
  local cid
  cid=$(docker inspect "$NAME" --format '{{.Id}}' 2>/dev/null) || { echo "ERR"; return; }
  docker run --rm -v /var/lib/docker/containers:/c:ro alpine \
    cat "/c/$cid/config.v2.json" 2>/dev/null |
    python3 -c "import json,sys; print(json.load(sys.stdin).get('HasBeenManuallyStopped'))"
}

check() {  # $1 = description, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1"; echo "      expected '$2', got '$3'"; failures=$((failures+1))
  fi
}

fresh_container() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" --restart unless-stopped alpine sleep 300 >/dev/null
}

# Guard against a false pass: if the fixture can't even start, every assertion
# below would compare two error strings and could look like agreement.
fresh_container
[ "$(docker inspect "$NAME" --format '{{.State.Running}}')" = "true" ] || {
  echo "FIXTURE ERROR: could not start $NAME"; exit 2; }

# 1. The failure path is the whole point: a mid-script error must still restart.
fresh_container
(
  set -euo pipefail
  trap 'docker start "$NAME" >/dev/null 2>&1 || true' EXIT
  docker stop "$NAME" >/dev/null
  false                      # stand-in for tar/gpg blowing up
  echo "UNREACHABLE"
) >/dev/null 2>&1
sleep 1
check "container is running again after a mid-script failure" \
      "true" "$(docker inspect "$NAME" --format '{{.State.Running}}')"
check "manually-stopped flag is clear after the guarded failure" \
      "False" "$(flag)"

# 2. The success path must not be broken by the trap double-starting.
fresh_container
(
  set -euo pipefail
  trap 'docker start "$NAME" >/dev/null 2>&1 || true' EXIT
  docker stop "$NAME" >/dev/null
  true                       # stand-in for a backup that worked
  docker start "$NAME" >/dev/null
) >/dev/null 2>&1
sleep 1
check "container is running after a successful run" \
      "true" "$(docker inspect "$NAME" --format '{{.State.Running}}')"
check "manually-stopped flag is clear after a successful run" \
      "False" "$(flag)"

# 3. The regression this guards against - unguarded, the container stays down
#    AND stays flagged, which is what survives a reboot.
fresh_container
(
  set -euo pipefail
  docker stop "$NAME" >/dev/null
  false
) >/dev/null 2>&1
sleep 1
check "unguarded failure leaves the container stopped (regression baseline)" \
      "false" "$(docker inspect "$NAME" --format '{{.State.Running}}')"
check "unguarded failure leaves it flagged manually-stopped (regression baseline)" \
      "True" "$(flag)"

echo; echo "FAILURES: $failures"
exit $((failures > 0))
