# ESP32 UPS LED monitor
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** open the UPS case if possible; note the fastening (screws/glue), LED wiring (flying leads vs PCB-mounted) and pad spacing
- [ ] **Together:** from that inspection, decide whether option (D) is viable before buying anything

**Why:** `watchdog_power.sh` (below) currently guesses "90 minutes on battery is probably safe" before shutting down cleanly. The RouterUPS has 4 status LEDs (plug=mains, battery-full=on-battery-ok, lightning=charging, battery-low=critical) - reading the actual battery-low LED would replace the time guess with the UPS's own real signal.
**State:** LED behavior mapped. The 4 LEDs are only 5mm apart, too tight for discrete sensors, so five ways to read the UPS state have been weighed (see Options). (E) inline power sensor ranks strongest on paper, but the user is leaning toward (D), tapping the LED driver circuit, whose feasibility is unknown until the case is open. Nothing purchased yet.

#### Physical blocker
The 4 LEDs are only 5mm apart, too tight for discrete sensors + individual light shields (ruled out phototransistors/LDR modules + heat-shrink light shields - the sensor packages themselves don't fit at that pitch).

#### Options
- **Two options first considered:** (A) fiber-optic light pipes to relay light to normally-spaced sensors, or (B) a small camera reading pixel brightness at fixed, known coordinates in software (not image recognition/ML - just a threshold check on specific pixels, since the camera would be in a fixed mount).
- **Leaning toward B** at first - turns a hard mechanical problem into an easier, more debuggable software one.

**GoPro HERO5 Black considered for (B) instead of buying anything - ruled out for the *permanent* build:** (the model was recorded here as HERO4 until 2026-11-07, when all 176 of its files on `datapool` read `HERO5 Black`, firmware `HD5.02`)
- No official USB webcam mode (that's HERO7+), only a WiFi AP-based UDP preview stream (community-documented, works, but the camera can't join the home WiFi as a client - only broadcasts its own isolated AP).
- A permanent monitor would need a second network path entirely (dual WiFi radios, or WiFi+Ethernet on something like a Pi) just to reach MQTT/HA while also being connected to the GoPro - real added complexity the ESP32-CAM avoids by just joining the home WiFi directly like any other IoT device.
- Also unverified whether a 2016-era action camera can even focus sharply on something a few cm away.
- Still useful as a one-time proof-of-concept (temporarily join its WiFi, confirm the 4 LEDs are resolvable and readable) before committing to real hardware.

**ESP32-CAM pricing checked:** ~₹400-700 for the module alone (Robokits ₹400, Robocraze from ₹599, Robu.in ₹699), plus a separate USB-to-serial programmer board since the bare module has no USB port (~₹150-250, e.g. Robu's ESP32-CAM-MB) - realistically ~₹550-950 total for one working, flashable unit. Not yet purchased.

**Fiber-optic (option A) cost/complexity/reliability compared directly against the camera (option B):**
- **Cost: cheaper than the camera.** PMMA optical fiber (0.75-1mm) is sold as bulk craft/decor rolls, ~₹200-500/roll (estimate, not a confirmed price) - only need ~20-30cm total across 4 strands, so cost is a rounding error of any roll bought. Plus ~₹100-150 for 4 phototransistors and ~₹10-20 for resistors. Total ~₹300-700 in new parts, and reuses an already-owned ESP32 dev board (which usually has its own USB port, unlike the bare ESP32-CAM that needs a separate programmer) - genuinely cheaper than the ~₹550-950 camera path.
- **Software complexity: lower than the camera.** Plain ESPHome YAML reading 4 analog pins against a threshold - no custom firmware, no pixel calibration.
- **Physical build complexity: higher than the camera, and it's the hard part.** Hand-aligning 4 fiber tips (~0.75mm) against 4 LEDs 5mm apart, glued in place, without light leaking sideways between adjacent channels or ambient light leaking in around a loose fit - with no live feedback loop while doing it (unlike the camera, where you can watch a preview and nudge things in real time, fiber alignment is done blind: glue it, power up, test, redo if wrong).
- **Reliability: robust once aligned correctly, but a real long-term risk specific to this device.** A passive optical path has nothing to drift on its own - but the UPS itself heats up during charging/operation, and heat cycling can soften/creep the glue holding fiber alignment over time, silently degrading a channel with no obvious external symptom (just a dimmer or dark reading, discoverable only by physically reopening the enclosure to check). That's a worse failure mode than the camera's for something meant to trigger an automatic shutdown reliably - camera drift is at least visible in a preview image; fiber misalignment isn't visible at all without disassembly.
- **Verdict:** fiber is cheaper and has less code, but the build is fiddlier with no feedback loop, and its failure mode (heat-driven glue creep) is quieter and harder to catch than the camera's. Still leaning toward the camera (B) for the trust/debuggability reasons, but fiber remains a legitimate lower-cost alternative if comfortable with occasional physical re-checks.

**More options considered, (C), (D) and (E):**
- **(C) Pinhole mask + hollow chamber** - a single rigid opaque card with 4 tiny pinholes punched at the LEDs' actual 5mm spacing, held against the LED cluster; behind it, a small light-tight box (blackened inside to kill internal reflections) extends back a few cm to a second board where the 4 phototransistors sit with *normal* spacing - same pinhole-camera physics, light diverges enough over that distance that crowding stops being a problem. Combines fiber's advantages (cheap, ~₹100-150 in parts beyond what's on hand, plain ESPHome analog reads, no custom firmware) without its weaknesses: no per-strand precision gluing (one rigid mask instead of 4 floppy fiber tips), and much more heat-tolerant than fiber since a rigid mask held by friction/a snug enclosure doesn't rely on a glue joint holding sub-mm alignment. Looked like the strongest option overall at the time - cheaper and simpler-firmware like fiber, without fiber's alignment fragility or heat-driven failure mode.
- **(D) Tap the LED driver circuit directly, skip optics entirely** - open the UPS, find the PCB traces feeding each of the 4 LEDs, tap a wire to each with a voltage divider into an ESP32 GPIO. Sidesteps every optical problem at once (no alignment, no ambient light, no heat/glue concerns, nothing to ever drift). Most robust option in principle, but real safety stakes: opening a device with a rechargeable lithium battery and active charging circuit risks a short circuit, battery damage, or fire if a probe slips or a trace is misidentified, plus voids any warranty. Only worth doing with genuine confidence probing live boards carefully - not a casual default choice.
- **(E) Inline voltage/current sensor on the DC power cable, bypassing the UPS's LEDs entirely** - splice an INA219/INA226 sensor breakout (~₹150-300, I2C, plain ESPHome sensor support) directly into the DC cable between the RouterUPS and the server. Measures actual power reaching the server directly - voltage sag or current-draw shift as the battery depletes - rather than inferring state from the UPS's own indicator LEDs. No need to open the UPS at all (splicing an external cable, not touching internals near the battery - none of (D)'s safety stakes), and no LED-reading problem at all (no 5mm spacing, no optics, no fiber/pinhole/camera build). Same caveat as everything else: still needs the actual voltage/current curve for this specific UPS+server pairing characterized during a real discharge to know what threshold means "critical" - same underlying need as the pending runtime-measurement test below, just answering a different question from it.
- Also considered: a microphone/sound sensor listening for a low-battery beep, if the UPS has one - would be even simpler than (E). Unconfirmed whether this UPS actually beeps on low battery; user believes not but hasn't observed it for real. Free to check during the runtime-measurement test below rather than a separate step.

**Current ranking:** (E) inline power sensor looks like the strongest option now - avoids every problem raised so far (no LED optics, no UPS-internals safety risk) by measuring the thing that actually matters directly. (C) pinhole mask remains the best of the LED-reading approaches if E doesn't pan out. (B) camera is a solid fallback for debuggability. (A) fiber has the weakest reliability story. (D) electrical tap is the most direct read of intent but carries real safety stakes.

#### Option (D): safety and unknowns
**User is leaning toward (D)** despite the safety stakes, with real safety practices agreed if it goes ahead:
- Unplug from mains before opening.
- Work on a non-conductive fire-safe surface.
- Keep loose metal away from the board.
- Avoid doing this at 100% charge.
- Tap at the LED's own leg (after its current-limiting resistor) with a simple voltage divider - not anywhere in the main battery/charge power path.

**But (D)'s actual feasibility is unknown until the case is physically open** - three unknowns identified:
1. Whether the enclosure is even openable (screws vs glued shut).
2. Whether the LEDs are on flying wires already connected to the main board (trivial to tap) or mounted directly on the PCB (would need to solder at whatever pad pitch the board actually uses, not necessarily the same 5mm as the LEDs' visible spacing).
3. If it's PCB-mounted, whether that pitch is something comfortable to hand-solder at all.

#### Parts
Nothing to buy until the case inspection decides between the options; each `#` line is one option.

```parts
qty | item | est | note
# (E) Inline power sensor - current favourite
1 | ESP32 devkit | 400-600 | or a spare if one is free
1 | INA219 or INA226 current/voltage sensor breakout | 150-300 | local
1 | DC barrel jack pair (male + female) to splice into the UPS-to-xero cable | | local, match the UPS output plug
# (D) Tap the LED driver circuit
1 | ESP32 devkit | 400-600 | or a spare
8 | Resistors for 4 voltage dividers | 10-20 | local, values after measuring the LED voltages
# (B) Camera
1 | ESP32-CAM module | 400-700 | local (Robokits 400, Robocraze 599, Robu 699)
1 | ESP32-CAM-MB USB programmer board | 150-250 | local - the bare module has no USB
# (A) Fiber light pipes
1 | ESP32 devkit | 400-600 | or a spare
1 | PMMA optical fiber, 0.75-1mm, roll | 200-500 | local craft/decor shop - estimate; only ~30cm needed
4 | Phototransistors | 100-150 | local
4 | Resistors | 10-20 | local
```

#### Log
- 2026-10-26: moved to Backlog by the user. Nothing bought; the case inspection is still the next step whenever it is picked up.
