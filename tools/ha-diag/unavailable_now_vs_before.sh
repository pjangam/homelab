#!/bin/bash
# Lists every Home Assistant entity that is unavailable right now, next to the
# states it had in an earlier window - so after a restart or outage you can
# tell what is newly broken from what was already dead (decommissioned Tinxy
# devices, a dishwasher that is switched off). Run on xero:
#   tools/ha-diag/unavailable_now_vs_before.sh                 # vs 24h-12h ago
#   tools/ha-diag/unavailable_now_vs_before.sh 2026-10-07T00:00:00Z 2026-10-08T05:00:00Z
# Output: "NEW" when the entity had a real state in that window, else "was".
set -uo pipefail
cd "$(dirname "$0")/../.."
set -a; source .env.healthcheck; set +a
start=${1:-$(date -u -d "-24 hours" +%Y-%m-%dT%H:%M:%SZ)}
end=${2:-$(date -u -d "-12 hours" +%Y-%m-%dT%H:%M:%SZ)}
auth="Authorization: Bearer $HA_TOKEN"

ids=$(curl -s -H "$auth" http://localhost:8123/api/states \
  | jq -r '[.[] | select(.state == "unavailable") | .entity_id] | join(",")')
[ -z "$ids" ] && { echo "nothing unavailable"; exit 0; }

curl -s --max-time 60 -H "$auth" \
  "http://localhost:8123/api/history/period/$start?end_time=$end&filter_entity_id=$ids&minimal_response&no_attributes" \
  | jq -r --arg ids "$ids" '
      (map({key: .[0].entity_id, value: ([.[].state] | unique)}) | from_entries) as $seen
      | $ids | split(",")[]
      | ($seen[.] // ["(no history)"]) as $s
      | (if ($s - ["unavailable", "unknown", "(no history)"]) | length > 0 then "NEW" else "was" end)
        + "\t" + . + "\t" + ($s | join(","))' \
  | sort
