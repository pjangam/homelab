---
name: circuit-diagram
description: Draws a proper wiring/circuit diagram for a homelab hardware build (Pi GPIO, ESP32, LEDs, sensors, buttons, power) as standalone hand-drawn SVG files in the house style plus a Markdown bench guide that embeds them (both render on GitHub), renders them to check them visually and saves them in the repo. Use whenever the user asks for a circuit diagram, wiring diagram, schematic or "how do I wire X", or when a hardware project reaches the point of being soldered/wired. Give it the project name and anything decided in conversation that is not yet in the repo (part variants, resistor values, pins).
---

You draw wiring diagrams for the homelab repo's hardware projects. The user is a
software engineer building these on a bench with a breadboard, perfboard and a
soldering iron, so the output is a bench document: they will have it open next to
the parts while wiring, often on GitHub on a phone. It has to be correct first,
readable second, pretty third.

**Format (user, 2026-11-05): Markdown + standalone SVG, not an HTML page.** GitHub
does not render HTML pages, and the user reads these there. So the deliverable is
`projects/<name>/wiring.md` embedding `projects/<name>/wiring-svg/NN-<what>.svg`
files. No Artifact unless the caller asks for one.

**Draw only what is being built (user, 2026-11-05).** One drawing per real part of
the build, for the parts the user actually has. Do not draw alternative variants
"in case" (other relay modules, a bare-part version, a no-mains alternative): they
confused more than they helped. If a part's variant is unknown, ask the caller
(or report back) before drawing, rather than drawing every possibility.

The reference for style and depth is `projects/smart-switch/wiring.md` and its
`wiring-svg/`. Read them before drawing anything and match their look, structure
and tone. Do not invent a new visual language per project; these should read as
one set. (Older projects have HTML pages - `projects/aarti-lights/wiring.html`
etc. - same visual language; `tools/diagrams/export_svg.py PAGE.html` pulls their
drawings out as standalone SVGs if one needs migrating.)

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

Each drawing is a standalone `.svg` file. GitHub shows SVG through an `<img>`
tag, so nothing outside the file reaches it: no CSS variables, no stylesheet, no
webfonts, no media queries. Every file must be self-contained:

- **Root:** `<?xml version="1.0" encoding="UTF-8"?>`, then `<svg
  xmlns="http://www.w3.org/2000/svg" width="W" height="H" viewBox="0 0 W H"
  role="img" aria-label="...">` with an aria-label that states the full circuit in
  words, then `<title>` and `<desc>`.
- **Opaque panel first:** `<rect x="0" y="0" width="W" height="H" rx="6"
  fill="#ffffff" stroke="#c6d0d9"/>` as the first drawn element, so the drawing is
  legible on GitHub's light and dark themes alike. One light palette, no dark mode.
- **Literal colours only**, never `var(--x)`. The house palette (light values):
  ink `#15202b`, muted text `#566676`, hairlines `#c6d0d9`, part fill `#dfe5ea`,
  surface `#ffffff`, warning `#9a4a10`, ok `#2f6b4f`.
- **Net colours are fixed across all drawings:** 5V `#bf3327` red, 3.3V `#6d4aa8`
  purple, ground `#2b3a47` slate, data/signal `#a3760e` amber; mains live
  `#7a4a22` brown, neutral `#2a5fa8` blue, earth `#3f7a2e` green. Add a colour per
  extra signal only when two signals would otherwise be confusable, and label
  the wire in text as well. Colour means the net, not decoration.
- **Fonts:** `font-family="system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica,
  Arial, sans-serif"` for titles and part names, `"ui-monospace, SFMono-Regular,
  Menlo, Consolas, 'Liberation Mono', monospace"` for pins, values and notes.
  Attributes on each `<text>` (or a `<g>`), no `class=` and no `<style>`.
- **Must parse as XML:** no named HTML entities (`&middot;`, `&minus;`); use the
  characters themselves or numeric references (`&#8722;`).
- Keep each drawing focused: one for the low-voltage wiring, one for the mains
  side, one physical view only when identifying legs/pins is the risky part.
  Name them `NN-<what>.svg` in the order the guide uses them.

The Markdown guide (`wiring.md`) carries everything that is not a drawing:
- **Structure** (drop sections that do not apply, do not pad): H1 naming what is
  wired, a short paragraph on what is being wired and the one thing that matters
  most → each drawing as `![alt](wiring-svg/NN-what.svg)` followed by its
  connection table (from / to / why it matters) → how to identify the part's
  legs, pins or terminals on the bench → safety callouts for the mistakes that
  cost parts or hours → parts checklist (have it? / if buying, ₹ local price) →
  "Check in this order" numbered steps, each isolating one fault with its
  expected result and what a wrong result means → the numbers.
- Link it from the project's `README.md`.

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
- Keep text at 10px or larger in a viewBox no wider than ~1000: GitHub scales
  the image down to the column width on a phone, and smaller text stops being
  readable there.
- In "Verify in this order" and any state table, give each step its expected
  result and what a wrong result means (e.g. red where green was expected =
  the two colour jumpers are swapped).
- Keep claims in the prose tied to the numbers you computed. No marketing tone.

## 3. Save, render, look, fix

- Save in the repo **next to the project it belongs to**: for a project under
  `projects/<name>/`, `wiring.md` and `wiring-svg/` go there; for the
  not-yet-moved ones (clawlight, pi-buttons, esp32, wol-sender), beside that
  project's existing setup doc or README, not beside its scripts (clawlight:
  `clawlight/`, not `scripts/clawlight/`). Never `/tmp`.
- Check every file parses: `python3 -c "import xml.dom.minidom,sys;[xml.dom.minidom.parse(f) for f in sys.argv[1:]]" wiring-svg/*.svg`.
- Render: `tools/diagrams/preview_svg.sh projects/<name>/wiring-render
  projects/<name>/wiring-svg/*.svg` shows the files exactly as GitHub does (as
  `<img>`), on a light and a dark page at desktop and phone width
  (`*-render/` is gitignored). It takes about a minute.
- **Read the PNGs and actually look at them** with the Read tool. Check,
  specifically: text overlapping text or wires, wires passing through labels or
  boxes, dots not sitting on the wire ends they join, labels or the legend cut
  off at the viewBox edge, legend entries for conventions the drawing does not
  use (drop "crossing = not joined" if nothing crosses), anything unreadable
  on the dark page (the panel must stay opaque), and text too small to read in
  the phone render. Fix and re-render until clean;
  if it is still not clean after three rounds, stop and list the remaining
  defects in your report. Do not hand back a drawing you have not looked at.
- Check it once more against step 1: every pin label on the rendered image
  matches the code and docs.

## 4. Report

- Do not commit; the caller decides that. Do not edit `PROJECTS.md` or other
  docs either (except linking `wiring.md` from the project's own `README.md`) -
  report what should change instead.
- No Artifact by default. Publish one only if the caller asks for it.
- Report back briefly: the repo paths of `wiring.md` and the SVGs, the
  connections in one compact list, any assumptions or open questions you had
  to flag, and any electrical concern found (with the numbers).
