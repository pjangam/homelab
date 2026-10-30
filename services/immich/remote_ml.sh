#!/usr/bin/env bash
# Points xero's Immich at a remote machine-learning container (the 2019
# MacBook, see remote_ml_mac.sh) ahead of its own, or back to its own only.
# Immich tries the URLs in order and skips one that fails its availability
# check (every 30s), so xero's ML stays as the fallback while the Mac sleeps.
#
#   services/immich/remote_ml.sh on [URL]   # default: the MacBook over Tailscale
#   services/immich/remote_ml.sh off
#   services/immich/remote_ml.sh status
#
# `on` also raises face detection / smart search concurrency to REMOTE_CONCURRENCY
# (the Mac has 6 threads for it); `off` puts it back to 2. A running
# ml_backlog.sh keeps going either way - it sets concurrency only when it starts.
set -euo pipefail

LOCAL=http://immich-machine-learning:3003
MAC=http://100.99.217.113:3003   # 2019 MacBook's Tailscale address (docs/hardware.md)
REMOTE_CONCURRENCY=${REMOTE_CONCURRENCY:-6}
API=${API:-http://localhost:2283/api}

cd "$(dirname "$0")/../.." || exit 1
: "${IMMICH_API_KEY:=$(sed -n 's/^IMMICH_API_KEY=//p' .env)}"
[[ -n $IMMICH_API_KEY ]] || { echo "IMMICH_API_KEY not set and not in .env" >&2; exit 1; }
api() { curl -sf -H "x-api-key: $IMMICH_API_KEY" -H 'Content-Type: application/json' "$@"; }
ping_from_server() { docker exec immich_server curl -s -m 3 "$1/ping" 2>/dev/null; }

# set_config CONCURRENCY URL...
set_config() {
  api "$API/system-config" | python3 -c '
import json, sys
c = json.load(sys.stdin)
c["machineLearning"]["urls"] = sys.argv[2:]
for q in ("faceDetection", "smartSearch"):
    c["job"][q]["concurrency"] = int(sys.argv[1])
print(json.dumps(c))' "$@" | api -X PUT "$API/system-config" -d @- >/dev/null
}

case "${1:-status}" in
  on)
    url=${2:-$MAC}
    [ "$(ping_from_server "$url")" = pong ] \
      || { echo "$url does not answer from immich_server - is remote_ml_mac.sh running on the Mac?" >&2; exit 1; }
    set_config "$REMOTE_CONCURRENCY" "$url" "$LOCAL"
    echo "ML: $url first, $LOCAL fallback; concurrency $REMOTE_CONCURRENCY" ;;
  off)
    set_config 2 "$LOCAL"
    echo "ML: $LOCAL only; concurrency 2" ;;
  status)
    api "$API/system-config" | python3 -c '
import json, sys
c = json.load(sys.stdin)
print("urls:", c["machineLearning"]["urls"])
print("concurrency:", {q: c["job"][q]["concurrency"] for q in ("faceDetection", "smartSearch")})'
    for u in $(api "$API/system-config" | python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)["machineLearning"]["urls"]))'); do
      echo "$u: $(ping_from_server "$u" || true)"
    done ;;
  *) echo "usage: $0 on [URL] | off | status" >&2; exit 1 ;;
esac
