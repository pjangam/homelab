#!/usr/bin/env bash
# Bring xero's Syncthing to the settled config (services/syncthing/README.md).
# Idempotent: safe to re-run after a rebuild, an upgrade or a hand edit in the GUI.
#
#   - fixes the config volume's ownership (a fresh named volume is root-owned)
#   - no global discovery, no relays, no UPnP, no usage/crash reporting
#   - GUI login from SYNCTHING_GUI_PASSWORD in .env (generated if missing)
#   - the "documents" folder on /datapool/documents, staggered versioning
#
# Devices are NOT added here: pairing needs each device's ID, done in the GUI
# (README "Adding a device").
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="$REPO/.env"
API="http://127.0.0.1:8384/rest"
VERSION_DAYS=90

cd "$REPO"

# 1. Volume ownership + container up.
docker compose up -d syncthing >/dev/null
docker run --rm -v homelab_syncthing-config:/c --entrypoint chown \
    "$(docker inspect -f '{{.Config.Image}}' syncthing)" -R 1000:1000 /c

# 2. GUI password lives in .env (gitignored). Generate one the first time.
if ! grep -q '^SYNCTHING_GUI_PASSWORD=' "$ENV_FILE"; then
    printf 'SYNCTHING_GUI_PASSWORD=%s\n' "$(openssl rand -base64 18 | tr -d '/+=')" >> "$ENV_FILE"
    echo "Generated SYNCTHING_GUI_PASSWORD in .env - copy it into Vaultwarden."
fi
PASSWORD="$(grep '^SYNCTHING_GUI_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"

# 3. Wait for the API, then read its key from the config.
for _ in $(seq 30); do
    curl -s -o /dev/null "$API/noauth/health" && break
    sleep 1
done
KEY="$(docker exec syncthing sh -c 'sed -n "s:.*<apikey>\(.*\)</apikey>.*:\1:p" /var/syncthing/config/config.xml')"
api() { curl -fsS -H "X-API-Key: $KEY" -H 'Content-Type: application/json' "$@"; }

# 4. Options: never touch the public internet.
api -X PATCH "$API/config/options" -d '{
  "globalAnnounceEnabled": false,
  "relaysEnabled": false,
  "natEnabled": false,
  "localAnnounceEnabled": true,
  "listenAddresses": ["tcp://:22000", "quic://:22000"],
  "urAccepted": -1,
  "crashReportingEnabled": false,
  "autoUpgradeIntervalH": 0,
  "startBrowser": false
}' >/dev/null

# 5. GUI: login required. Caddy forwards Host xero.<tailnet>, so skip the
#    host check (the GUI itself only listens on 127.0.0.1).
api -X PATCH "$API/config/gui" -d "$(python3 -c '
import json, sys
print(json.dumps({"user": "pramod", "password": sys.argv[1], "insecureSkipHostcheck": True}))
' "$PASSWORD")" >/dev/null

# 6. The documents folder. PUT replaces it wholesale, devices included, so
#    keep whichever devices are already shared with it.
DEVICES="$(api "$API/config/folders/documents" 2>/dev/null | python3 -c '
import json, sys
print(json.dumps(json.load(sys.stdin).get("devices", [])))' 2>/dev/null || echo '[]')"
api -X PUT "$API/config/folders/documents" -d "$(python3 - "$DEVICES" "$VERSION_DAYS" <<'EOF'
import json, sys
devices, days = json.loads(sys.argv[1]), int(sys.argv[2])
print(json.dumps({
    "id": "documents",
    "label": "Documents",
    "path": "/var/syncthing/documents",
    "type": "sendreceive",
    "fsWatcherEnabled": True,
    "rescanIntervalS": 3600,
    "devices": devices,
    "versioning": {
        "type": "staggered",
        "params": {"maxAge": str(days * 86400), "cleanInterval": "3600"},
        "cleanupIntervalS": 3600,
    },
}))
EOF
)" >/dev/null

# 7. Ignore OS clutter that Macs/Windows drop over SMB; (?d) lets Syncthing
#    delete it if it blocks a directory removal.
cat > /datapool/documents/.stignore <<'EOF'
// services/syncthing/configure.sh writes this file - edit it there.
(?d).DS_Store
(?d)._*
(?d)Thumbs.db
(?d)desktop.ini
EOF

echo "Syncthing configured. Device ID:"
api "$API/system/status" | python3 -c 'import json,sys; print(json.load(sys.stdin)["myID"])'
