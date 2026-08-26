#!/usr/bin/env bash
# Run this ON XERO to append the two toggle-switch -> white-noise automations
# to HOMEASSISTANT_CONFIG/automations.yaml. That file is root-owned (HA's
# container writes it as root) and gitignored (backed up separately via
# Dropbox/rclone, not git) - this appends via sudo tee rather than needing
# ownership changed, and deliberately doesn't embed the rest of the file's
# content here, so this script itself stays clean of automations.yaml's data.
set -euo pipefail

TARGET="$(dirname "$0")/../HOMEASSISTANT_CONFIG/automations.yaml"

if grep -q "^- id: toggle1_white_noise_on$" "$TARGET" 2>/dev/null; then
  echo "Already applied - toggle1_white_noise_on found in $TARGET. Skipping."
  exit 0
fi

sudo tee -a "$TARGET" > /dev/null <<'EOF'
- id: toggle1_white_noise_on
  alias: White noise on (toggle switch)
  description: Physical GPIO toggle switch on the wol-sender Pi turns on white noise. Edge-triggered - only fires on the switch's own transition, so scenes/dashboard controls of switch.white_noise are untouched unless the switch is also flipped.
  triggers:
  - trigger: state
    entity_id: binary_sensor.toggle_switch_1
    to: 'on'
  conditions: []
  actions:
  - action: switch.turn_on
    target:
      entity_id: switch.white_noise
  mode: single
- id: toggle1_white_noise_off
  alias: White noise off (toggle switch)
  description: Physical GPIO toggle switch on the wol-sender Pi turns off white noise. Edge-triggered - only fires on the switch's own transition, so scenes/dashboard controls of switch.white_noise are untouched unless the switch is also flipped.
  triggers:
  - trigger: state
    entity_id: binary_sensor.toggle_switch_1
    to: 'off'
  conditions: []
  actions:
  - action: switch.turn_off
    target:
      entity_id: switch.white_noise
  mode: single
EOF

echo "Appended to $TARGET"
echo "Now reload automations in HA: Settings -> Automations & Scenes -> (top-right menu) -> Reload Automations"
