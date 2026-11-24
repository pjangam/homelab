# Kitchen exhaust fan on stove heat and smoke (IR thermometer + PM2.5, ESP32)
**Status:** Active
**Priority:** P3
**Cost:** ₹2,000-4,500
**Effort:** ~1 weekend (8-12h) + 2-3 evenings tuning thresholds

#### Open items
- [ ] **Together, Sat 2026-11-28 (decides it):** bench the MLX90614 at 60-70cm over the hob: one burner lit under a pan must lift the object reading clearly over room temperature within ~30s; if not, the wide-view averaging is too weak and the trigger needs rethinking
- [ ] **Pramod, before Wed 2026-11-25:** say how the exhaust fan is switched today: plugged into a socket (which one, 2- or 3-pin) or hard-wired through a switch on the board. HA has no kitchen fan (checked 2026-11-24: no Tinxy or other switch in the kitchen). This decides the fan-switching parts
- [ ] **Pramod, by Wed 2026-11-25:** order the PMS5003 online if the local shop cannot confirm stock (DNA Tech / Hubtronics / Robocraze ship in 2-8 days); it is the long-lead part. If it will not arrive by Sat, build with the MLX90614 only and add it later
- [ ] **Pramod, by Fri 2026-11-27:** buy the rest locally (GY-906 MLX90614 **BAA** - check the marking on the can, relay module, box, jumpers); Amazon/Robu as fallback. Confirm whether the Diwali ESP32 (wled-diwali, .127) is coming off the door, or a loose spare ESP32 is still in the drawer
- [ ] **Pramod:** confirm the room is **Kitchen** for HA's area and the dashboard tile (the Home dashboard already has a Kitchen view with the dishwasher)
- [ ] **Together, Sun 2026-11-29:** mount the sensors, fit the fan switching if the fan is on a socket, add the HA automation in record-only mode first
- [ ] **Together, the week after:** read a week of cooking in HA history/Grafana, set thresholds, then let the automation switch the fan
- [ ] **Claude, before Done:** `docs/hardware.md` entry for the new board (and fan switch), HA name + area Kitchen + tile on the Kitchen view of `projects/ha-dashboard/dashboards/home.yaml`, `projects/endpoints/endpoints.toml` entry (ESPHome API 6053, like the kandil switch), `projects/kitchen-exhaust/README.md` with the folder's first file

**Why:** raised 2026-11-24: turn the kitchen exhaust fan on by itself when cooking starts, and off again once the stove is off and the smoke has cleared. Started from "is this good product to automate exhaust fan in kitchen" about an Electronic Spices MQ-2 module; the answer was no (below).
**State:** researched and decided 2026-11-24 (design changed the same day from PM2.5 + humidity to IR + PM2.5); nothing bought. **Picked straight to Active** (user, 2026-11-24): building the weekend of **Sat 2026-11-28 / Sun 2026-11-29 if all parts can be sourced in time**. Fallback if parts are short: MLX90614 only, PMS5003 added later on the same board and firmware.

#### Feasibility
**Yes, a known build.** ESPHome has first-class components for both sensors: [mlx90614](https://esphome.io/components/sensor/mlx90614/) (I2C, object + ambient temperature) and [pmsx003](https://esphome.io/components/sensor/pmsx003/) (PMS5003, UART). HA's forum has cooking-triggered hood control done with PM spikes and timers ([extractor hood thread](https://community.home-assistant.io/t/ideas-for-how-to-measure-when-cooking-occurs-controlling-a-extractor-hood/422219), [kitchen air purifier thread](https://community.home-assistant.io/t/suggestions-help-on-automation-for-kitchen-air-purifier/581658)). The one real unknown is how strongly a wide-view IR sensor 60-70cm up sees one burner (first Open item). Switching a 230V fan with a relay is the kandil build (`projects/smart-switch/`) again.

#### Decisions (2026-11-24)
- **Main trigger: MLX90614 IR thermometer, 90° wide-view (MLX90614ESF-BAA), wall-mounted 60-70cm above the 3-burner gas stove, looking down.** "Stove is on" is the thing that actually means cooking; it reacts within seconds of a flame and a hot pan, and it sees all three burners from one spot with nothing on the hob.
- **Second sensor: PM2.5 (PMS5003).** Keeps the fan running while smoke lingers after the flame is off, and catches heavy frying/tadka smoke.
- **HA logic:** fan **on** when the stove is hot (object temperature risen over room temperature) **or** PM2.5 is high; **off** when the stove is cool **and** PM2.5 has been normal for ~5 min.
- **Humidity dropped** (was in the first version of this entry). The IR sensor covers steam: the stove is always hot when there is steam, so a humidity-rise signal adds nothing.
- **VOC dropped** (SGP40/ENS160): noisy, slow baselines, little gain over heat + PM.
- **MQ-2 rejected.** It responds mostly to LPG, methane, hydrogen, alcohol and heavy smoke, and only weakly to cooking-oil fumes or particulates. Steam, humidity and temperature make it drift, so it would false-trigger on boiling water and miss frying. Its heater is always on (~150mA at 5V, ~0.75W) and needs 24-48h burn-in. Its analog out swings to 5V, needing a divider for the ESP32's 3.3V ADC. The other MQ-series share these problems.
- **This is not a gas-leak safety device, and must not be presented as one.** Switching a fan relay or motor during an LPG leak can strike a spark at exactly the wrong moment. Leak safety means a certified LPG detector with its own shut-off valve; out of scope. Do not add a gas sensor "while we are at it".

#### Rejected sensor placements (2026-11-24)
| Option | Why not |
|---|---|
| Thermistor or thermocouple at each burner | 3 burners = 3 sensors in flame heat and grease, in the way of cleaning, with wiring across the hob |
| DS18B20 in the rising hot air above the stove (~₹100) | Works and is the **cheap fallback**, but reacts 1-2 min late: it waits for the air to warm, not the pan |
| AMG8833 8x8 thermal camera (₹3,000+) | Works, and would tell burners apart, but overkill: one averaged number is enough to say "stove on" |

#### Design notes
- **The ESP32 only reports; HA decides.** Thresholds stay editable in HA without a reflash, same pattern as `humidity-dry-mode.md`.
- **Read the IR as a difference, not an absolute.** The MLX90614 reports both object and its own ambient temperature; trigger on object minus room temperature (or object over a slow baseline), so a hot summer afternoon does not look like cooking.
- **Wide view averages.** At 65cm a 90° cone covers a ~1.3m circle - the whole hob plus counter and wall - so one small burner raises the averaged reading by a few degrees, not by hundreds. That is why the first Open item is a bench test with one burner and a pan. If the lift is too small: aim it at the burners rather than straight down, or move to the 35° **BCC** variant at the same height (covers ~40cm, so not all three burners).
- **Which variant you get:** GY-906 boards are sold as "MLX90614" with BAA (90°), BCC (35°) or DCI (5°) cans; the marking is on the can. Buy the BAA; check before leaving the shop.
- **Heat, steam and grease at the sensor.** 60-70cm over a flame the rising air can reach 50°C+ and carries grease. The MLX90614 is rated to 85°C ambient (estimate from the ESF datasheet range; confirm). Mount it on the wall slightly to the side of the plume, angled at the hob, and wipe the window when cleaning the kitchen. **The ESP32 and the PMS5003 go in a box off to the side, out of the plume**, with the MLX on a short 4-core lead (I2C at the default 100kHz, the MLX's SMBus maximum; keep the lead under ~50cm).
- **PM sensor: PMS5003, SDS011 as the equal fallback.** Both are laser counters on 5V with 3.3V UART. **Trap:** the PMS5003 uses a 1.25mm 8-pin connector - buy the listing "with cable"/adapter, or it cannot be wired to dupont jumpers. In a kitchen it will foul: keep it out of the plume, inlet facing down, and expect to clean or replace it in 1-3 years. Run it on a 30-60s duty cycle (ESPHome `update_interval`) to stretch its fan and laser life.
- **Off needs both and a delay.** Off only when the IR delta is back near zero **and** PM2.5 has been near baseline for ~5 min, with a minimum run time so the fan does not chatter when a pan is lifted off and back.
- **Manual wins over automatic.** The automation only turns off a fan it turned on itself (an `input_boolean` "fan on by automation"); a fan someone switched on by hand stays on. If the fan is on a wall switch, wiring the relay **in parallel with the switch** means switch on = always on, switch off = automatic - an override that needs no code.
- **Never lie about state.** ESPHome's API gives HA availability for free: a sensor `unavailable` = the automation does nothing, never "stove is cold, turn off". The fan relay comes up **off** after a power cut (`restore_mode: ALWAYS_OFF`); HA re-evaluates on `homeassistant: start` and on the sensors' first readings, not only on a threshold crossing.
- **Power cuts:** board and fan are both mains-only, which is fine - the fan cannot run without mains anyway. No UPS needed.
- **Fan switching, by how the fan is wired today (Pramod to answer):**
  - **Plugged into a socket:** a plug-in relay box, the kandil build again (`projects/smart-switch/wiring.md`, firmware in `projects/smart-switch/esphome/`). Fits this weekend. The kandil relay itself is claimed after Diwali by `baby-monitor-charge-limit.md`, so buy a second relay module.
  - **Hard-wired through the switchboard:** a relay in parallel with the existing switch, inside the board, with its own 5V supply and fuse - exactly `smart-switch-in-wall.md`'s open design (HLK-PM01, fuse). **Not a weekend job on a kitchen board:** do the sensors this weekend (record-only), the fan switch when the in-wall design is settled.
  - **One board or two:** if the fan's socket or switch is within a few metres of the sensor box, one ESP32 with a lead to the relay box; otherwise the sensor board plus a separate relay box. Decide when the fan's wiring is known.
- **Fan load:** a kitchen exhaust fan is ~30-60W (estimate; read its label). The 10A 250VAC relay type used for the kandil is ample, inductive inrush included.
- **Build firmware on the 2019 MacBook** (`projects/voice-assistant/esphome/build_on_mac.sh` pattern), never on xero (RAM/heat history).

#### Overlaps
- **`tracker/smart-switch.md` / `tracker/smart-switch-in-wall.md`** - the fan relay is either the kandil plug box again or the second real use case for the in-wall switch. If the fan is hard-wired, this project is a reason to settle the in-wall design (or the Tinxy 4N reflash test) sooner.
- **`tracker/diwali-lights.md`** - its ESP32 (wled-diwali, .127) frees when the lights come down after 24 Nov. It is also counted on by `wol-to-esp32.md`, `wifi-analog-clock.md` and `hub75-wall-display.md`; whichever is built first takes it. This one is the first with a date.
- **`tracker/baby-monitor-charge-limit.md`** - has claimed the kandil relay box after Diwali, so it is not free for the fan.
- **`tracker/humidity-dry-mode.md`** - same "ESP32 reports, HA decides, unavailable means do nothing" pattern; no longer shares a sensor since humidity was dropped here.
- **`tracker/shopping-list-display.md`** - also a kitchen device; no shared hardware, but a kitchen screen could show the fan state.

#### Readymade alternatives
- **Countdown timer switch for the fan (~₹300-800, estimate):** press it when cooking starts, fan runs 30-60 min. If the real problem were only "forgetting to switch it off", this solves it for a fifth of the price. It does not catch the fan never being switched on, which is the itch here.
- **Kitchen chimney with an auto-on heat sensor (₹12,000+, estimate):** a different appliance and installation, not a retrofit of the exhaust fan. Out of proportion.
- **Off-the-shelf air-quality monitors:** Xiaomi/Qingping/Tuya units are cloud or BLE-only (the Tinxy lesson); IKEA VINDSTYRKA is Zigbee and there is no Zigbee coordinator here; Apollo AIR-1 / AirGradient run ESPHome but ship from abroad at several times the parts cost. None of them sees the stove, which is the main trigger.
- **Sonoff MINIR4 in-wall relay for the fan, rejected for now:** no Indian retail price found except Fruugo at ₹4,949 (2026-11-24, [listing](https://www.fruugoindia.com/sonoff-minir4-wi-fi-smart-switch-10a-mini-extreme-smart-home-relay-module-remote/p-309819894)), and ESPHome needs soldering ([ESPHome](https://devices.esphome.io/devices/sonoff-minir4-extreme/)). The cheaper **MINIR4M** (~₹1,800-2,000 on Amazon.in in late 2025, [price history](https://www.cheapestinindia.com/price-history/sonoff-matter-smart-switch-minir4m-wi-fi-smart-switch-10a-2400w-zero-and-fire-wires--68e293b577df51d843b2ae09)) needs its chip replaced for ESPHome ([ESPHome](https://devices.esphome.io/devices/Sonoff-MINIR4M/)); stock firmware is eWeLink cloud. Revisit only with `smart-switch-in-wall.md`.
- **Any cloud smart plug or switch for the fan** - fails in an ISP outage, cannot be pointed at xero.

#### Parts
Prices from listings found 2026-11-24 (search snippets; check before buying, local shop first):
- **MLX90614 / GY-906:** Hubtronics ₹688 ([link](https://hubtronics.in/other-sensors/gy-906-mlx90614esf-temperature-sensor)), Probots "GY-906 BAA" ₹749 ([link](https://probots.co.in/non-contact-infrared-temperature-sensor-mlx90614-digital-output.html)), Zbotic MLX90614ESF-BAA ₹636 ([link](https://zbotic.in/product/mlx90614esf-baa-non-contact-infrared-temperature-sensor/)); budgeted ₹600-1,200 to allow a better-sourced board.
- **PMS5003:** DNA Tech India ₹1,652 incl. GST ([link](https://www.dnatechindia.com/pms5003-pm2.5-air-quality-sensor-buy-in-india)), Hubtronics ₹1,499 + GST ([link](https://hubtronics.in/sensors/pms5003-pm2.5-sensor)), Robocraze ₹2,022 ([link](https://robocraze.com/products/pms5003-pm2-5-air-quality-sensor-by-plantower)). SDS011 ~₹1,200-2,200 (electronicscomp ₹2,180, [link](https://electronicscomp.com/nova-pm-sensor-sds011-high-precision-laser-pm2.5-air-quality-detection-sensor)).
- Everything else is a local-shop estimate.

```parts
qty | item | est | note
1 | ESP32 dev board (WROOM-32, USB) | 0-500 | skip if the Diwali board (.127) is off the door or a loose spare is in the drawer (Pramod to confirm); else local
1 | GY-906 MLX90614 IR thermometer, BAA (90° wide view) | 600-1200 | local first; check "BAA" on the sensor can (BCC = 35°, DCI = 5°). The main trigger - buy this even if nothing else arrives
1 | PMS5003 PM2.5 sensor WITH its 8-pin cable/adapter | 1400-2100 | local if stocked, else ORDER ONLINE by Wed 25 Nov. SDS011 is an equal substitute. If it cannot arrive by Sat 28 Nov, build MLX-only and add this later (same board, same firmware)
1 | USB charger 5V 1A + USB cable | 0-200 | probably have (Pramod to check); one per board, never a shared GaN port (see voice-living-room in hardware.md)
1 | Small ABS project box (~85x55x30mm) | 120-200 | local; vent slots for the PM sensor; mounted beside the stove, out of the plume
1 | 4-core lead ~50cm + jumpers | 20-60 | local or Workbench stock; MLX on the lead, box to the side
# Fan on a socket: plug-in relay box (kandil build)
1 | 1-channel 5V relay module (KY-019 type, 10A 250VAC) | 60-100 | local; the kandil one is claimed by baby-monitor-charge-limit
1 | Junction box with screw lid | 60-150 | local
2 | WAGO 221 2-way lever connectors | 30-80 | local; neutral and earth through
1 | 3-pin 6A plug + socket, 1m 3-core cable | 100-200 | local; so the relay switches phase, not neutral
# Fan hard-wired: in-wall relay (later, with smart-switch-in-wall)
1 | HLK-PM01 5V supply, genuine Hi-Link | 180-195 | local; full list in smart-switch-in-wall.md
1 | 1-channel 5V relay module | 60-100 | local
1 | Fuse holder + T1A fuse, 5x20mm | 12-20 | local
```

**Cost detail:** **₹2,000-4,500** covers the sensor board (MLX90614 + PMS5003 + box + lead, ~₹2,100-3,700 including an ESP32 and charger if bought) plus the socket relay box (~₹250-530). With the Diwali ESP32 and a spare charger it is about ₹2,400-3,800. **Cheaper variant / weekend fallback: MLX-only**, ~₹750-1,500 with the Diwali ESP32 - catches every cooking session that lights a burner, but switches off as soon as the stove cools even if smoke lingers. **Cheapest:** a DS18B20 (~₹100) in the rising air instead of the MLX, accepting a 1-2 min lag.

**Effort detail:** **~8-12h over the weekend, then 2-3 short evenings.**
1. **Bench (Sat, 2-3h):** ESPHome YAML for mlx90614 (+ pmsx003 if here), build on the Mac, flash, add to HA. Hold the MLX over the hob with one burner and a pan: **the decisive test**. Incense stick for the PM sensor.
2. **Fan switch (Sun, 2-3h):** socket relay box from the kandil drawings, metered before mains; or deferred if hard-wired.
3. **Mounting (Sun, 2-3h):** **the phase that overruns** - the MLX's angle and height over the hob, out of the worst of the plume, a box spot beside the stove with a socket for the charger, and a lead that survives cleaning. Expect to re-aim it once after seeing data.
4. **HA (1-2h):** IR delta over room temperature, PM2.5 baseline, the on/off automation with the "on by automation" flag and the 5-min off delay, record-only first.
5. **Tuning (2-3 evenings over the next week):** read a week of real cooking, set thresholds, then let it switch. Plus the done-rules paperwork (hardware.md, dashboard tile, endpoints.toml, README) ~1h.

**When built (CLAUDE.md done-rules):** new `docs/hardware.md` entry for the board (and relay box), with HA name, area and tile; HA area **Kitchen** (user to confirm) and a tile on the Kitchen view in `home.yaml`, pushed with `ui_dashboard.py restore` and checked with `shot_dashboard.sh`; `endpoints.toml` entry for the ESPHome API (port 6053, as the kandil switch) - no MQTT unless that changes; `projects/kitchen-exhaust/README.md` with its first file and its line in the root `Readme.md`. Ask the `circuit-diagram` agent for the wiring before soldering.

#### Log
- 2026-11-24: recorded. MQ-2 rejected; PM2.5 + humidity-rise on an ESPHome ESP32 decided; not a gas-safety device. Repo check: no kitchen fan in HA (no Tinxy in the kitchen), Home dashboard has a Kitchen view (dishwasher only); Diwali ESP32 frees after 24 Nov, kandil relay already claimed. Set straight to Active (user) for the weekend of 28-29 Nov, parts permitting.
- 2026-11-24: design changed (user): main trigger is now an MLX90614ESF-BAA (90°) IR thermometer 60-70cm above the 3-burner stove, plus the PMS5003 for lingering smoke; on = stove hot OR PM high, off = stove cool AND PM normal ~5 min. Humidity and VOC dropped; per-burner thermistors, DS18B20 in the hot air (cheap fallback, 1-2 min late) and AMG8833 (overkill) rejected. MLX-only is the fallback if the PMS5003 is late.
