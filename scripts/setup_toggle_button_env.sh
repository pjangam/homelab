#!/usr/bin/env bash
# Run this ON THE PI (wol-sender) to create ~/toggle-button-mqtt.env.
# Prompts interactively so the MQTT password never has to be pasted into a
# heredoc (copy-paste of quoted heredocs was mangling the previous approach).
set -euo pipefail

ENV_FILE="$HOME/toggle-button-mqtt.env"

read -rp "MQTT username [homelab]: " mqtt_user
mqtt_user="${mqtt_user:-homelab}"

read -rsp "MQTT password (from Vaultwarden): " mqtt_pass
echo

cat > "$ENV_FILE" <<EOF
MQTT_USERNAME=$mqtt_user
MQTT_PASSWORD=$mqtt_pass
EOF
chmod 600 "$ENV_FILE"

echo "Wrote $ENV_FILE (permissions: $(stat -c '%a' "$ENV_FILE"))"
