# 2026-08-25 (found) / 2026-08-31 (recurred): MQTT reconnect-loop race flapping HA switches unavailable

**Symptom:** the HA white-noise switch (`switch.white_noise`) intermittently flickered "unavailable" every ~5 seconds. Presses/automation calls made during one of those "offline" blips were silently dropped. When the same bug first appeared (2026-08-25, in a different bridge script), the visible symptom was worse: white noise turned itself back off every time it was turned on via a scene, with the physical switch never touched.

**Root cause:** a racy manual MQTT reconnect loop - `while client.is_connected(): sleep(...)` called immediately after `client.loop_start()`. `is_connected()` could read `False` before the CONNACK was actually processed, tearing the connection down and reconnecting on a ~5s cycle indefinitely, even though the process itself never crashed (systemd restart count stayed at 0 throughout both occurrences). Each reconnect briefly republished the switch's retained state through an "unavailable" transition on `whitenoise/available`, which was enough to refire the switch's HA automation on every cycle.

**Timeline:**
- **2026-08-25** - first found in `toggle-button-mqtt.py` (the original GPIO17 toggle-switch bridge). Confirmed via Mosquitto's own broker log (not the Pi's systemd restart count, which never moved). Fixed by replacing the manual loop with `client.connect_async()` + `client.loop_forever()` (paho's built-in reconnect handling, no race). Confirmed stable via 90+ seconds with zero reconnects before re-enabling the automation.
- **2026-08-31** - same-day as an unrelated hardware change (GPIO17 toggle switch swapped for momentary start/stop buttons), found the identical unfixed race in `scripts/white-noise-mqtt.py` - the switch's own MQTT bridge, unrelated to the physical buttons. It predated the 2026-08-25 fix and the fix was never back-ported to it. Fixed the same way (`connect_async()` + `loop_forever()`), with the periodic `publish_state` poll moved to a background thread since `loop_forever()` blocks the main thread.

**Fix (both occurrences):**
```python
# before: racy
client.loop_start()
while client.is_connected():
    time.sleep(...)

# after: paho's own reconnect handling, no race
client.connect_async(...)
client.loop_forever()
```

**Prevention:** the newer button bridges (`scene-buttons-mqtt.py`, and `white-noise-buttons-mqtt.py` which replaced `toggle-button-mqtt.py`) sidestep the whole bug class by design - they publish a plain non-retained MQTT message only on an actual press, with no persisted state/availability topic to flap in the first place. Any future MQTT bridge script that does need retained state/availability (like `white-noise-mqtt.py` and `publish_healthcheck_mqtt.py`) should use `connect_async()` + `loop_forever()` from the start rather than a manual reconnect loop.

**Debugging this class of bug:** check the actual MQTT traffic, not just the process's own restart count - `docker exec mosquitto mosquitto_sub -h localhost -p 1883 -u homelab -P "$(grep MQTT_PASSWORD .env.mqtt | cut -d= -f2)" -t 'whitenoise/#' -v` and watch whether `whitenoise/available` flaps offline/online every few seconds.
