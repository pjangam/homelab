# Bedroom remote and satellite buttons (media, volume, white noise, oju sleep, talk)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹200-1,600 (₹200-300 for the wired buttons; the Fire TV remote rebuild is the rest)
**Effort:** ~2 evenings + 1-2 weekends (wired buttons 2 evenings; remote 1-2 weekends)

#### Open items
- [ ] **Pramod:** think the plan over before any build starts (user, 2026-11-18)
- [ ] **Pramod:** decide the SHT40's home (Pi or bedroom satellite, `humidity-dry-mode.md`): it decides whether GPIO19/21 are free for volume down / talk
- [ ] **Pramod:** open the gen-1 Fire TV Stick remote, measure the battery bay's depth, photograph the PCB (key pads reachable? shield or glue?)
- [ ] **Pramod:** pick the remote's power: 2 Panasonic NiMH + buck-boost, or a Li-ion cell on the XIAO
- [ ] **Claude:** before building, check ESPHome can wake an ESP32-C3 from deep sleep on any of 4 pins, and that ESP-NOW receive runs alongside the voice satellite on the original ESP32
- [ ] **Claude:** run `architecture-review` on this plan before phase 1 starts

**Why:** raised 2026-11-18 while bouncing ideas for the bedroom ESP32. The Pi's GPIO buttons (`pi-gpio-buttons.md`, Done) were built on the Pi only because no ESP32 was at hand. The bedroom voice satellite is now an ESP32 in the same room, moving next to the bed, so the buttons can move to it, gain media and volume keys, and later a handheld remote made from an old Fire TV Stick remote shell (sturdy case, printed symbols).
**State:** plan only, nothing built or bought. Wired buttons first (phase 1), box moves by the bed (phase 2), remote last (phase 3). The pending bedroom flash (SHT40 block, extender-first WiFi, play button, voice-reply events) is separate and can go first.

#### Decisions (2026-11-18, user)
- **The Pi stays** on the bedroom pegboard, visible from the work chair: white noise, Spotify, WoL and the clawlight LED stay on it.
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
- Placement: away from the Pi's white-noise speaker (the hiss drowns commands, `voice-control.md`); on mains, not the UPS (keeps the WoL-backup option in `wol-to-esp32.md` open).

#### Phase 3: handheld remote from the gen-1 Fire TV Stick remote
- **Shell:** gen-1 Fire TV Stick remote (user believes gen 1: smaller, no mic). Keep its PCB as the contact surface for the rubber keys; cut out or lift its chip and wire the key pads (a row/column matrix) to the ESP32. ESPHome `matrix_keypad`.
- **Board:** Seeed XIAO ESP32-C3 (21 x 17.5mm), no mic needed. An S3 only if a mic ever goes into the remote.
- **Radio:** ESP-NOW to the bedroom satellite, which turns each key into the same HA event as its wired button. ~0.3s from press to action, versus 2-5s to wake and join WiFi.
- **Sleep:** deep sleep between presses; the 4 matrix columns on the C3's wake-capable pins (GPIO2-5), rows held low while asleep, so any key wakes it.

| Key | Action |
|---|---|
| Play/Pause | Play/pause (playlist if idle) |
| Rewind / Fast-forward | Previous / next |
| Ring up / down | Volume up / down |
| Ring right / left | White noise start / stop |
| Select | Talk (bedroom satellite listens) |
| Home | Oju sleep scene |
| Back, Menu | Spare |

| XIAO pin | GPIO | Matrix line (provisional, set by the remote's PCB) |
|---|---|---|
| D0-D3 | 2, 3, 4, 5 | Columns 1-4 (deep-sleep wake) |
| D4-D6 | 6, 7, 21 | Rows 1-3 |
| D7-D10 | 20, 8, 9, 10 | Free (8/9 are boot pins) |

**Power: two options, both fit the 2 x AAA bay.**

| Option | Chain | Charging | Energy |
|---|---|---|---|
| 2 Panasonic NiMH + buck-boost | cells -> TPS63020/63802 module -> XIAO **3V3** pin | the existing NiMH charger | ~1.9Wh |
| Li-ion on the XIAO | 10440 (AAA-size, plus a dummy cell) or a ~300mAh LiPo pouch -> XIAO battery pads | USB-C on the remote | ~1.1-1.3Wh |

Rough battery life with deep sleep: ~0.13mAh per press if it joined WiFi (3s at ~150mA), far less over ESP-NOW; weeks to months either way.

#### Traps
- **Never put more than 3.6V on an ESP32's 3V3 pin.** 3 AAA (any chemistry) or a full Li-ion on 3V3 can kill the chip.
- **3 alkaline AAA on a dev board's VIN** runs only while fresh (>~4.3V, AMS1117 dropout) and its regulator burns ~5mA asleep: bench tests only. 3 NiMH on VIN does not work at all (~2.6V out).
- **NiMH + buck-boost on the XIAO's 3V3:** never plug USB in with the cells in, or two supplies feed one rail. Flash with the cells out.
- **10440 Li-ion:** one cell plus a dummy, never two in series (7.4V); never in the NiMH charger.
- **LiPo pouch:** kapton-wrap it, nothing may pinch it when the case closes; use a protected cell.
- **ESP-NOW channel:** the remote must transmit on the satellite's WiFi channel. If the satellite falls back from the extender to the router and they use different channels, the remote goes silent. Fix the channel on both, or have the remote scan.
- **Push-to-talk does not beat the white-noise hiss** - it only skips the wake word. Moving the box away from the speaker is what helps the command itself.

#### Parts
```parts
qty | item | est | note
# Phase 1: wired buttons
11 | 12mm momentary push button | 150-300 | local; 9 bedroom + 2 living room (prev/next; play button already planned). Estimate
# Phase 3 remote, power option A: NiMH
1 | Seeed XIAO ESP32-C3 | 450-700 | estimate; local first, else Robu/ThinkRobotics
1 | Buck-boost 3.3V module (TPS63020 or TPS63802) | 200-450 | estimate; must be thumbnail-sized to fit beside the board. Uses the Panasonic NiMH cells already owned
# Phase 3 remote, power option B: Li-ion
1 | Seeed XIAO ESP32-C3 | 450-700 | estimate
1 | 10440 Li-ion cell (protected) + AAA dummy cell, or ~300mAh LiPo pouch (402535) | 150-300 | estimate; charges on the XIAO over USB-C
```

#### Log
- 2026-08 to 09: Pi GPIO buttons built and done (`pi-gpio-buttons.md`); this file was the "ESP32 remote for places away from the Pi" follow-up.
- 2026-11-18: plan written after a brainstorm on the bedroom ESP32 (user): buttons move from the Pi to the bedroom satellite (oju awake dropped), media and volume keys added for each room, play/pause merged with start playlist, IR and Bluetooth dropped for WiFi/ESP-NOW, bedroom box loses its LED strip and amp, later a Fire TV Stick remote rebuild. User to think it over before building.
