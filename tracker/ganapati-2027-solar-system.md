# Ganapati 2027: solar system / general relativity decoration
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Together, mid-2027 (close to the festival):** pick one of the Ganapati 2027 ideas (this, spiral discs, or any added later); if this one, fix the makhar size, grid resolution and pixel count
- [ ] **Pramod, by July 2027:** order anything long-lead (this year's shortlist lesson)

**Why:** next year's makhar theme, picked while this year's sound-reactive strip was still up. The solar system as spacetime curvature - planets orbiting in a warped grid - is a decoration and a physics demo at once, and it is the kind of thing visiting kids will actually queue up for. Noted roughly a year ahead, which is the point: this year's shortlist was decided partly by what could still arrive in time.
**State:** idea only, nothing decided. Ganesh Chaturthi 2027 is around early September - confirm the date before planning backwards from it.

#### Three builds, and they combine well
- **(A) The spandex gravity well.** Stretchy fabric over a hoop, a heavy mass in the middle, marbles rolled in to spiral around it. The classic, and the only one that is *interactive* - people will play with it for far longer than they will look at a light. Cheap (fabric, a hoop, ball bearings), no electronics at all, and it needs someone to re-launch marbles, which at a festival is a feature rather than a chore.
- **(B) A WS2812 grid as the curved spacetime sheet.** Strips laid in a grid behind the makhar, rendered as a warped mesh with planets moving along their orbits, light bending near the sun, and a ripple when two masses merge. This is the one that reuses everything already learned: ESP32 + WLED, and the aarti Tier 3 renderer's shape (`aarti-render.py` streams every pixel over realtime UDP, with WLED's own boot preset as the fallback if xero is down). The work is the renderer, not the wiring.
- **(C) Planets as glowing spheres, using the pixel strings.** WS2811 bullet-pixel strings are made for this: one pixel inside each ping-pong ball or frosted acrylic sphere, one data line for the whole set, each planet its own colour and brightness. Hangs in front of, or through, the grid in (B) and gives the display depth that a flat strip cannot.

#### Be honest about the physics
Someone will ask. The rubber-sheet demo is the standard picture and it is *wrong* in an interesting way: it explains gravity by using gravity (the marbles fall because the Earth pulls them down), and what it really draws is closer to a potential well than curved spacetime. Two cheap additions fix it:
- **A gravitational lens.** A shaped acrylic or glass lens - the base of a wine glass is the classic stand-in - held over a picture or over the LED grid distorts the image the way a real mass distorts light. That *is* general relativity, not an analogy, and it is the cheapest true demo of the three.
- **A sign, and someone able to explain it.** "The sheet is an analogy; the light bending is the real thing" turns the flaw into the interesting part.

#### Constraints already known from this year
- **Mains only, no UPS**, and the renderer on xero means the display dies if xero does - hence a WLED boot preset that stands on its own.
- **Power budget:** current cap in software, strip power never through a breadboard or dupont wires, and size the supply from the pixel count (the aarti entry has the real numbers).
- **Everything local.** Last year's build was the first fully cloud-free light in the house; keep that.
- **A soldering iron, decent power supply and 2m of spare WS2812B are already owned,** so only the new parts count.

#### Rough shape of the spend
The fabric-and-marbles half is a few hundred rupees. The lit half depends entirely on pixel count - a grid dense enough to read as a curved mesh is the one line that can quietly run into thousands, so decide the grid size early and price *that* before anything else. Pixel strings and spheres are the cheap, high-impact part.

#### Log
- 2026-09-18: noted, roughly a year ahead.
- 2026-11-06: a second 2027 makhar idea competes for the same backdrop: "Ganapati 2027: counter-rotating spiral discs (kinetic backdrop)". A separate idea, not combined with this one.
- 2026-11-07: both stay candidates for 2027; user may add more options. Final pick deferred to mid-2027, close to the festival.
