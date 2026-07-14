#!/bin/bash
set -e

HA_CONFIG="/home/pramod/code/homelab/HOMEASSISTANT_CONFIG"

# Add command_line switch to configuration.yaml
cat >> "$HA_CONFIG/configuration.yaml" << 'YAML'

command_line:
  - switch:
      name: White Noise
      unique_id: white_noise_switch
      command_on: "curl -s -X POST http://localhost:8765/white-noise/on"
      command_off: "curl -s -X POST http://localhost:8765/white-noise/off"
      command_state: "curl -s http://localhost:8765/white-noise/status"
      value_template: "{{ value_json.state == 'active' }}"
      icon: mdi:weather-windy
YAML

# Add white noise ON to sleeping scene
sed -i "/id: '1781541681051'/,/entities:/{/entities:/{n; s/^/    switch.white_noise:\n      state: 'on'\n/}}" "$HA_CONFIG/scenes.yaml"

# Add white noise OFF to awake scene
sed -i "/id: '1781576403960'/,/entities:/{/entities:/{n; s/^/    switch.white_noise:\n      state: 'off'\n/}}" "$HA_CONFIG/scenes.yaml"

echo "Done. Restart HA with: docker restart homeassistant"
