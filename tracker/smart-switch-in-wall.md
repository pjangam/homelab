# In-wall smart switch (Tinxy replacement, phase 2)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹0-1,700 (reflash an installed Tinxy ₹0, test unit ~₹1,200; DIY 4-switch board ~₹1,600-1,700)
**Effort:** ~1 evening (reflash test) to ~2 weekends (DIY box)

#### Open items
- [ ] **Pramod, after Diwali:** with the MCB off, open one installed Tinxy: note the model (is it the 4N with fan regulator?) and photograph the board's chip for Claude
- [ ] **Together, after that:** try ESPHome on one Tinxy 4N (an installed one, or a ~₹1,200 test unit), then decide: reflash the rest, or build the DIY in-wall box (design and drawings already in `projects/smart-switch/wiring.md` section 6)

**Why:** same as "In-house smart switch to replace Tinxy" (Done 2026-11-05): the Tinxy switches route every click through `mqtt.tinxy.in`, leaking usage and failing in an ISP outage.
**State:** the plug-in prototype works (ESP32 + KY-019 relay module, ESPHome, LAN-only, Tinxy-style switch logic) and runs the akash kandil: `projects/smart-switch/`. What the wall box adds: its own mains-to-5V supply instead of a USB charger, a fuse, a back-box-sized enclosure with mains and low voltage kept apart, and sensing the existing 230V rocker so the wall switch keeps working. Reuse the firmware (`projects/smart-switch/esphome/`). Both options are drawn in `projects/smart-switch/wiring.md` section 6 (2026-11-05, design study: shared 5V module + fuse + relay, then A's opto module or B's cut phase loop); bench-check the opto module's OUT level (many pull low when on, so the firmware may need `inverted` too).
- **Cost check (user, 2026-11-05):** Tinxy's 4-node module with fan speed regulator is ~₹1,200, about ₹300 a switch; the DIY box (see Cost below) can't beat that and can't do fan speed (a relay is on/off only), so it doesn't win on price or features. It wins only on staying off the cloud. That reopens **reflashing a Tinxy 4N with ESPHome**: ESPHome's device list has a config for the Tinxy 4N fan regulator (ESP8266 sending serial to a relay MCU). Before designing a DIY box, open one installed unit (MCB off) or buy one 4N, check the chip, and try ESPHome on it. Newer Tuya-based boards may not flash. Decide after that.
  - Candidate test unit: Amazon ASIN B08KZMB7HD, "Tinxy 4 Node with Fan Regulator" (Tinxy official store; the listing shows no chip or price to a fetch). ESPHome device page: https://devices.esphome.io/devices/Tinxy-4N-Fan-Regulator (ESP8266 `esp01_1m`, UART to the relay/fan MCU, 3-speed fan component). Tinxy's own forum hosts the flashing guide: https://forum.tinxy.in/t/guide-how-to-flash-esphome-on-tinxy-4n-with-fan-regulator/1209. **Flashing needs:** desolder the W2/W3 bridges, a USB-TTL adapter (CH340G recommended) on RXD/TXD/3.3V/GND, hold reset while plugging in, esptool at 460800 (the web flasher fails at 115200), flash quickly (the ESP reboots without the MCU's PWM on GPIO14), then re-solder W2/W3. So: a soldering iron and a ~₹100-150 USB-TTL adapter.
- **The wall switch is the open question** (user, 2026-11-05: the prototype's rocker carries 3.3V DC, a wall switch carries 230V AC, so the prototype is not yet a Tinxy replacement). Either way phase goes straight to the relay's COM, not through the switch, and the firmware's Tinxy-style logic stays the same. Two ways to read the switch:
  - **(A) Keep it on AC, sense it with an isolated AC optocoupler module** (the Tinxy way, confirmed from Tinxy's wiring diagram 2026-11-05: L and N feed the module, L also goes through the wall switch into a "TO SWITCH" terminal, load comes off the module; https://user-images.githubusercontent.com/69470381/233136920-ca890a9b-f521-4597-8cf3-79327926a38e.jpeg; and the plan): phase -> wall switch -> module input -> neutral; module output to a GPIO. The board's wiring stays normal-looking 230V, so a later electrician can't get it wrong. Costs a small module; its output pulses at mains frequency, so the firmware needs a ~50-100ms `delayed_off` filter.
  - **(B) Make the wall switch a low-voltage "rocker"**: disconnect it from mains completely and wire it GPIO-to-GND. Cheapest, and the firmware already works. Traps: Indian switchboards loop the phase from switch to switch, so that loop must be broken for this switch only; 3.3V and 230V then share a box (keep them separated, mains-rated wire); and anyone who later "fixes" the switch back onto phase puts 230V into the ESP32. Label it if chosen.
#### Cost (2026-11-05)
Quoted prices incl. 18% GST, from search snapshots on 2026-11-05: robu.in refuses automated fetches (HTTP 403), so robu prices are from search snippets (two from its mirror/staging pages) and the rest from other Indian stores. Recheck on the site before buying; local shop first.

#### Parts
Each `#` line is one option, so the dashboard can add just that one to the shopping list.

```parts
qty | item | est | note
# Next: ESPHome reflash test on a Tinxy 4N
1 | Tinxy 4 Node with Fan Regulator (Amazon ASIN B08KZMB7HD) | 1200 | online, Tinxy store - test unit; skip if testing on an installed one
1 | USB-TTL adapter | 0 | have one (6-pin with CTS/RTS, recorded 2026-11-17) - skip; set it to 3.3V. Plus a soldering iron if none
# DIY one switch (option B)
1 | ESP32 devkit, WROOM-32 38-pin | 384 | have spares - skip
1 | 1-channel 5V relay module | 59 | have one (on the kandil) - skip unless it is still in use there
1 | HLK-PM01 5V supply, genuine Hi-Link | 180-195 | local - sits on 230V in the wall, no clones (hubtronics 195, vishaworld 180)
1 | 5x20mm PCB fuse holder | 7 | local
1 | Fuse T500mA-T1A, 5x20mm | 5-10 | local
1 | Enclosure that fits the back box | 50-150 | local
1 | Wire, lever connectors, sleeving | 30-60 | local
# DIY 4-switch board (option A)
1 | ESP32 devkit, WROOM-32 38-pin | 384 | have spares - skip
1 | HLK-PM01 5V supply, genuine Hi-Link | 180-195 | local
1 | 4-channel 5V relay module, optocoupler, with JD-VCC jumper | 159 | ₹159 incl. GST (user, 2026-11-27). Remove the JD-VCC jumper: VCC to the ESP32's 3.3V, JD-VCC to 5V, so a 3.3V pin switches the optos cleanly. Usually low-trigger (ESPHome `inverted: true`). 4 coils on = ~300-350mA; check the board has isolation slots
4 | 220V AC optocoupler module, 1 channel | 772 | local (robu 193 each) - active-low: OUT to GND when 230V is present
1 | 5x20mm PCB fuse holder + T500mA-T1A fuse | 15 | local
1 | Enclosure and wire | 80-210 | local
```

| Option | Total | Per switch |
|---|---|---|
| DIY one switch (option B) | ~₹750-870; ~₹290-430 with the ESP32 and relay on hand | same |
| DIY 4-switch board (option A) | ~₹1,600-1,700 | ~₹400-430 |
| **Tinxy 4-node with fan regulator** | **~₹1,200** | **~₹300, with fan speed** |

#### Log
- 2026-11-05: split out of "In-house smart switch to replace Tinxy" when the kandil prototype was marked Done.
- 2026-11-05: options A/B drawn (`wiring.md` section 6). Cost check: Tinxy's 4N with fan regulator at ~₹1,200 beats the DIY box on price and fan speed; DIY wins only on staying off the cloud. Next is testing an ESPHome reflash of a Tinxy 4N (ESP8266, documented on devices.esphome.io and Tinxy's forum) before any DIY build.
- 2026-11-27: option A's relay board priced at ₹159 (4-channel opto version, user), with the 3.3V wiring note. Budget lines added.
