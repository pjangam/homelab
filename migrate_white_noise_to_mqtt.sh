#!/bin/bash
# One-time migration: command_line/HTTP white-noise switch -> MQTT switch.
# Requires sudo (loginctl + docker stop/start touch root-owned HA config files).
set -euo pipefail

HA_CONFIG="/home/pramod/code/homelab/HOMEASSISTANT_CONFIG"

# 1. Persist systemd --user services (white-noise, white-noise-mqtt) across
#    logout/reboot. Without this they die whenever the login session that
#    started them ends, and the HA switch silently stops responding.
sudo loginctl enable-linger pramod

# 2. Remove the old command_line switch block from configuration.yaml
#    (everything from the "command_line:" line to end of file).
sudo sed -i '/^command_line:/,$d' "$HA_CONFIG/configuration.yaml"

# 3. Drop stray white_noise entity_registry entries (old command_line entity +
#    a mis-shaped mqtt entity created during testing) so MQTT discovery
#    creates a clean switch.white_noise entity that scenes.yaml already
#    references.
docker stop homeassistant
sudo python3 - <<'PYEOF'
import json
path = "/home/pramod/code/homelab/HOMEASSISTANT_CONFIG/.storage/core.entity_registry"
d = json.load(open(path))
before = len(d["data"]["entities"])
d["data"]["entities"] = [
    e for e in d["data"]["entities"]
    if e.get("entity_id") not in ("switch.white_noise", "switch.white_noise_player_white_noise")
]
after = len(d["data"]["entities"])
print("removed", before - after, "entries")
json.dump(d, open(path, "w"), indent=2)
PYEOF
docker start homeassistant

echo "Done. Tail logs with: docker logs -f homeassistant"
