#!/usr/bin/env bash
# Adds the "Spotifyd Connect Advertising" tile to the Homelab Health section
# of the storage-mode Stats dashboard, next to the existing spotifyd tiles.
#
# Home Assistant must be stopped for this: it holds the Lovelace storage
# config in memory and rewrites .storage on shutdown, so editing the file
# under a running HA gets silently reverted. Same stop/copy/restart pattern
# as the earlier Tailscale and power-watchdog dashboard edits.
#
# The .storage directory is owned by root (the HA container writes as root).
# Rather than requiring an interactive sudo password, the privileged edit is
# done inside a throwaway container running as root with .storage bind-mounted
# - the same image HA already uses, so nothing new is pulled. Reads from the
# host stay unprivileged.
#
# Idempotent - re-running when the tile is already present is a no-op.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
DASH="$REPO/HOMEASSISTANT_CONFIG/.storage/lovelace.dashboard_stats"
ENTITY="binary_sensor.homelab_healthcheck_homelab_spotifyd_connect_advertising"
ANCHOR="binary_sensor.homelab_healthcheck_homelab_spotifyd"

[ -f "$DASH" ] || { echo "dashboard file not found: $DASH" >&2; exit 1; }

if python3 -c "
import json,sys
d=json.load(open('$DASH'))
sys.exit(0 if '$ENTITY' in json.dumps(d) else 1)
"; then
  echo "Tile already present - nothing to do."
  exit 0
fi

echo "Stopping Home Assistant so it can't overwrite the dashboard on shutdown..."
docker stop homeassistant >/dev/null
# Restart HA on every exit path: a failure between here and the end would
# otherwise leave HA down, which is exactly the class of bug the vaultwarden
# backup guard was added for (see 2026-09-06 incident).
trap 'echo "Restarting Home Assistant..."; docker start homeassistant >/dev/null || true' EXIT

STORAGE_DIR="$(dirname "$DASH")"
BASE="$(basename "$DASH")"
IMAGE="$(docker inspect homeassistant --format '{{.Config.Image}}')"

docker run --rm -u 0:0 -v "$STORAGE_DIR:/s" -w /s \
  -e BASE="$BASE" -e ENTITY="$ENTITY" -e ANCHOR="$ANCHOR" \
  "$IMAGE" python3 -c '
import json, os, shutil, datetime
base, entity, anchor = os.environ["BASE"], os.environ["ENTITY"], os.environ["ANCHOR"]
shutil.copy2(base, f"{base}.bak.{datetime.datetime.now():%Y%m%d%H%M%S}")
d = json.load(open(base))
cards = d["data"]["config"]["views"][0]["sections"][0]["cards"]
idx = max(i for i, c in enumerate(cards)
          if c.get("entity", "").startswith(anchor)
          or c.get("entity", "") == "sensor.homelab_healthcheck_spotifyd_restarts_24h")
cards.insert(idx + 1, {"type": "tile", "entity": entity})
json.dump(d, open(base, "w"), indent=2)
print(f"Inserted tile at position {idx + 1}")
'


echo "Done."
