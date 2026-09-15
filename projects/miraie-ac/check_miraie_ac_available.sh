#!/usr/bin/env bash
# Is the MirAIe (Panasonic) AC actually usable from Home Assistant?
#
# This asks the end-state question - what does HA hold for the climate
# entity - rather than anything about the bridge, because on 2026-09-11 the
# bridge was green through two separate outages totalling nearly two hours
# and the entity was unusable the whole time:
#
#   18:17-19:36  the indoor unit went silent to the MirAIe cloud. Both broker
#                connections stayed ESTABLISHED, DNS resolved, the container
#                was `Up (healthy)`, and three `docker restart node-red` in a
#                row reported success while changing nothing.
#   21:05-21:42  HA restarted (for unrelated spotifyd work). The node
#                publishes the unit's availability with retain=false, so a
#                fresh HA holds no availability value and pins the entity
#                `unavailable` no matter how much state arrives.
#
# Two unrelated root causes, one symptom, and nothing was watching the
# symptom. Both are caught here for the same reason the spotifyd
# advertisement check exists: watch the thing you actually depend on, and it
# catches whatever breaks it next.
#
# Reads HA's API rather than the recorder DB so it sees live state with no
# WAL lag - same approach and token as verify_healthcheck_entities.sh.
#
# Exit codes are three-way, matching check_spotifyd_advertising.sh:
#   0 - the entity holds a real state (including `off`) - healthy
#   1 - `unavailable`/`unknown`, or HA has no such entity at all - the fault
#   2 - can't tell: no HA_TOKEN, no curl, or HA did not answer its API. A
#       caller must not alert on this. HA being down is already covered by
#       the container check, and blaming the AC for a dead HA points at the
#       wrong thing.
#
# Prints a one-line explanation on fault; silent on healthy.
set -uo pipefail

HA_URL="${HA_URL:-http://localhost:8123}"
ENTITY="${MIRAIE_AC_ENTITY:-climate.panasonic_ac_panasonic_ac}"

[ -n "${HA_TOKEN:-}" ] || { echo "HA_TOKEN not set - cannot check the AC entity" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl missing" >&2; exit 2; }

body="$(curl -s --max-time 10 -o - -w '\n%{http_code}' \
        -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/states/$ENTITY" 2>/dev/null)"
code="$(printf '%s' "$body" | tail -1)"
json="$(printf '%s' "$body" | sed '$d')"

case "$code" in
  200) ;;
  404)
    # The entity is gone entirely, not merely unavailable - this is the
    # "no longer being provided by the mqtt integration" shape, which happens
    # because the AC's discovery config is published retain=false.
    echo "Home Assistant has no entity $ENTITY at all - MQTT discovery for the AC is not registered"
    exit 1
    ;;
  # curl reports 000 when it never got a response at all (refused, timed
  # out, no route) - that is "HA is not answering", not a status code.
  000|"")
    echo "Home Assistant did not answer its API - cannot check the AC" >&2
    exit 2
    ;;
  *)
    echo "Home Assistant returned HTTP $code for $ENTITY - cannot check the AC" >&2
    exit 2
    ;;
esac

state="$(printf '%s' "$json" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('state', ''))
except Exception:
    print('')
" 2>/dev/null)"

case "$state" in
  "")
    echo "Could not read a state for $ENTITY from Home Assistant" >&2
    exit 2
    ;;
  unavailable|unknown)
    echo "$state"
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
