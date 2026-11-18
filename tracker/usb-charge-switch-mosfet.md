# USB charge switch (MOSFET): ATtiny85 + current sensor, silent P-channel switch
**Status:** Backlog
**Priority:** P3
**Cost:** ₹50-100
**Effort:** ~1 evening (2-3h), after the relay build

#### Open items
- [ ] **Together, after the relay build works:** pick the gate pin (see "Digispark pin trap") on the relay box's board before buying anything
- [ ] **Pramod:** buy the extra parts below when deciding to try it - ask the shop for a ready P-MOSFET module first
- [ ] **Together, at the bench:** swap the relay for the AO3401, flip the firmware's pin polarity, compare against the relay (heat, drop, standby draw)

**Why:** the silent version of "USB charge switch (relay): ATtiny85 + current sensor to stop charging when full". Split out on 2026-11-16 (user): "we will do relay for now, might try P-channel MOSFET (AO3401) later". It waits because the relay build comes first, not because anything blocks it.
**State:** idea, design decided in conversation 2026-11-16. Nothing bought. Everything except the switch is shared with the relay entry - read that one for the speaker logic, the threshold trap, the board choice and the phone notes.

#### What is the same as the relay build
- USB-A in and out, 5V only; INA219 high-side; Digispark ATtiny85, standalone logic, no Wi-Fi.
- Logic: charge on power-up; off when current stays under the threshold for 5 min; restart after ~48h or a button press.
- Threshold: the Portronics Apollo One is always on, so its "full" current must be measured with the USB tester first.
- **Reuses the relay box as-is:** board, INA219, breakouts, box, button, USB tester. Only the switch part changes.

#### Design (what differs)
```
charger 5V -> INA219 -> AO3401 source | drain -> USB socket +5V (VBUS)
                              gate -> ATtiny pin, 10k gate-to-source (holds it off)
GND and D+/D- pass straight through, never switched
```
- **High-side P-channel on VBUS only.** Pin LOW = charging on, pin HIGH (or floating) = off. Never switch ground with an N-channel low side: it breaks the USB ground and data reference.
- **Polarity is inverted vs the relay** (relay module is high-trigger): a firmware flag, nothing else changes in code.
- **Driven straight from the ATtiny** because the Digispark runs at 5V: gate at 5V = Vgs 0 = fully off. An ESP32's 3.3V pin could not turn it fully off without an extra transistor - one more reason the ATtiny suits this variant.
- **Boot is safe:** micronucleus waits ~5s on power-up with pins floating; the 10k pull-up keeps it off. Failure mode is off (no charging), same as the relay.
- **Body diode points the right way:** with source on the charger side, the AO3401's body diode cannot feed the device when it is off.

| | Relay | AO3401 |
|---|---|---|
| Noise | clicks twice per charge | silent |
| Draw while charging | coil ~70-90 mA | ~0 |
| Drop at 1 A | ~0 (contacts) | ~0.05 V (Rds(on) ~50-60 mOhm at Vgs -4.5 V) |
| Soldering | none (module) | SOT-23 onto an adapter board |
| Firmware | pin HIGH = on | pin LOW = on |

#### Digispark pin trap (decide before buying)
Found while writing this entry, 2026-11-16 - check against the actual clone board, revisions differ:
- **PB0 / PB2** are taken by the INA219 (I2C SDA / SCL).
- **PB3 / PB4** are the USB lines: each has a **3.6V zener** to ground, and PB3 also a 1.5k pull-up to 5V ([Instructables DIY Digispark parts](https://www.instructables.com/Digispark-DIY-The-smallest-USB-Arduino), [circuitdigest](https://circuitdigest.com/microcontroller-projects/attiny85-ic-programming-through-usb-using-digispark-bootloader)). A gate on one of these is clamped near 3.6V when "off": Vgs ~-1.4V, past the AO3401's -0.5 to -1.3V threshold, so it **never fully turns off**. Fine for the relay module, wrong for the MOSFET.
- **PB1** has the onboard LED + resistor to ground ([best-microcontroller-projects](https://www.best-microcontroller-projects.com/attiny85.html)): with only a 10k pull-up, the LED drags the gate low and turns charging **on during the boot wait**.
- **PB5** is reset on most Digisparks.
- **Options:**
  - **Recommended: gate on PB1, onboard LED (or its resistor) removed.** Keeps the direct drive; the button stays on PB3.
  - **NPN driver (BC547 + 1k base) from PB4:** gate pulled to 5V by the 10k, NPN pulls it low. Polarity back to HIGH = on. Two more parts.

#### Rejected
- **N-channel on the ground side:** breaks USB ground/data reference.
- **Through-hole P-MOSFETs a shop stocks (IRF9540, IRF4905):** not logic-level at a 5V gate drive (thresholds -2 to -4V, Rds(on) specified at -10V); they would run warm or half-on. Only worth it if the shop has a logic-level one.

#### Readymade alternatives
- A ready P-MOSFET switch module, if a local shop has one, removes the SOT-23 soldering; check its gate pull-up and that it switches the high side.
- Same verdict as the relay entry otherwise: no off-the-shelf box measures USB current and cuts at "full".

#### Parts
Extra to the relay entry's parts only; resistors are assumed owned (`docs/hardware.md` parts on hand).
```parts
qty | item | est | note
5 | AO3401 P-channel MOSFET (SOT-23, -30V -4A) | 15-30 | local - a few spares, they are cheap and easy to kill while soldering; estimate
3 | SOT-23 to DIP adapter board | 30-60 | local - skip if the shop sells a ready P-MOSFET module; estimate
2 | 10k resistor | 0-2 | local, likely in the drawer - gate-to-source pull-up
1 | BC547 NPN + 1k resistor | 5-10 | local - only for the NPN-driver option (gate on PB4); skip if the gate goes on PB1
```
**Cost detail:** ~₹50-100 on top of the relay build (estimates, not fetched listings); ~₹20 if the drawer has 10k resistors and the shop has a module.

**Effort detail:** ~2-3 h, after the relay build works.
- Pin choice and LED removal on the Digispark: 0.5 h.
- Soldering the AO3401 to its adapter and fitting it in the box: 1-1.5 h - **the phase that overruns** (SOT-23 is tiny; the mechanical side always does on this repo).
- Firmware polarity flag and reflash: 15 min.
- Bench compare against the relay with the USB tester: 0.5 h.

#### Log
- 2026-11-16: split from the relay entry (user): relay first, this one to try later. Recorded the high-side AO3401 design and found the Digispark pin trap (zener-clamped USB pins, LED on PB1).
