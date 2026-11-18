# USB charge switch (relay): ATtiny85 + current sensor to stop charging when full
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** source the ATtiny85 parts (option "Board: ATtiny85 (Digispark)" in the parts block) plus the shared parts and the relay
- [ ] **Pramod, next local shop visit:** USB-A female breakout (out of stock on Robu, 2026-11-17; the 2 male ones are already on hand). Fallback: Amazon ASIN B0F3FK753T (QBM), ₹125 for a pack of 2 (~₹62 each, one 1-star review, 2026-11-17)
- [ ] **Claude, after the parts are in hand:** ATtiny85 firmware (Arduino: INA219 cutoff, 48h restart, button), wiring diagram (circuit-diagram agent). No code before then (user, 2026-11-16)
- [ ] **Together, at the bench:** measure the speaker's "full" current with the USB tester, then fix the threshold in the firmware

**Why:** the Portronics Apollo One (xero's Bluetooth speaker since 2026-11-14) stays on its charger, and a Li-ion battery held at 100% ages faster. Neither the speaker nor its Bluetooth link reports a battery level (checked from xero, the phone and the MacBook on 2026-11-14), so a plain timer or a smart plug can only guess when it is full. Building it on the 5V USB side, not as a mains plug, keeps it away from 230V.

#### Design
```
USB charger 5V -> [INA219 current sensor] -> [relay] -> USB cable -> device
                          |                     |
                          +---- ATtiny85 -------+   (standalone; ESP32-C3 + Wi-Fi is the fallback)
```
- **Switch: 5V relay module** (user, 2026-11-16): no soldering, clicks only twice per charge. The silent P-channel MOSFET (AO3401) version is its own entry, "USB charge switch (MOSFET)", to try later.
- **Board: ATtiny85 (Digispark)**, being tried (user, 2026-11-16); ESP32-C3 kept as the fallback option.
- **Speaker logic (on the board, decided 2026-11-16):** charge on power-up; off when the current stays under a threshold for 5 min (full); restart after a fixed interval (~48h) or a button press. Works with Wi-Fi and HA down.
- **Wi-Fi is for debugging only** (user, 2026-11-16): current graph, tuning the threshold/interval, a charge-done notification. Not needed for the box to do its job.
- **Threshold trap:** the speaker is always on (xero's speaker), so "full" is its running draw, not ~0 mA. Measure it before fixing the number (~50 mA is a guess).
- **Phone logic (HA):** off at 80% from the Companion app's battery sensor; current is no use there, a phone in use keeps drawing when full.
- **Placement:** wall-mounted near the speaker.

#### Parts
```parts
qty | item | est | note
1 | INA219 current sensor module | 150-250 | local - measures the device's charging current (up to 26V, ~3.2A)
1 | USB-A male breakout board | 0 | have 2 (recorded 2026-11-17) - skip; input from the charger, check it passes D+/D- through
1 | USB-A female breakout board | 25 | local - output to the device's cable; must pass D+/D- through
1 | Small ABS project box (~85x55x30mm) | 120-200 | local - wall-mounted near the speaker
1 | 6x6mm tactile push button | 5-10 | local - "charge now"
1 | USB-A power meter / tester (voltage + current display) | 200-350 | local - to measure the speaker's "full" current before fixing the threshold; useful for any USB build after
1 | 5V relay module (1 channel, high-trigger like the KY-019) | 60 | local - check the stash first; a low-trigger opto module would switch on at boot
# Board: ATtiny85 (Digispark)
1 | Digispark ATtiny85 USB dev board (micronucleus bootloader) | 120-200 | local - chosen to try (user, 2026-11-16); flashes over its own USB, no programmer. PB3/PB4 are the USB lines (button OK on PB3), PB1 has the onboard LED
# Board: ESP32-C3 SuperMini
1 | ESP32-C3 SuperMini (headers soldered) | 250 | local or hubtronics/makerbazar - Robu R183884 out of stock (2026-11-16); or the free Diwali ESP32. Wi-Fi for debugging/tuning
```

#### Phones and fast charging
**Decided 2026-11-14 (user): USB-A, 5V only.** Phones charge at plain 5V through it; no Power Delivery, so the switch and breakouts only ever see 5V.

| Charging | Through the box? |
|---|---|
| Plain 5V USB | Yes; slower, gentler on the battery |
| Quick Charge over USB-A | Only if the breakouts pass D+/D- through; OnePlus's own fast charging needs its own cable, so expect normal speed |
| USB-C Power Delivery (9-20V) | Only with USB-C in and out that passes CC; the INA219 copes to 26V, the switch must too |

- Many phones can cap charging themselves (iPhone 80% limit, Android "Protect battery"); then the box mainly helps the speaker.

#### Log
- 2026-11-14: idea from the speaker-to-Bluetooth session; confirmed the speaker reports no battery level. Recorded as backlog.
- 2026-11-14: build decided: USB-A in and out, 5V only (user).
- 2026-11-16: board options compared: ATtiny85 (no Wi-Fi, needs a programmer, reflash to tune) vs ESP32-C3 SuperMini vs Wemos D1 mini. Decided the charge logic runs standalone on the board, Wi-Fi only for debugging (user). Recommended the C3 anyway: same price class, USB-C flashing with the existing ESPHome setup, tuning without reflashing.
- 2026-11-16: **trying the ATtiny85 this time** (user): Digispark board, no Wi-Fi; restarts charging on its own timer (~48h, internal clock ±10% is fine) or the button. Added to the parts block as a board option; user sources parts before any code.
- 2026-11-16: split in two (user): this entry is the **relay** build, done first; the P-channel MOSFET (AO3401) build is a separate entry for later. Renamed from "USB charge switch: ESP32 + current sensor to stop charging when full"; MOSFET option moved out of the parts block.
