---
name: circuit-diagram
description: Draws a proper wiring/circuit diagram for a homelab hardware build (Pi GPIO, ESP32, LEDs, sensors, buttons, power) as an HTML page with hand-drawn SVG in the house style, renders it to check it visually, saves it in the repo and publishes it as an Artifact. Use whenever the user asks for a circuit diagram, wiring diagram, schematic or "how do I wire X", or when a hardware project reaches the point of being soldered/wired. Give it the project name and anything decided in conversation that is not yet in the repo (part variants, resistor values, pins).
---

You draw wiring diagrams for the homelab repo's hardware projects. The user is a
software engineer building these on a bench with a breadboard, perfboard and a
soldering iron, so the page is a bench document: they will have it open next to
the parts while wiring. It has to be correct first, readable second, pretty third.

The reference for style and depth is the "Aarti Strip Bench Wiring" artifact:
https://claude.ai/artifact/9htRRMwTKPzQxMk5Fmqbmb. **Read it with the Artifact
tool (`action: "read"`) before drawing anything**, and match its look, structure
and tone. Do not invent a new visual language per project; these pages should
read as one set.

## 1. Gather the facts - never invent a pin

Every pin, GPIO number, resistor value and part variant on the page must come
from somewhere you can point to. Look in this order:

- What the caller told you (decisions made in conversation that the repo may
  not have caught up with yet - these win).
- The code that drives the hardware: pin constants, polarity flags
  (`COMMON_ANODE`, `active_high`), WLED/ESPHome configs.
- `docs/gpio_pinout.md` for the wol-sender Pi header, `docs/hardware.md`
  (gitignored, local only) for devices, addresses and what runs where.
- The project's `PROJECTS.md` entry (including its `parts` block) and its setup
  doc (`projects/<name>/*_setup.md`, `clawlight/README.md`, root
  `*_buttons_setup.md` etc.).

If sources disagree, or something needed is not decided (which leg is which,
resistor value, which GPIO), **do not guess silently.** Either draw the variant
the evidence favours and say so in a callout on the page and in your report, or
stop and report the open question back. A wrong pin on a confident-looking
diagram is worse than no diagram.

Do the electrical sanity pass while gathering, and put anything that matters on
the page:
- Logic levels: Pi and ESP32 GPIO are 3.3V, not 5V tolerant. 5V parts on a data
  line need thought.
- Current: compute LED current from supply, forward voltage and resistor
  (red ~2.0V, yellow-green ~2.1V, pure green/blue/white ~3.0V) and show the
  number. Keep a GPIO pin under ~16mA on a Pi, ~20mA on an ESP32.
- Pull-ups/pull-downs, shared grounds between separate supplies, decoupling
  and bulk capacitors, series resistors on data lines.
- ESP32 traps: strapping pins (GPIO0/2/12/15) and input-only pins (GPIO34-39).
  Pi traps: pins 27/28 (ID EEPROM), pins already claimed in `gpio_pinout.md`.
- Polarity of every polarised part (LED legs, electrolytic capacitors, supply).
- **Any bench test you suggest must be harmless if the user's guess is wrong**:
  always through a resistor, on 3.3V rather than 5V, never a bare wire from a
  supply pin to a leg. Say which pins not to use (e.g. Pi pins 2/4 are 5V).

## 2. Draw it

Load the `artifact-design` and `artifact-diagramming` skills first and follow
their page contract. On top of that, the house style:

- **Page structure** (drop sections that do not apply, do not pad):
  header with mono eyebrow (`Project · phase`), condensed H1 (two to four words),
  one-paragraph standfirst saying what is being wired and the one thing that
  matters most → "The whole circuit" SVG → connection table (from / to / why it
  matters) → how to identify the part's legs or polarity on the bench →
  callouts for the mistakes that cost parts or hours → "Verify in this order"
  numbered checks where each check isolates one fault → footer with the
  project's current state and the file/script that drives it.
- **Fonts and tokens:** IBM Plex Sans / Sans Condensed / Mono from Google Fonts.
  Colours as CSS custom properties on `:root`, redefined for dark mode under
  `@media (prefers-color-scheme: dark)` with `:root:not([data-theme="light"])`
  and again under `:root[data-theme="dark"]`. Every SVG `fill`/`stroke` uses
  `var(--token)`, never a raw hex, so both themes work.
- **Net colours are fixed across all pages:** `--w5v` red for 5V, `--w33` purple
  for 3.3V, `--wgnd` slate for ground, `--wdata` amber for data/signal. Add a
  token per extra signal only when two signals would otherwise be confusable
  (e.g. a red-channel and green-channel line: name them for what they carry).
  Colour means the net, not decoration. When a signal's natural colour is
  already taken by a net (a red-channel line next to `--w5v`), give it its own
  token with a clearly different shade and label the wire in text as well.
- **Symbols:** resistor as a zigzag with its value above (`220R`), LED as a
  triangle-and-bar with the anode/cathode side labelled, capacitor as two plates
  with the polarity stripe noted, boards and modules as labelled rectangles with
  pins as dots on the edge carrying both the physical pin number and the GPIO
  name (`pin 33 · GPIO13`). For a Pi, draw the relevant part of the 40-pin
  header in its real two-column physical layout (odd pins in the left column,
  as in `docs/gpio_pinout.md`) so the user can count pins on the actual board;
  mark unused neighbours as hollow, and say how to orient the board: pin 1 is
  the square pad at the end away from the USB ports, pin 40 is nearest them.
- **Wiring conventions:** filled dot = joined, plain crossing = not joined, and
  include that legend. Orthogonal wire runs. Arrows only for signal direction,
  and say so. Rails for shared power/ground when there are more than two taps.
- **Real-world view where it helps:** if leg identification is the risky part
  (LED leg lengths, flat edge, strip pads, module silkscreen), add a second
  small SVG showing the physical part, not just the schematic.
- Wrap each SVG in `<div class="scroller">` with a `min-width` so it scrolls
  inside its box on a phone instead of shrinking to unreadable; give it
  `role="img"` and an `aria-label` that states the full circuit in words.
- In "Verify in this order" and any state table, give each step its expected
  result and what a wrong result means (e.g. red where green was expected =
  the two colour jumpers are swapped).
- Keep claims in the prose tied to the numbers you computed. No marketing tone.

## 3. Save, render, look, fix

- Save the page in the repo **next to the project it belongs to**: for a
  project under `projects/<name>/`, put it there; for the not-yet-moved ones
  (clawlight, pi-buttons, esp32, wol-sender), put it beside that project's
  existing setup doc or README, not beside its scripts (clawlight: `clawlight/`,
  not `scripts/clawlight/`). Name it `<thing>_wiring.html`. Never `/tmp`.
- Render it: `tools/diagrams/render.sh <page.html>` writes PNGs to
  `<page>-render/` (gitignored): full page at desktop and phone width in light
  and dark, plus each SVG alone at 2x. It takes about a minute (Playwright is
  installed from npm on every run). Layout problems it can detect are printed
  as `WARNING` lines in its output.
- This render-look-fix loop replaces the artifact-design skill's single look;
  where the two disagree, this file wins.
- **Read the SVG PNGs and actually look at them** with the Read tool. Check,
  specifically: text overlapping text or wires, wires passing through labels or
  boxes, dots not sitting on the wire ends they join, labels or the legend cut
  off at the viewBox edge, legend entries for conventions the drawing does not
  use (drop "crossing = not joined" if nothing crosses), anything unreadable in
  dark mode, and whether the render
  WARNING lines report horizontal page scroll. Fix and re-render until clean;
  if it is still not clean after three rounds, publish anyway and list the
  remaining defects in your report. Do not publish a diagram you have not
  looked at.
- Check it once more against step 1: every pin label on the rendered image
  matches the code and docs.

## 4. Publish and report

- Before publishing, `Artifact` `action: "list"` to see whether this project
  already has a wiring artifact. If so, read it and update it in place with its
  `url` rather than creating a second one. Otherwise publish new with a fitting
  favicon (e.g. 🔌💡) and a one-sentence description.
- Do not commit; the caller decides that. Do not edit `PROJECTS.md` or other
  docs either - report what should change instead.
- Report back briefly: the artifact URL (and that the page source should be
  linked from the project's setup doc / `PROJECTS.md` entry), the repo path of the HTML, the
  connections in one compact list, any assumptions or open questions you had
  to flag, and any electrical concern found (with the numbers).
