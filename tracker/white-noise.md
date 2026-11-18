# White noise: HTTP polling → MQTT + systemd linger fix
**Status:** Done

**Why:** the HA white-noise switch was unresponsive. Root cause was `Linger=no` - `white-noise-api.service` (a `systemd --user` unit) died every time the SSH session that started it ended, and HA's `curl` polling failed silently.
**Outcome:** replaced the HTTP API with an MQTT bridge (`projects/white-noise/white-noise-mqtt.py`, `uv run --script`) using HA discovery, and ran `loginctl enable-linger pramod` so `systemd --user` units survive logout/reboot. Confirmed fixed via a real logout test.
