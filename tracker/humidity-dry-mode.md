# Humidity-triggered AC dry mode and mister (temperature/humidity sensor on an ESP32)
**Status:** Active
**Priority:** P3
**Cost:** ₹300-500
**Effort:** ~2 evenings (4-6h)

#### Open items
- [ ] **Pramod:** decide where the SHT40 lives: the Pi (leaning, 2026-11-18: pins 3/5, I2C on, small MQTT script like pi-health) or the bedroom satellite (firmware already written; it frees GPIO19/21 for `scene-remote.md` if it goes to the Pi)
- [ ] **Pramod:** wire the SHT40 to the bedroom satellite on a ~30cm lead: VIN->3V3, GND->GND, SDA->GPIO21, SCL->GPIO19, sensor outside the box
- [ ] **Pramod:** flash the bedroom satellite (OTA to .125, built on the Mac with `build_on_mac.sh`); it also carries the extender-first WiFi (the play button and reply events are already on the board, flashed 2026-11-18)
- [ ] **Claude:** once it reads, check `sensor.voice_satellite_bedroom_temperature`/`_humidity` in HA and add both to the Bedroom dashboard view
- [ ] **Together:** bench the sensor beside a known hygrometer for a day, then record a few weeks of data before writing any automation

**Why:** raised 2026-10-17: turn the AC (dehumidify) on above a humidity level, or a mister/humidifier on below one, automatically. Amazon lists DHT sensors at Rs 85-300, and the question was which sensor is actually worth buying.
**State:** researched in conversation 2026-10-17, nothing bought. Sensor and architecture decided (below). **Room: Bedroom.** **Board: the bedroom voice satellite** (.125, GPIO21/19 free; decided 2026-10-17, reversing the earlier "new ESP32" call). **AC:** has dry mode (user, 2026-10-17); still confirm `dry` is in the MirAIe entity's `hvac_modes` in HA. **Mister:** the user owns a non-smart one (brand not remembered yet) with a **touch button** that most likely has to be pressed after power-up, so a smart plug alone cannot automate it. **Plan: build in two phases** - phase 1 is sensor + AC dry mode only; phase 2 (mister) is optional and decided later between hacking the touch button and skipping it. Phase 1 only for now.

#### Feasibility
**Yes, a known build with no unknowns.** ESPHome has first-class components for both recommended sensors ([SHT3x-D](https://esphome.io/components/sensor/sht3xd/), [SHT4x](https://esphome.io/components/sensor/sht4x/)); they show up in HA as ordinary temperature and humidity entities. The AC is already in HA via MirAIe ("Miraie AC self-healing"), so the AC half is an HA automation, not hardware.

#### Sensor choice (decided 2026-10-17)
- **Recommended: Sensirion SHT41/SHT40 (~Rs 300-450) or SHT31/SHT30 (~Rs 250-400) breakout.** About +-2% RH (SHT41 +-1.8%), 0-100% RH, I2C, and a **built-in heater** to drive off condensation. The SHT4x is the better pick near a mister: ESPHome's sht4x component can pulse the heater periodically (`heater_max_duty`), while the sht3xd only takes `heater_enabled` as a fixed boot setting that biases every reading (temperature up, RH down).
- **Budget fallback: AHT20 (~Rs 100-180).** +-2-3% RH on paper, I2C, no heater. Fine for a room that never gets near saturation; not near a mister.
- **Rejected: DHT11.** +-5% RH and only 20-80% RH range - useless exactly where the automation needs to act.
- **Rejected: DHT22/AM2302.** Mostly clones; drifts and sticks high after time in humid air, and its timing-sensitive single-wire protocol is the fussy one. The extra rupees over a DHT11 buy little.
- **Rejected: "BME280" listings.** Commonly a BMP280 (pressure/temperature, **no humidity**) sold under the BME name; identify by chip ID 0x58 vs 0x60, but simpler to not buy one for this.
- **Trap: ESP32 + IDF + SHT3x** at high I2C speed fails with "Communication with SHT3xD failed" on setup; the ESPHome docs suggest a 10ms I2C timeout. Use the default 100kHz and it does not arise.

#### Design notes
- **The ESP32 only reports; HA decides.** ESPHome publishes temperature and RH; HA automations switch the AC and the mister. Thresholds stay editable in HA without a reflash.
- **Hysteresis, not one threshold.** E.g. mister on below 40% RH, off above 50%; AC dry on above ~70%, off below ~60%. Add a minimum on/off time (10min) so the AC compressor is not short-cycled by a sensor hovering at the edge.
- **Never lie about state, and fail safe.** If the sensor entity goes `unavailable` (board offline, power cut, I2C error), the mister automation must turn the mister **off**, not hold its last state - a mister running on a stale "too dry" reading wets the room. ESPHome's API connection gives HA the availability for free.
- **Board: the bedroom voice satellite (decided 2026-10-17).** Briefly planned as a new dedicated ESP32, then switched back: it saves Rs 200-600 and a USB adapter by the bed. Trade-off accepted: voice and humidity share one firmware and go offline together (the unavailable-means-off rule covers the mister). Pin analysis: the two voice satellites ("Local voice control (HA Assist)") are ESPHome ESP32s already in the Bedroom (.125) and Living Room (.126). They use GPIO2, 4, 25, 32, 33, with 22, 26, 27 planned for the speaker amp, so **I2C goes on SDA GPIO21 / SCL GPIO19** (not the default SCL 22, taken by the amp's DIN). Adding a sensor block to `voice-satellite-common.yaml` (or the per-room file) costs nothing. Rejected the alternatives: a dedicated new ESP32 (Rs 350-600, "Diwali lights 2026" and "Automatic pour-over coffee" already assume buying one; no spare exists); an ESP32-C3 SuperMini (~Rs 200-300) if the sensor must be in a room with no satellite.
- **Placement decides accuracy.** Put the sensor on a 15-30cm lead outside the satellite's box: the ESP32 and amplifier warm their enclosure and would read low RH. Keep it **1-2m from the mister's spray** (or it reads the plume, not the room) and **out of the AC's airflow** (or it reads the coil's dry air and switches the AC off early).
- **The mister must be a "dumb" one.** Switched by a plug or relay, it only works if the mister starts when power is applied (mechanical switch left on). Most button-start ultrasonic humidifiers come up off after power returns and cannot be automated this way. The user owns a non-smart mister (brand not remembered, 2026-10-17): test it before buying the plug.
- **Switching the mister:** a local smart plug (ESPHome/Tasmota-flashed, or Shelly), or a home-built switch from "In-house smart switch to replace Tinxy" if that lands first - the user is open to either. **Not a Tinxy or other cloud plug** - the Tinxy lesson, same reasoning as "In-house smart switch to replace Tinxy". A relay switching mains on a breadboard-built satellite is the wrong place to learn mains wiring; prefer a plug.
- **AC dry mode:** the AC has it (user, 2026-10-17). Confirm the MirAIe climate entity lists `dry` in `hvac_modes` before writing the automation; if HA does not expose it, "cool at 26C" is the fallback dehumidify.
- **Power cuts:** the satellite and mister are mains-only, which is fine; the AC also loses power. When mains returns, HA re-evaluates the automation on the sensor's next reading - write the automation with a `homeassistant: start` / sensor-state trigger, not only a threshold crossing, so it does not wait for the next crossing.
- **Build firmware on the 2019 MacBook** with `projects/voice-assistant/esphome/build_on_mac.sh`, never on xero (bad RAM history, see the system incidents memory).

#### Readymade alternatives
- **Xiaomi Mi Temperature and Humidity Monitor 2 (BLE, ~Rs 300-600, estimate):** good sensor, but BLE - needs an ESPHome Bluetooth proxy (which the satellite could be) or the custom ATC firmware. More moving parts than a wired I2C sensor on a board already in the room; only worth it for a room with no ESP32.
- **Smart humidifiers with built-in humidistat (Wi-Fi, Rs 3,000+, estimate):** cloud apps, cannot be pointed at xero, fail in an ISP outage. Rejected. A humidifier with its own *manual* humidistat dial needs no automation at all - if the only goal is "mister keeps the room at 45%", that is the cheaper answer.
- **Tuya/Wi-Fi temperature-humidity sensors (~Rs 500-1,000, estimate):** cloud-dependent. Rejected.

#### Parts
```parts
qty | item | est | note
1 | SHT41 (or SHT40) breakout, I2C | 300-450 | local first, else online; estimate. SHT31-D is the equal alternative (IndiaMART lists GY-SHT31-D at Rs 203, ThinkRobotics at Rs 850, both 2026-10-17). Skip DHT11/DHT22/"BME280"
1 | 4-core lead + header pins, ~30cm | 20-50 | local; takes the sensor outside the satellite's warm box
1 | Local smart plug (ESPHome/Tasmota-capable) | 700-1200 | for the user's mister, only if it restarts on power-up; estimate. Or a home-built switch
```

**Cost detail:** **Rs 300-500** for the sensor on the bedroom satellite (phase 1). Phase 2 with a smart plug adds ~Rs 700-1,200.

**Effort detail:** **~4-6h.** Bench the sensor against a reference hygrometer for a day (0.5h of work); ESPHome sensor block, build on the Mac, flash (1h); HA automations with hysteresis, minimum run time and the unavailable-means-off rule (1-2h); mounting the sensor on its lead at a sensible spot (1h) and plug/mister setup (1h). **Placement is the phase that overruns**: finding a spot that is out of the AC draft, away from the spray and not next to the satellite's heat takes moving it a few times and watching the graph.

**When built:** update the satellite's entry in `docs/hardware.md` (new sensor, GPIO19/21; a new board or plug gets its own entry), and note the plug's address in `projects/endpoints/endpoints.toml` if it serves anything.

#### Log
- 2026-10-17: noted. Sensor and architecture decided in conversation; voice satellites identified as the likely host board (no new ESP32). Open: room, mister ownership and type, AC dry mode in the MirAIe entity.
- 2026-10-17: room is the Bedroom; a new dedicated ESP32 instead of the voice satellite; user owns a non-smart mister (brand TBD), to be switched by a bought or home-built smart switch.
- 2026-10-17: AC has dry mode. Mister has a touch button and likely will not start on power-up - split into phase 1 (sensor + AC) and optional phase 2 (hack the touch button, swap mister, or skip).
- 2026-10-17: host board back to the bedroom voice satellite (SDA GPIO21 / SCL GPIO19, sensor on a lead outside its box); no new ESP32.
- 2026-11-18: SHT40 arrived (user). Started as record-only: `sht4x` block (60s, heater off) added to `voice-satellite.yaml` (bedroom board only) on I2C SDA21/SCL19, config validated; not wired or flashed yet. Automations deferred until there is data.
- 2026-11-18: same pending flash: bedroom satellite now prefers the extender `dlink_pramod_bed_room`, router as fallback (it only knew the router before), plus `WiFi network` / `WiFi access point` / `WiFi signal` diagnostics. `wifi_ssid_bedroom` copied into the voice-assistant `secrets.yaml` on xero (the Mac build pulls it from there).
- 2026-11-18: board reopened (user): the Pi is in the bedroom too (on its pegboard, not near xero), and the satellite is filling with buttons (`scene-remote.md`), so the Pi is now the leaning choice. The satellite's `sht4x` block stays until decided; harmless if flashed unwired.
