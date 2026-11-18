# Big wall display (HUB75 LED matrix) - clock, and whatever else is worth a glance
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** decide the shape - clock-first (buy one) or dashboard-first (build the matrix)
- [ ] **Together:** if dashboard, list what actually deserves wall space (a 64x32 grid holds very little text)

**Why:** asked whether a big screen could be made into a wall clock with an ESP32. It can, but not any screen, and as a *clock alone* it loses to a ₹1500 shop clock. It only earns its place if it also shows what nothing else in the house shows at a glance: clawlight, healthcheck state, AC, power-on-battery.
**State:** idea only, and expected to sit here a long time - in the user's own words, it is not a priority and it would not help day to day. Options are priced (cheapest real build: a 64x32 HUB75 panel on the freed aarti board and supply, ~₹1000-1800).

#### Verdict to record
If it is only a clock, buy one. Build the matrix only if it is a *homelab display* - the data is already there (`homelab/healthcheck/overall`, `clawlight/state`, the AC and power entities all publish over MQTT), so the work is a renderer, not plumbing. This overlaps two entries already here: **shopping list display** (which wants e-paper, not this) and **consolidated status dashboard** (which this would be the physical face of). Decide them together rather than buying two screens.

**Why this will sit here a long time, in the user's own words (2026-09-19): it is not a priority and it would not help day to day.** That is the honest reason, not effort and not parts - a clock is a solved problem in this house, and a nicer-looking one changes nothing about a day. Worth saying out loud so it is not picked up later on the assumption that something was blocking it. Recorded because it costs nothing to keep and the pixel maths is the part nobody wants to redo.

#### What an ESP32 can actually drive
No HDMI, ever - a TV or monitor needs a Pi or mini PC, not an ESP32. That leaves three kinds of screen:
- **HUB75 LED matrix panels** - the right answer for a wall clock. Bright enough to read across a room in daylight, fast, and cheap per area. `ESP32-HUB75-MatrixPanel-I2S-DMA` drives them; a 64x32 P3 panel is 192x96mm (about the footprint of a paperback) and a 64x64 is 192x192mm. Panels chain, so area scales linearly with cost.
- **E-paper** - gorgeous, no glow, readable in sun, but refreshes in seconds, so a second hand is out and even a minute tick is a visible flash. It suits the **shopping list display** idea above far better than a clock, and a 7.5" 800x480 raw panel plus the ESP32 driver board lands around ₹6000-9000 - for a screen the size of a paperback.
  - **E-paper plus a small lamp, suggested 2026-09-18, is a better idea than it sounds.** E-paper is reflective, like paper: in a dark room it shows nothing at all, which is the usual reason it loses to a glowing display. A ~1W lamp over it fixes exactly that, and keeps what makes e-paper worth having - it stays paper-like by day and is lit only when someone is there. 1W continuous is ~0.7 kWh/month, around ₹5, so even left on it is nothing; on a PIR it is less.
  - **Wash it, don't spot it.** A single 1W LED aimed at a flat panel gives a hotspot and glare at the viewing angle. A short warm-white strip in an aluminium channel along the top, lipped forward like a picture light, lights it evenly - the same trick as a painting light, and it looks deliberate on a wall.
  - **Switch it, don't leave it on:** a PIR or HA presence turning it on for ~30s costs nothing to add and matches the house's "no light nobody is looking at" habit. An LDR can set the level so it does not glare at night.
  - **Watch the driver board's spare pins.** Waveshare's e-paper ESP32 board is built for the panel and does not leave many GPIOs free; a lamp MOSFET plus a PIR may want a plain ESP32 driving the panel instead. Check before buying.
  - **It does not fix the refresh limits** - still no seconds, still ghosting on a partial refresh. This makes e-paper viable *at night*, not suddenly a clock.
- **SPI/RGB LCDs** - 3.5" to 7", fine on a desk, not a wall.

#### Prices (checked 2026-09-18)
India, incl. GST: a 64x64 P3 panel is **₹2269** at Hubtronics (192x192mm), a 64x32 P3 panel is **₹600-1200** (192x96mm), and a MAX7219 4-in-1 red dot matrix (32x8) is about **₹260**.

#### Parts
**The first version of this entry priced two 64x64 panels at ₹6000-7000, and that is not worth it** - rejected 2026-09-18. The cheap configurations are the ones to consider, and they only work because the aarti lights board and its 5V 4A supply are freed after the festival:

```parts
qty | item | est | note
1 | HUB75 P3 64x32 panel | 600-1200 | online - 192x96mm, full colour, digits up to ~7cm tall
1 | ESP32 dev board | 0-600 | reuse the aarti lights board; only a purchase if that stays in service
1 | 5V 3-4A power supply | 0-600 | reuse the aarti supply; one sparse-content panel draws well under its rating
1 | Frame + acrylic diffuser | 300-600 | local - a bare panel looks like a component, not a clock
```

**So ~₹1000-1800 built from freed parts, ~₹2500 buying everything new.** The even cheaper option is a **MAX7219 chain at ₹260-520 plus a board** - a 32x8 or 64x8 red ticker that scrolls time and one line of status for well under ₹1000. It is red-only, so it cannot use colour as the signal the way clawlight and the health LED do, and its digits are ~3cm tall against ~7cm on the panel.

#### The zero-cost option: digits from the leftover WS2812B
Recorded 2026-09-19, and honestly the least likely to get built. The aarti reel is 60 LEDs/m, so the ~2m spare is about 120 pixels. Two layouts fit:
- **True seven-segment** - 3 pixels per segment, 21 per digit, 4 digits plus a 2-pixel colon = **86 pixels** (~1.4m), digits ~10cm tall. At 4 px/segment it is 114 pixels, which fits 2m with nothing spare.
- **Zigzag matrix** - 7 rows of 16 laid behind a diffuser, **112 pixels**, ~27cm x 10cm, digits drawn in software with a 3x5 font, ~7cm tall.

**The matrix is the better build despite using more pixels:** 6 cut-and-solder joints against ~27 for the segment version (each 3 wires, so 80-odd joints), one sheet of diffuser instead of a divider per segment, and it can show anything - icons, scrolling text - rather than only digits. It also reuses the aarti renderer's exact shape. Cap brightness in software: 112 pixels at full white would pull ~6.7A, digits at a sane level closer to 0.8A.

**Both builds fit on the one reel (corrected 2026-09-19).** The pegboard clawlight needs about **0.5m, ~30 pixels**, not the whole spare - so roughly **90 pixels** are left for digits. That changes which layouts are on the table:
- **Seven-segment `HH:MM` at 86 pixels still fits**, with four to spare. Tight, and it is the joint-heavy build.
- **The 16-wide matrix (112) no longer fits.** A stacked one does: `HH` over `MM`, 6 columns by 11 rows = **66 pixels**, portrait instead of landscape, ~10cm wide and ~18cm tall.
- **Measure the actual leftover before trusting any of this** - 120 pixels is inferred from the reel being 60/m, not counted.

#### Log
- 2026-09-18: asked whether a big screen could be made into a wall clock with an ESP32. Prices checked; the first version of this entry (two 64x64 panels at ₹6000-7000) rejected in favour of the cheap configurations. E-paper plus a small lamp suggested.
- 2026-09-19: zero-cost WS2812B digits option recorded, then corrected the same day - the pegboard clawlight only needs ~30 pixels, so both builds fit on the one reel, but the 16-wide matrix no longer does. User said it is not a priority and would not help day to day.
