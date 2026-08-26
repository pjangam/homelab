#!/usr/bin/env bash
# Run this ON XERO to append the two scene-button automations (oju
# sleep/awake) to HOMEASSISTANT_CONFIG/automations.yaml. That file is
# root-owned (HA's container writes it as root) and gitignored (backed up
# separately via Dropbox/rclone, not git) - this appends via sudo tee rather
# than needing ownership changed, and deliberately doesn't embed the rest of
# the file's content here, so this script itself stays clean of
# automations.yaml's data.
set -euo pipefail

TARGET="$(dirname "$0")/../HOMEASSISTANT_CONFIG/automations.yaml"

if grep -q "^- id: scene_button_oju_sleep$" "$TARGET" 2>/dev/null; then
  echo "Already applied - scene_button_oju_sleep found in $TARGET. Skipping."
  exit 0
fi

sudo tee -a "$TARGET" > /dev/null <<'EOF'
- id: scene_button_oju_sleep
  alias: Oju sleeping (physical button)
  description: Momentary GPIO push button on the wol-sender Pi (scripts/scene-buttons-mqtt.py) fires the oju sleeping scene directly - no persisted state involved, so there's nothing for HA/MQTT to resync or override on reconnect.
  triggers:
  - trigger: mqtt
    topic: scene_buttons/oju_sleep/pressed
    payload: 'PRESS'
  conditions: []
  actions:
  - action: scene.turn_on
    target:
      entity_id: scene.ojaswi_sleeping
    data:
      transition: 30
  mode: single
- id: scene_button_oju_awake
  alias: Oju awake (physical button)
  description: Momentary GPIO push button on the wol-sender Pi (scripts/scene-buttons-mqtt.py) fires the oju awake scene directly - no persisted state involved, so there's nothing for HA/MQTT to resync or override on reconnect.
  triggers:
  - trigger: mqtt
    topic: scene_buttons/oju_awake/pressed
    payload: 'PRESS'
  conditions: []
  actions:
  - action: scene.turn_on
    target:
      entity_id: scene.ojaswi_awake
    data:
      transition: 30
  mode: single
EOF

echo "Appended to $TARGET"
echo "Now reload automations in HA: Settings -> Automations & Scenes -> (top-right menu) -> Reload Automations"
