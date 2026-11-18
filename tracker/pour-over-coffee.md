# Automatic pour-over coffee (dose by weight, timed spiral pour, bell at the end)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹3,500-6,500
**Effort:** ~4-6 weekends (30-45h)

#### Open items
- [ ] **Pramod:** if picked up, start with the water half - a pump into a cup on a load cell, checking the pump's hot-water rating and pour accuracy

**Why:** seen 2026-10-12 in an [Instagram reel](https://www.instagram.com/reel/DeW8QpPs0S4/) of a DIY machine that grinds and pours. The user wants the pour-over part only, so a good cup happens without standing over the kettle. Captured quickly and on purpose: a rough budget only, with no deep research done.
**State:** idea only, nothing built. Scope decided 2026-10-12; feasible (a known build); rough budget **₹3,500-6,500** and effort **30-45h**. Nothing planned.

#### Scope (decided 2026-10-12)
No grinder and no water heating. **Hopper 1** takes pre-ground coffee, and the machine drops an exact weight (e.g. 15g) into the dripper cone. **Reservoir 2** takes water the user has already heated, and the machine pumps measured amounts on a pour schedule (a bloom, then pulses, e.g. the 4:6 method) in a circular or spiral motion. It **rings a bell** when the brew timer ends.

#### Feasibility
**Yes, it is a known build.** [An Instructables build](https://www.instructables.com/Automatic-Pour-Over-Coffee-Machine/) ([summary](https://jpralves.net/post/2023/05/25/automatic-pour-over-coffee-machine.html)) uses food-safe 12V peristaltic pumps with silicone tubing, plus an HX711 load cell in the drip tray. A [2020 Berkeley student build](https://edg.berkeley.edu/wp-content/uploads/2020/12/2020Fall_ME102B_borzillerievan.pdf) does the spiral pour from an ESP32. Notes for later, none of them researched in depth:
- **Water:** a peristaltic pump with silicone tubing keeps the hot water off the mechanism, but **confirm that the pump itself is rated for ~95°C** before buying it. Weigh the water with a load cell under the server rather than a flow meter. An unheated reservoir cools over a 3-4min brew, so it should be insulated, for example a thermos.
- **Spiral:** the simplest is probably a turntable rotating the dripper under a fixed off-centre spout, rather than an arm that moves.
- **Coffee dosing is the risky half:** an auger on a stepper, with a load cell for feedback, is the usual approach. Ground coffee clumps, sticks with static and bridges in the hopper. Build it last.
- **Bell:** a buzzer on the board, plus an MQTT message to HA or ntfy, as with the other ESP32 builds here. Firmware: **do not compile ESPHome on xero** (bad RAM, see the system incidents memory); build on the 2019 MacBook.
- **Board:** the aarti ESP32, packed away since 2026-10-02, is already claimed by the WoL-to-ESP32 move and named in the clock and wall-display entries. Assume a new ESP32 at ₹400-600.
- **Readymade:** the Fellow Aiden (~$365, about ₹30k landed if it can be imported at all) and xBloom do the water half and more. Neither turned up at an Indian retailer, and neither doses pre-ground coffee from a hopper.

#### Budget and effort
**Budget (rough estimate, not priced against listings):** **₹3,500-6,500.** That covers the ESP32, a 12V peristaltic pump, a stepper and driver for the turntable, a load cell and HX711, a 12V supply, a buzzer, and a frame or enclosure. The auger and its stepper add ~₹800-1,500 of that. **Without coffee dosing, around ₹2,500-4,500.**

**Effort detail:** **30-45h, about 4-6 weekends.** Water pour, scale and timer are 1-2 weekends; the spiral turntable is 1 weekend; coffee dosing is 2-3 weekends. The mechanical work (spout alignment, hopper and auger) will overrun, not the code.

#### Parts
Not priced per part yet: only the ESP32 has a figure; the whole build is budgeted at ₹3,500-6,500.

```parts
qty | item | est | note
1 | ESP32 devkit | 400-600 | the aarti ESP32 is claimed elsewhere, so a new one
1 | 12V peristaltic pump | | water dosing
1 | Stepper motor + driver | | turntable for the spiral pour
1 | Load cell + HX711 amplifier | | dose by weight
1 | 12V power supply | |
1 | Buzzer | | the "coffee's ready" bell
1 | Frame or enclosure | |
```

#### When built
Add the board to `docs/hardware.md` and its MQTT topic to `endpoints.toml`.
