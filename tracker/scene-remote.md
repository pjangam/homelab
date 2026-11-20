# Bedroom remote and satellite buttons (media, volume, white noise, oju sleep, talk)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹200-1,500
**Effort:** ~4 evenings + 2-3 weekends (30-40h)

#### Open items
- [ ] **Pramod:** think the plan over before any build starts (user, 2026-11-18)
- [ ] **Pramod:** decide the SHT40's home (Pi or bedroom satellite, `humidity-dry-mode.md`): it decides whether GPIO19/21 are free for volume up / talk
- [ ] **Pramod:** multimeter (continuity beep): map each key pad to the back's TX test points, which tells matrix or direct wiring; measure the PCB and the battery bay, room for a 21 x 18mm board
- [ ] **Pramod:** pick the remote's board (XIAO ESP32-C6 recommended, C3 the alternative) and power (LiPo pouch on the board, or 2 Panasonic NiMH + buck-boost)
- [ ] **Pramod:** buy the parts once the plan is settled (block below; buttons local, XIAO and LiPo online)
- [ ] **Together, before phase 3:** bench-test ESP-NOW receive on the bedroom satellite with voice running: `espnow` + `power_save_mode: none`, wake word still works, free heap stays healthy
- [ ] **Claude:** run `architecture-review` on this plan before phase 1 starts

**Why:** raised 2026-11-18 while bouncing ideas for the bedroom ESP32. The Pi's GPIO buttons (`pi-gpio-buttons.md`, Done) were built on the Pi only because no ESP32 was at hand. The bedroom voice satellite is now an ESP32 in the same room, moving next to the bed, so the buttons can move to it, gain media and volume keys, and later a handheld remote made from an old Fire TV Stick remote shell (sturdy case, printed symbols).
**State:** plan researched 2026-11-18, nothing built or bought. Wired buttons first (phase 1), box moves by the bed (phase 2), remote last (phase 3). The pending bedroom flash (SHT40 block, extender-first WiFi, play button, voice-reply events) is separate and can go first. The remote's two firmware unknowns are answered below: both work, each needs a small lambda, no custom component.

#### Decisions (2026-11-18, user)
- **The Pi stays** on the bedroom pegboard, visible from the work chair: white noise, Spotify, WoL and the clawlight LED stay on it.
- **WoL stays on the Pi.** Battery power is in the plans, and a battery-backed device never loses power in an outage, so it never reboots to send the wake packet. The bedroom satellite is not a WoL candidate (`wol-to-esp32.md`).
- **The bedroom satellite moves next to the bed**, beside the extender `dlink_pramod_bed_room`; its firmware prefers that network, router as fallback (committed, not flashed).
- **Buttons, not IR or Bluetooth.** Everything reaches HA over the WiFi path the satellites already use.
- **Oju awake button dropped** (rarely used). The scene stays in HA for the app and voice.
- **"Start playlist" and play/pause are one button:** nothing playing in the room starts its playlist, otherwise pause/resume.
- **Each room controls its own player:** bedroom -> the Pi's spotifyd and "Pi Speaker Volume"; living room -> xero's spotifyd and "xero Speaker Volume". HA already knows a satellite's room from its area.
- **Bedroom box drops the LED strip and the speaker amp:** replies already play on the Pi's speaker; with a remote in hand nobody watches the box. The living room board keeps its strip.
- **The remote has no mic:** its Select key tells the bedroom satellite to start listening, and the satellite's mic hears you.

#### Phase 1: wired buttons on the satellites
Every button from its pin to GND, internal pull-up, no resistor.

| Button | Bedroom GPIO | Living room GPIO | Firmware file |
|---|---|---|---|
| Play/pause (starts the playlist if idle) | 23 | 23 | common (already there as "Play button") |
| Previous | 13 | 13 | common |
| Next | 14 | 14 | common |
| Volume up | 19 | - (optional) | bedroom |
| Volume down | 22 | - (optional) | bedroom |
| Start white noise | 16 | - | bedroom |
| Stop white noise | 17 | - | bedroom |
| Oju sleep scene | 18 | - | bedroom |
| Talk (push-to-talk, no wake word) | 21 | - (optional) | bedroom |

Bedroom board after phase 1:

| Use | GPIO |
|---|---|
| Mic (INMP441) | 25, 32, 33 |
| Onboard status LED | 2 |
| 9 buttons | 13, 14, 16, 17, 18, 19, 21, 22, 23 |
| Free | 4 (was the LED strip), 26, 27, 34-39 (input only, no pull-ups) |
| Avoid | 12 (pull-up can stop boot), 6-11 (flash), 0/5/15 (boot pins) |

- **If the SHT40 stays on the satellite** it keeps 21/19: talk and volume up move to 26/27.
- **Firmware:** each press fires an HA event (like `esphome.play_button`), not an entity HA has to watch; HA automations do the rest, per room by the device's area.
- **Volume:** steps of ~5% on the room's existing slider; the bedroom slider's 93% cap stays (the Pi's jack clips above). Holding a key repeats every ~300ms. On the Pi, white noise and Spotify share that one volume control, so the keys move both.
- **LED strip removal is bedroom-only:** `num_leds` is already per board, but the strip and its effects live in `voice-satellite-common.yaml`, so removing it from one board needs a per-board switch or moving the strip block into the living room file.
- **Parts:** 9 buttons for the bedroom, 2 more for the living room (play button already planned).

#### Retiring the Pi's buttons (end of phase 1)
- Wire the new buttons and test them for a few days **before** unwiring the Pi's: the user's mother and the house help use the white-noise buttons daily.
- Then on the Pi: disable and remove `white-noise-buttons-mqtt` and `scene-buttons-mqtt` (system units, sudo from a real terminal), unwire GPIO17/18.
- In HA: remove `white_noise_button_start`/`_stop`, `scene_button_oju_sleep`/`_awake`.
- Update `docs/hardware.md` (Pi and satellite entries), `scripts/pi-buttons/README.md`, and `projects/endpoints/endpoints.toml` if it lists the buttons' MQTT topics.

#### Phase 2: move the bedroom box by the bed
- Needs the pending flash first (extender-first WiFi). Then check HA's `WiFi network` sensor shows `dlink_pramod_bed_room`.
- Placement: away from the Pi's white-noise speaker (the hiss drowns commands, `voice-control.md`); within reach of a mains socket.

#### Phase 3: handheld remote from the gen-1 Fire TV Stick remote
- **Shell:** gen-1 Fire TV Stick remote (2014, model W87CUN stick; Bluetooth, no mic, 2 x AAA). Keep its PCB as the contact surface for the rubber keys; cut out or lift its chip and wire the key pads (a row/column matrix) to the ESP32. ESPHome `matrix_keypad`. No published teardown or dimensions found: the bay and PCB are measured by hand (open item).
- **Board:** Seeed XIAO ESP32-C6 recommended, XIAO ESP32-C3 the alternative (comparison below). No mic either way; an S3 only if a mic ever goes into the remote.
- **Radio:** ESP-NOW to the bedroom satellite, which turns each key into the same HA event as its wired button. The remote has no `wifi:` block at all: it never joins the network, so a press costs a boot and one packet, not a 2-5s WiFi join. No OTA either: flash over USB-C.
- **Sleep:** deep sleep between presses, rows held low while asleep, columns as pulled-up wake inputs, so any key wakes it. After a press it stays awake ~2s for follow-up presses (volume taps, a held key), then sleeps.

| Key (gen-1 remote, confirm on opening) | Action |
|---|---|
| Play/Pause | Play/pause (playlist if idle) |
| Rewind / Fast-forward | Previous / next |
| Ring up / down | Volume up / down |
| Ring right / left | White noise start / stop |
| Select | Talk (bedroom satellite listens) |
| Home | Oju sleep scene |
| Back, Menu | Spare |

| XIAO ESP32-C3 pin | GPIO | Matrix line (provisional, set by the remote's PCB) |
|---|---|---|
| D0-D3 | 2, 3, 4, 5 | Columns 1-4 (the only deep-sleep wake pins; GPIO2 is a strapping pin) |
| D4-D6 | 6, 7, 21 | Rows 1-3 |
| D7-D10 | 20, 8, 9, 10 | Free (8/9 are boot pins) |

| XIAO ESP32-C6 pin | GPIO | Matrix line (provisional) |
|---|---|---|
| D0-D2 | 0, 1, 2 (LP GPIO) | Columns 1-3 (the only exposed wake pins) |
| D3-D7 | 21, 22, 23, 16, 17 | Rows 1-4, one free |
| D8-D10 | 19, 20, 18 | Free |

- **The remote's 11 keys fit a 3 x 4 or 4 x 3 matrix.** If its PCB has 4 columns and the board is the C6, swap rows and columns in firmware (the wake lines are whichever side has 3), or OR the 4th column into a wake pin with a Schottky diode.

#### Feasibility checks (2026-11-18)
- **ESP32-C3 wake on any of several pins: yes, but not from ESPHome's YAML.**
  - ESPHome's `deep_sleep` takes one `wakeup_pin` on the C3; its multi-pin `esp32_ext1_wakeup` excludes the C2 and C3, and `ANY_LOW` is listed for C5/C6/C61/H2/P4/S2/S3 only ([deep_sleep docs](https://esphome.io/components/deep_sleep/)). The C3 code path passes a one-bit mask, `1ULL << pin`, to `esp_deep_sleep_enable_gpio_wakeup` ([source](https://api-docs.esphome.io/deep__sleep__esp32_8cpp_source)).
  - The IDF call itself takes a bitmask of GPIO0-5 with one level ([ESP-IDF C3 sleep modes](https://docs.espressif.com/projects/esp-idf/en/v5.0/esp32c3/api-reference/system/sleep_modes.html)), so a short `on_shutdown` lambda calling it with the 4 column bits (and no `wakeup_pin` in YAML) does it. No custom component.
  - **Fallback with stock YAML:** OR the columns into one wake pin with Schottky diodes (BAT43/BAT54, not 1N4148: its 0.7V drop sits right at the C3's input-low threshold of ~0.8V).
  - Seeed confirms only D0-D3 wake the XIAO C3 ([Seeed wiki](https://wiki.seeedstudio.com/XIAO_ESP32C3_Getting_Started/)).
- **ESP32-C6: native in ESPHome.** `esp32_ext1_wakeup` with `ANY_LOW` works on the C6 ([deep_sleep docs](https://esphome.io/components/deep_sleep/)); wake pins are LP GPIO0-7, and the XIAO C6 exposes only 0-2 ([Seeed wiki](https://wiki.seeedstudio.com/xiao_esp32c6_getting_started/)).
- **Rows held low in deep sleep: needs a lambda on either chip.** `matrix_keypad` drives rows only while scanning, and ESPHome has no YAML option to hold arbitrary output pins through deep sleep. Set the rows low and call `gpio_hold_en()` per row plus `gpio_deep_sleep_hold_en()` before sleeping; release with `gpio_hold_dis()` at boot. Bench-test it: the only tested reference found is Arduino, not ESPHome.
- **Reference build:** [WLED-ESPNow-Remote](https://github.com/DedeHai/WLED-ESPNow-Remote) is an ESP32-C3 button-matrix remote over ESP-NOW with deep sleep and an awake window after a press; Arduino code, but the same shape. No ready-made ESPHome config for matrix + deep sleep + ESP-NOW was found ([HA forum, 4x3 keypad](https://community.home-assistant.io/t/4x3-telephone-keypad-repurposing/823058) left deep-sleep wake unsolved).
- **ESP-NOW receive on the original ESP32 satellite: supported, with one setting.**
  - ESPHome's `espnow` component landed in 2025.8.0 ([changelog](https://esphome.io/changelog/2025.8.0/)); the repo's image is 2026.9.1. It runs alongside `wifi:`, but then the channel is the AP's and the component's `channel` option cannot be set ([espnow docs](https://esphome.io/components/espnow/)).
  - **Set `power_save_mode: none` on the satellite.** ESPHome's default on ESP32 is `LIGHT` ([wifi docs](https://esphome.io/components/wifi/)), and modem sleep loses unicast ESP-NOW packets, broadcasts excepted ([esp32.com report](https://esp32.com/viewtopic.php?p=70762)). The satellite is on mains, so the extra draw does not matter.
  - **Memory:** default 250-byte payload buffers are small next to the voice pipeline, but the satellite is a no-PSRAM ESP32 already running `voice_assistant`. Unmeasured: the bench test in Open items.
  - **Traffic is unencrypted** (the component skips ESP-NOW encryption). Filter `on_receive` by the remote's MAC and accept only known key codes; fine for media keys, not for anything security-relevant.
- **Channel:** the extender is a single-radio 2.4GHz repeater with a 2.4GHz backhaul (`docs/hardware.md`), so it must sit on the router's channel: **6, fixed since 2026-11-06** (`docs/wifi.md`). The satellite falling back from extender to router does not change the channel, and the remote can hard-code channel 6.
- **Gen-1 Fire TV Stick remote:** the 2014 stick (84.9 x 25 x 11.5mm, shipped with 2 AAA) came with a Bluetooth, no-mic remote ([CNX Software, 2014](https://www.cnx-software.com/2014/10/28/amazon-introduces-39-fire-tv-stick-to-compete-with-chromecast-roku-streaming-stick/)). No teardown, remote dimensions or official key list found online; the key table above is from memory of that remote and is checked when it is opened.

#### Board choice: XIAO ESP32-C6 vs C3

| | XIAO ESP32-C6 | XIAO ESP32-C3 |
|---|---|---|
| Multi-key wake | ESPHome YAML (`esp32_ext1_wakeup`, `ANY_LOW`), 3 exposed pins | lambda or diode-OR, 4 pins (D0 is a strapping pin) |
| Deep sleep (Seeed figure) | 15µA | 44µA |
| Antenna | onboard ceramic (U.FL optional) | **external FPC antenna** on U.FL, which has to fit inside the shell |
| LiPo charger | yes | yes (380mA) |
| Size | 21 x 17.8mm | 21 x 17.5mm |
| India price (listings, 2026-11-18) | ₹533-720 (Robocraze ₹720, IndiaMART ₹533) | ₹500-750 (Robotools ₹619, ThinkRobotics ₹750) |

- **C6 recommended:** native wake config, a third of the sleep current, and no antenna to route inside a slim shell. The C3 only wins if the PCB has 4 columns and 3 rows that cannot be swapped.
- **Rejected: ESP32-C3 SuperMini** (₹250, in other entries' parts lists): poor onboard antenna, no LiPo charger, and its always-on power LED has to be removed for battery use.

#### Power: two options, both fit the 2 x AAA bay

| Option | Chain | Charging | Usable energy at 3.3V |
|---|---|---|---|
| A: 2 Panasonic NiMH + buck-boost | cells (2.0-2.8V) -> TPS63020/63802 module -> XIAO **3V3** pin | the existing NiMH charger | ~1.6Wh (2 x 800mAh x 1.2V, ~85% converter) |
| B: Li-ion on the XIAO (recommended) | ~300mAh LiPo pouch, or a 10440 plus a dummy cell -> XIAO battery pads | USB-C on the remote | ~1.0Wh (300mAh x 3.7V, ~90% LDO) |

- **Why B:** no converter to fit or buy, the XIAO charges it, and 300mAh LiPo cells are stocked in India at ₹115-200 where a 3.3V TPS63020 module was out of stock at the one Indian listing found.
- **Why still A:** the cells are already owned and swappable, and ~60% more energy.
- **Neither works without a converter for NiMH:** 2 cells (2.0-2.8V) are below the ESP32's 3.0V minimum; 3 fresh-charged cells (up to ~4.2V) exceed the 3V3 pin's 3.6V.

#### Battery life (estimate, 2026-11-18)

| Draw | Assumption | Per day |
|---|---|---|
| Deep sleep, C6 | 15µA board + a few µA held pins | ~0.5mAh |
| Deep sleep, C3 | 44µA | ~1.1mAh |
| Buck-boost quiescent (option A only) | ~25-50µA module | ~0.6-1.2mAh |
| Presses | 30 wake sessions a day, each ~0.5s boot + 2s awake with the radio on at ~80mA | ~1.7mAh |

- **Option B, C6:** ~2.2mAh/day -> a 300mAh pouch lasts **~4 months**.
- **Option A, C6:** ~3.4mAh/day against ~500mAh at 3.3V -> **~4-5 months**, minus NiMH self-discharge.
- **The awake window decides it, not sleep current:** 2s on vs 5s on is the difference between ~4 and ~2 months. Measure the real wake time and sleep current with a USB meter on the bench before closing the case.
- The earlier figure of ~0.13mAh per press assumed a WiFi join (3s at ~150mA); with ESP-NOW and no WiFi a session is ~0.05mAh.

#### Readymade alternatives
- **Amazon.in Bluetooth media remotes (the user's starting point):** cheap and finished, but Bluetooth pairs to one host and speaks HID, which would need the Pi or an ESPHome BT proxy to turn keys into HA actions. Ruled out by the WiFi-only decision; no prices taken.
- **Zigbee remotes (IKEA-style):** good battery life, but no Zigbee coordinator here; adding one is a bigger project than this remote.
- **The rebuild wins on** a sturdy shell with printed symbols already owned, and keys mapped straight to this house's scenes.

#### Traps
- **Never put more than 3.6V on an ESP32's 3V3 pin.** 3 AAA (any chemistry) or a full Li-ion on 3V3 can kill the chip.
- **3 alkaline AAA on a dev board's VIN** runs only while fresh (>~4.3V, AMS1117 dropout) and its regulator burns ~5mA asleep: bench tests only. 3 NiMH on VIN does not work at all (~2.6V out).
- **NiMH + buck-boost on the XIAO's 3V3:** never plug USB in with the cells in, or two supplies feed one rail. Flash with the cells out.
- **3.3V buck-boost modules are scarce in India:** most TPS63020 listings are the 5V version, which is useless here without changing its feedback resistor.
- **10440 Li-ion:** one cell plus a dummy, never two in series (7.4V); never in the NiMH charger. No protected 10440 found at an Indian shop: online only, and many listings overstate capacity.
- **LiPo pouch:** kapton-wrap it, nothing may pinch it when the case closes; use a cell with a protection board (PCM).
- **ESP-NOW channel:** the remote transmits on a hard-coded channel 6. If an Airtel firmware push resets the router to Auto channel, the remote goes silent while everything else keeps working. `docs/wifi.md` already says to re-check the channel after a push; the remote is one more reason.
- **ESP-NOW on the satellite with the default power save** drops unicast packets: `power_save_mode: none`.
- **Rows not held in deep sleep** means no key wakes the remote: the hold lambda is not optional.
- **C3 only: GPIO2 (D0) is a strapping pin.** A key held on that column during a wake reset could upset boot; put the column least likely to be held there, or use 3 columns.
- **Push-to-talk does not beat the white-noise hiss** - it only skips the wake word. Moving the box away from the speaker is what helps the command itself.

#### Parts
```parts
qty | item | est | note
# Phase 1: wired buttons
11 | 12mm momentary push button | 150-300 | local; 9 bedroom + 2 living room (prev/next; play button already planned). Estimate, not a fetched listing
# Phase 3 remote, power option B: LiPo (recommended)
1 | Seeed XIAO ESP32-C6 | 530-720 | online: Robocraze ₹720 incl. GST, IndiaMART ₹533 (2026-11-18 listings); local shops rarely stock XIAO. C3 instead: ₹500-750
1 | 300mAh 3.7V LiPo pouch with PCM (402535 or similar, under ~40 x 25 x 5mm) | 115-200 | online: Robocraze 300mAh cells ₹114-143 (2026-11-18), size code varies, check dimensions against the bay. Or a protected 10440 + AAA dummy cell, ~₹150-300, estimate, online only
2 | Schottky diode BAT43/BAT54 | 10-20 | local; only if the matrix has more columns than wake pins
# Phase 3 remote, power option A: NiMH
1 | Seeed XIAO ESP32-C6 | 530-720 | as option B
1 | Buck-boost 3.3V module (TPS63020 or TPS63802), thumbnail-sized | 300-450 | online: Robozar 3.3V TPS63020 ₹413, out of stock (2026-11-18); 5V versions do not fit. Uses the Panasonic NiMH cells already owned
```

#### Cost detail
- **Header total ₹200-1,500:** phase 1 buttons ₹150-300, plus the remote at ₹650-950 (option B) or ₹830-1,170 (option A).
- **Cheapest:** phase 1 alone, ₹150-300; phases 2 and 3 are free until the remote is built.
- **Already owned, not priced:** the Fire TV remote, the Panasonic NiMH cells and charger, wire, solder, kapton.

#### Effort detail
| Phase | Hours | Notes |
|---|---|---|
| 1: wired buttons + HA automations | 8-10 (3 evenings) | firmware events, per-room play/volume automations, LED strip split out of the common file, days of parallel running, retiring the Pi's units |
| 2: box by the bed | 2-3 (1 evening) | after the pending flash; placement against the hiss |
| 3a: bench (decisive, first) | 4-6 | ESP-NOW on the satellite with voice running; XIAO on a breadboard with a 2 x 2 test matrix: wake lambda, row hold, sleep current, wake-to-HA latency |
| 3b: open the remote, map the matrix | 3-5 | trace rows/columns on its PCB, cut the chip out |
| 3c: fit board, battery, wires in the shell | 8-12 | **will overrun:** mechanical fit in a slim shell, as every mechanical step on this repo has |
| 3d: firmware polish + battery check | 3-5 | awake window, key repeat, a week of real use with a USB meter reading |

#### Log
- 2026-08 to 09: Pi GPIO buttons built and done (`pi-gpio-buttons.md`); this file was the "ESP32 remote for places away from the Pi" follow-up.
- 2026-11-18: plan written after a brainstorm on the bedroom ESP32 (user): buttons move from the Pi to the bedroom satellite (oju awake dropped), media and volume keys added for each room, play/pause merged with start playlist, IR and Bluetooth dropped for WiFi/ESP-NOW, bedroom box loses its LED strip and amp, later a Fire TV Stick remote rebuild. User to think it over before building.
- 2026-11-18: WoL stays on the Pi (user): battery power is in the plans, and a battery-backed board never loses power in an outage, so it never reboots to send the wake packet. Bedroom-satellite WoL wording removed from phase 2.
- 2026-11-18: researched by `idea-dump`: C3 multi-pin wake needs a lambda (ESPHome YAML takes one pin), the C6 does it natively, so the XIAO ESP32-C6 is now the recommended board; satellite ESP-NOW needs `power_save_mode: none`; channel is fixed at 6 for router and extender; LiPo (option B) now recommended over NiMH + buck-boost, whose 3.3V module was out of stock in India; prices from 2026-11-18 listings; effort raised to ~4 evenings + 2-3 weekends with a battery-life budget.
- 2026-11-19: remote found at home (user). **It has a mic button**, so it is a later Alexa Voice Remote, not the 2014 no-mic one this plan assumed: the shell section and key table need re-checking against it once open. Case looks glued; a teardown video of the same remote (youtu.be/6OinNv8L1vk) opens it with a visiting card slid in around all sides. Not opened yet after ~30min.
- 2026-11-20: remote **opened** (user, photos of both PCB sides). Board `30-002573 REV 01`. 12 keys, silkscreened: SW500 VOICE, SW504 UP, SW511 DOWN, SW507 LEFT, SW505 RIGHT, SW506 SEL, SW503 BACK, SW502 HOME, SW501 MENU, SW510 REWIND, SW509 PLAY, SW508 FFW - no volume keys, so the ring's up/down stay volume; VOICE is the natural Talk key, freeing Select. Key pads are round plated discs (metal domes or carbon pills on top; check when the keypad is off). Back: one QFN SoC, a MEMS mic at the top, battery contacts J301-J304, many labelled test points (TX100-TX110, TX400-TX521) and edge pads BON100-BON109 - candidate solder points for the key lines, to be mapped by continuity.
