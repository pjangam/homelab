# Kitchen exhaust fan on air-quality sensors (PM2.5 + humidity, ESP32)
**Status:** Active
**Priority:** P3
**Cost:** ₹1,800-3,500
**Effort:** ~1 weekend (8-12h) + 2-3 evenings tuning thresholds

#### Open items
- [ ] **Pramod, before Wed 2026-11-25:** say how the exhaust fan is switched today: plugged into a socket (which one, 2- or 3-pin) or hard-wired through a switch on the board. HA has no kitchen fan (checked 2026-11-24: no Tinxy or other switch in the kitchen). This decides the fan-switching parts
- [ ] **Pramod, by Wed 2026-11-25:** order the PMS5003 online if the local shop cannot confirm stock (DNA Tech / Hubtronics / Robocraze ship in 2-8 days); it is the long-lead part
- [ ] **Pramod, by Fri 2026-11-27:** buy the rest locally (SHT31/SHT40, relay module, box, jumpers); Amazon/Robu as fallback. Confirm whether the Diwali ESP32 (wled-diwali, .127) is coming off the door, or a loose spare ESP32 is still in the drawer
- [ ] **Pramod:** confirm the room is **Kitchen** for HA's area and the dashboard tile (the Home dashboard already has a Kitchen view with the dishwasher)
- [ ] **Together, Sat 2026-11-28:** bench test: ESPHome firmware for PMS5003 + SHT on the ESP32 (built on the Mac), check readings move with a lit incense stick and a kettle
- [ ] **Together, Sun 2026-11-29:** mount the sensor board in the kitchen, fit the fan switching if the fan is on a socket, add the HA automation in record-only/notify mode first
- [ ] **Together, the week after:** look at a week of cooking data in Grafana/HA history, set thresholds, then let the automation switch the fan
- [ ] **Claude, before Done:** `docs/hardware.md` entry for the new board (and fan switch), HA name + area Kitchen + tile on the Kitchen view of `projects/ha-dashboard/dashboards/home.yaml`, `projects/endpoints/endpoints.toml` entry (ESPHome API 6053, like the kandil switch), `projects/kitchen-exhaust/README.md` with the folder's first file

**Why:** raised 2026-11-24: turn the kitchen exhaust fan on by itself when cooking puts smoke or steam into the air, and off again when it clears. Started from "is this good product to automate exhaust fan in kitchen" about an Electronic Spices MQ-2 module; the answer was no (below).
**State:** researched and decided 2026-11-24; nothing bought. **Picked straight to Active** (user, 2026-11-24): building the weekend of **Sat 2026-11-28 / Sun 2026-11-29 if all parts can be sourced in time**. If the PMS5003 does not arrive, the weekend still builds the humidity half and the fan switch, and the PM sensor goes in when it lands.

#### Feasibility
**Yes, a known build.** ESPHome has first-class components for both sensors: [pmsx003](https://esphome.io/components/sensor/pmsx003/) (PMS5003, UART) and [sht4x](https://esphome.io/components/sensor/sht4x/) / [sht3xd](https://esphome.io/components/sensor/sht3xd/). HA's forum has the same idea done with PM spike + timer ([extractor hood thread](https://community.home-assistant.io/t/ideas-for-how-to-measure-when-cooking-occurs-controlling-a-extractor-hood/422219), [kitchen air purifier thread](https://community.home-assistant.io/t/suggestions-help-on-automation-for-kitchen-air-purifier/581658)); no ready YAML for exactly this, but nothing unknown. Switching a 230V fan with a relay is the kandil build (`projects/smart-switch/`) again.

#### Decisions (2026-11-24)
- **MQ-2 rejected.** It responds mostly to LPG, methane, hydrogen, alcohol and heavy smoke, and only weakly to cooking-oil fumes or particulates. Steam, humidity and temperature make it drift, so it would false-trigger on boiling water and miss frying. Its heater is always on (~150mA at 5V, ~0.75W) and needs 24-48h burn-in. Its analog out swings to 5V, so it needs a divider for the ESP32's 3.3V ADC. The other MQ-series (MQ-135 etc.) share every one of these problems.
- **This is not a gas-leak safety device, and must not be presented as one.** Switching a fan relay or motor during an LPG leak can strike a spark at exactly the wrong moment. Leak safety means a certified LPG detector with its own shut-off valve; out of scope here. Do not add a gas sensor "while we are at it".
- **Triggers: PM2.5 for smoke, humidity rise for steam.** PM2.5 is the best single signal for frying and tadka smoke. Humidity catches boiling and pressure-cooker whistles, read as **how fast RH rises** (an HA `derivative` helper), not an absolute level, because kitchen RH swings with the weather.
- **Recommended build:** one ESP32 (ESPHome) with a PMS5003 + an SHT31/SHT40; HA turns the fan on when either signal rises and off a few minutes after both settle.
- **Optional, not in v1:** VOC sensor (SGP40 or ENS160, ~₹600-1,200) for the smell of cooking without visible smoke; a stove thermistor (~₹50-100) as a direct "burner on" signal. Add only if a week of data shows PM + humidity miss real cooking.

#### Design notes
- **The ESP32 only reports; HA decides.** Thresholds stay editable in HA without a reflash, same as `humidity-dry-mode.md`.
- **PM sensor: PMS5003, SDS011 as the equal fallback.** Both are laser particle counters on 5V with 3.3V UART, both ~₹1,400-2,200. PMS5003 is smaller and has a SET pin to sleep its fan; SDS011 is bulkier. Take whichever the shop has. **Trap:** the PMS5003 uses a 1.25mm 8-pin connector - buy the listing "with cable"/adapter board or it cannot be wired to dupont jumpers.
- **Humidity sensor: SHT40/SHT41 first, SHT31 equal.** Same reasoning as `humidity-dry-mode.md`: SHT4x has a heater ESPHome can pulse to drive off condensation, which steam will cause here. **Not "BME280" listings** (often a BMP280, no humidity) and not DHT11/22. The SHT40 already bought is the bedroom one - not spare.
- **Placement decides whether it works, and grease decides how long it lasts.** Not above the hob (grease and heat coat the PM sensor's fan and optics in weeks) and not in the fan's own airflow. A wall 1.5-2m from the hob at head height, PM inlet facing down. Expect to clean or replace the PM sensor in 1-3 years in a kitchen; run it on a 30-60s duty cycle (ESPHome `update_interval`) to stretch its fan and laser life.
- **Signal shape, not one threshold.** Fan on when PM2.5 jumps by a margin over its 30-min baseline, or RH rises faster than ~X%/min (number set from a week of data). Off 5-10 min after both are back near baseline, with a minimum run time so it does not chatter.
- **Manual wins over automatic.** The automation only turns off a fan it turned on itself (an `input_boolean` "fan on by automation"); a fan someone switched on by hand stays on. If the fan is on a wall switch, wiring the relay **in parallel with the switch** means the switch on = always on, switch off = automatic - the override needs no code.
- **Never lie about state.** ESPHome's API gives HA availability for free: sensor `unavailable` = the automation does nothing, not "air is clean, turn off". The fan relay comes up **off** after a power cut (`restore_mode: ALWAYS_OFF`); HA re-evaluates on `homeassistant: start` and on the sensor's first reading, not only on a threshold crossing.
- **Power cuts:** board and fan are both mains-only, which is fine - the fan cannot run without mains anyway. No UPS needed.
- **Fan switching, by how the fan is wired today (Pramod to answer):**
  - **Plugged into a socket:** a plug-in relay box, the kandil build again (`projects/smart-switch/wiring.md`, firmware in `projects/smart-switch/esphome/`). Fits this weekend. The kandil relay itself is claimed after Diwali by `baby-monitor-charge-limit.md`, so buy a second relay module.
  - **Hard-wired through the switchboard:** a relay in parallel with the existing switch, inside the board, with its own 5V supply and fuse - this is exactly `smart-switch-in-wall.md`'s open design (HLK-PM01, fuse, opto or low-voltage switch). **Not a weekend job on a kitchen board:** do the sensors this weekend and the fan switch when the in-wall design is settled. A flashable in-wall relay (Sonoff MINIR4, [ESPHome page](https://devices.esphome.io/devices/sonoff-minir4-extreme/), soldering needed) is the off-the-shelf version, but see Rejected.
  - **One board or two:** the sensor wants to be away from the hob, the relay near the fan's socket or switch. If they are within a few metres, one ESP32 with a lead to the relay box; otherwise the sensor board here plus a separate relay box. Decide when the fan's wiring is known.
- **Fan load:** a kitchen exhaust fan is ~30-60W (estimate; read its label). The SONGLE-type 10A 250VAC relay used for the kandil is ample, inductive inrush included.
- **Build firmware on the 2019 MacBook** (`projects/voice-assistant/esphome/build_on_mac.sh` pattern), never on xero (RAM/heat history).

#### Overlaps
- **`tracker/humidity-dry-mode.md`** - same sensor choice (SHT4x over DHT/BME), same "ESP32 reports, HA decides, unavailable means do nothing" pattern, same hysteresis logic. Reuse its reasoning; the sensor rejections there apply here.
- **`tracker/smart-switch.md` / `tracker/smart-switch-in-wall.md`** - the fan relay is either the kandil plug box again or the second real use case for the in-wall switch. If the fan is hard-wired, this project is a reason to settle the in-wall design (or the Tinxy 4N reflash test) sooner.
- **`tracker/diwali-lights.md`** - its ESP32 (wled-diwali, .127) frees when the lights come down after 24 Nov. It is also counted on by `wol-to-esp32.md`, `wifi-analog-clock.md` and `hub75-wall-display.md`; whichever is built first takes it. This one is the first with a date.
- **`tracker/baby-monitor-charge-limit.md`** - has claimed the kandil relay box after Diwali, so it is not free for the fan.
- **`tracker/shopping-list-display.md`** - also a kitchen device; no shared hardware, but a kitchen screen could show the fan state.

#### Readymade alternatives
- **Countdown timer switch for the fan (~₹300-800, estimate):** press it when cooking starts, fan runs 30-60 min. If the real problem is only "forgetting to switch it off", this solves it for a fifth of the price with no sensors. It does not catch the fan never being switched on, which is the itch here.
- **Kitchen chimney with an auto-on heat sensor (₹12,000+, estimate):** a different appliance and installation, not a retrofit of the exhaust fan. Out of proportion for this.
- **Off-the-shelf air-quality monitors:** Xiaomi/Qingping/Tuya units are cloud or BLE-only (the Tinxy lesson); IKEA VINDSTYRKA is Zigbee and there is no Zigbee coordinator here; Apollo AIR-1 / AirGradient run ESPHome but ship from abroad at several times the cost of the parts. None beats ~₹2,000 of parts on a board the repo already knows how to run.

#### Rejected
- **MQ-2 (Electronic Spices, 200-10000ppm) and other MQ gas sensors** - see Decisions.
- **Sonoff MINIR4 for the fan, for now:** no Indian retail price found except Fruugo at ₹4,949 (2026-11-24, [listing](https://www.fruugoindia.com/sonoff-minir4-wi-fi-smart-switch-10a-mini-extreme-smart-home-relay-module-remote/p-309819894)); ESPHome needs soldering to the module. The cheaper **MINIR4M** (Matter) was ~₹1,800-2,000 on Amazon.in in late 2025 ([price history](https://www.cheapestinindia.com/price-history/sonoff-matter-smart-switch-minir4m-wi-fi-smart-switch-10a-2400w-zero-and-fire-wires--68e293b577df51d843b2ae09)) but ESPHome needs its chip replaced ([ESPHome](https://devices.esphome.io/devices/Sonoff-MINIR4M/)), and stock firmware is eWeLink cloud. Revisit only with `smart-switch-in-wall.md`.
- **Any cloud smart plug or switch for the fan** - fails in an ISP outage, cannot be pointed at xero.

#### Parts
Prices: PMS5003 from listings fetched 2026-11-24 (DNA Tech India ₹1,652 incl. GST, [link](https://www.dnatechindia.com/pms5003-pm2.5-air-quality-sensor-buy-in-india); Hubtronics ₹1,499 + GST, [link](https://hubtronics.in/sensors/pms5003-pm2.5-sensor); Robocraze ₹2,022, [link](https://robocraze.com/products/pms5003-pm2-5-air-quality-sensor-by-plantower)). SDS011 ₹1,200-2,200 in search snippets the same day (electronicscomp ₹2,180, [link](https://electronicscomp.com/nova-pm-sensor-sds011-high-precision-laser-pm2.5-air-quality-detection-sensor)). Everything else is a local-shop estimate.

```parts
qty | item | est | note
1 | ESP32 dev board (WROOM-32, USB) | 0-500 | skip if the Diwali board (.127) is off the door or a loose spare is in the drawer (Pramod to confirm); else local
1 | PMS5003 PM2.5 sensor WITH its 8-pin cable/adapter | 1400-2100 | local if stocked (ask), else ORDER ONLINE by Wed 25 Nov (DNA Tech/Hubtronics/Robocraze). SDS011 is an equal substitute if that is what the shop has
1 | SHT40/SHT41 breakout, I2C (or SHT31-D) | 250-450 | local; not "BME280", not DHT11/22. The SHT40 on hand is the bedroom one
1 | USB charger 5V 1A + USB cable | 0-200 | have spares probably (Pramod to check); one per board, never a shared GaN port (see voice-living-room in hardware.md)
1 | Small ABS project box (~85x55x30mm) | 120-200 | local; vent slots so the PM sensor breathes and the SHT sits outside or at a slot
1 | Jumpers / 4-6 core lead | 0-60 | have, or Workbench stock
# Fan on a socket: plug-in relay box (kandil build)
1 | 1-channel 5V relay module (KY-019 type, 10A 250VAC) | 60-100 | local; the kandil one is claimed by baby-monitor-charge-limit
1 | Junction box with screw lid | 60-150 | local
2 | WAGO 221 2-way lever connectors | 30-80 | local; neutral and earth through
1 | 3-pin 6A plug + socket, 1m 3-core cable | 100-200 | local; so the relay switches phase, not neutral
# Fan hard-wired: in-wall relay (later, with smart-switch-in-wall)
1 | HLK-PM01 5V supply, genuine Hi-Link | 180-195 | local; see smart-switch-in-wall.md for the full list
1 | 1-channel 5V relay module | 60-100 | local
1 | Fuse holder + T1A fuse, 5x20mm | 12-20 | local
```

**Cost detail:** **₹1,800-3,500** covers the sensor board (PMS5003 + SHT + box, ~₹1,700-3,100) plus the socket relay box (~₹250-530). With the Diwali ESP32 and a spare charger it is about ₹2,000; buying the ESP32 and a charger new adds ~₹700. The in-wall variant costs about the same in parts but belongs to `smart-switch-in-wall.md`'s effort, not this weekend's. **Cheaper variant:** humidity only (SHT on the ESP32, no PM) at ~₹400-700 catches steam and pressure cookers but misses frying smoke - the main reason for the project.

**Effort detail:** **~8-12h over the weekend, then 2-3 short evenings.**
1. **Bench (Sat, 2-3h):** ESPHome YAML for pmsx003 + sht4x, build on the Mac, flash, add to HA; incense stick and kettle to see both signals move. Most decisive phase: if the PM reading does not jump on smoke, stop and rethink.
2. **Fan switch (Sun, 2-3h):** socket relay box from the kandil drawings, metered before mains; or deferred if hard-wired.
3. **Mounting (Sun, 2-3h):** **the phase that overruns** - finding a wall spot away from the hob, out of the fan draft, with a socket for the charger, and a box the PM sensor can breathe through. Expect to move it once after seeing data.
4. **HA (1-2h):** derivative helper on RH, baseline on PM2.5, the on/off automation with the "on by automation" flag, record-only first.
5. **Tuning (2-3 evenings over the next week):** read a week of real cooking, set thresholds, then let it switch. Plus the done-rules paperwork (hardware.md, dashboard tile, endpoints.toml, README) ~1h.

**When built (CLAUDE.md done-rules):** new `docs/hardware.md` entry for the board (and relay box), with HA name, area and tile; HA area **Kitchen** (user to confirm) and a tile on the Kitchen view in `home.yaml`, pushed with `ui_dashboard.py restore` and checked with `shot_dashboard.sh`; `endpoints.toml` entry for the ESPHome API (port 6053, as the kandil switch) - no MQTT unless that changes; `projects/kitchen-exhaust/README.md` with its first file and its line in the root `Readme.md`. Ask the `circuit-diagram` agent for the wiring before soldering.

#### Log
- 2026-11-24: recorded. MQ-2 rejected; PM2.5 + humidity-rise on an ESPHome ESP32 decided; not a gas-safety device. Repo check: no kitchen fan in HA (no Tinxy in the kitchen), Home dashboard has a Kitchen view (dishwasher only); Diwali ESP32 frees after 24 Nov, kandil relay already claimed. Set straight to Active (user) for the weekend of 28-29 Nov, parts permitting.
