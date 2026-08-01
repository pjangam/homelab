#!/bin/bash
# One-off: install the updated automations.yaml (adds the white-noise
# night auto-off automation) - automations.yaml is owned by root since HA
# runs privileged, so this needs sudo. Backs up the current file first.
set -eu

sudo cp /home/pramod/code/homelab/HOMEASSISTANT_CONFIG/automations.yaml \
        /home/pramod/code/homelab/HOMEASSISTANT_CONFIG/automations.yaml.bak

sudo cp /tmp/claude-1000/-home-pramod-code-homelab/84a2f148-80ea-4db8-bbe8-9c194f7c81bc/scratchpad/automations.yaml.new \
        /home/pramod/code/homelab/HOMEASSISTANT_CONFIG/automations.yaml

echo "Done - automations.yaml updated, backup at automations.yaml.bak"
