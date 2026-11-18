# Remote control for scenes/scripts (Spotify, white noise, etc.)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** decide the buttons needed (e.g. white noise on/off, Spotify play/pause/skip)
- [ ] **Together:** pick ESPHome's native HA integration (least custom code, matches the MQTT-bridge pattern) or fully custom firmware

**Why:** the existing physical GPIO buttons (wol-sender Pi, see ✅ Done) prove the pattern - a button publishes an MQTT message, an HA automation fires a scene/script - but that only works for locations physically next to a host with GPIO. An ESP32/ESPHome-based remote would extend the same no-app physical-control idea (see "Physical GPIO buttons (wol-sender Pi)" in ✅ Done) to a standalone battery/USB device controllable from anywhere, not tied to the Pi's location - e.g. a bedside remote for white noise start/stop or Spotify play/pause/skip without opening the HA app.
**State:** not started - the ESP32/ESPHome route was already flagged as the likely answer for "a button location that isn't next to an existing host" in the scene-buttons project (now done, that thread closed as not needed for household use); this generalizes that to Spotify/media control specifically.
