#!/usr/bin/env bash
# Run this ON XERO to swap the toggle-switch white-noise automations for the
# new momentary-push-button ones, in HOMEASSISTANT_CONFIG/automations.yaml.
# That file is root-owned (HA's container writes it as root) and gitignored
# (backed up separately via Dropbox/rclone, not git).
#
# The toggle switch on GPIO17 was physically replaced with two momentary
# push buttons (GPIO17 start, GPIO18 stop - see scripts/white-noise-buttons-mqtt.py),
# so the old toggle1_white_noise_on/off automations (triggered on
# binary_sensor.toggle_switch_1 state) are dead - that entity no longer
# exists. This removes them and adds two MQTT-trigger automations matching
# the scene-button shape instead.
set -euo pipefail

TARGET="$(dirname "$0")/../HOMEASSISTANT_CONFIG/automations.yaml"

if grep -q "^- id: white_noise_button_start$" "$TARGET" 2>/dev/null; then
  echo "Already applied - white_noise_button_start found in $TARGET. Skipping."
  exit 0
fi

if grep -q "^- id: toggle1_white_noise_on$" "$TARGET" 2>/dev/null; then
  sudo python3 - "$TARGET" <<'PYEOF'
import re
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

for automation_id in ("toggle1_white_noise_on", "toggle1_white_noise_off"):
    content = re.sub(
        rf"(?m)^- id: {automation_id}\n(?:  .*\n)*",
        "",
        content,
    )

with open(path, "w") as f:
    f.write(content)
PYEOF
  echo "Removed toggle1_white_noise_on/off from $TARGET"
fi

sudo tee -a "$TARGET" > /dev/null <<'EOF'
- id: white_noise_button_start
  alias: White noise on (physical button)
  description: Momentary GPIO push button on the wol-sender Pi (scripts/white-noise-buttons-mqtt.py) turns on white noise directly - no persisted state involved, so there's nothing for HA/MQTT to resync or override on reconnect.
  triggers:
  - trigger: mqtt
    topic: white_noise_buttons/start/pressed
    payload: 'PRESS'
  conditions: []
  actions:
  - action: switch.turn_on
    target:
      entity_id: switch.white_noise
  mode: single
- id: white_noise_button_stop
  alias: White noise off (physical button)
  description: Momentary GPIO push button on the wol-sender Pi (scripts/white-noise-buttons-mqtt.py) turns off white noise directly - no persisted state involved, so there's nothing for HA/MQTT to resync or override on reconnect.
  triggers:
  - trigger: mqtt
    topic: white_noise_buttons/stop/pressed
    payload: 'PRESS'
  conditions: []
  actions:
  - action: switch.turn_off
    target:
      entity_id: switch.white_noise
  mode: single
EOF

echo "Appended to $TARGET"
echo "Now reload automations in HA: Settings -> Automations & Scenes -> (top-right menu) -> Reload Automations"
