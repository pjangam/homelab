# Sound-reactive aarti lights setup (ESP32 + WLED + WS2812B)

Build runbook for the Ganapati backdrop - see PROJECTS.md, "Sound-reactive
aarti lights". Parts are in hand as of 2026-09-12: strip (bought local),
INMP441 I2S mic, and a 5V 2A supply already owned.

**The ordering principle: prove it on a breadboard, then build it.** Nothing
gets cut, soldered or stuck to a wall until the ESP32 drives pixels and the
mic reports levels. Every step up to Phase 3 is reversible, and each one
either passes or tells you exactly what is wrong - which matters because the
deadline is days away and a hard-wired mistake costs an evening.

## Pin assignment (decided here so it is not re-decided at the bench)

| Signal | ESP32 pin | Why this one |
|---|---|---|
| Strip data (DIN) | **GPIO4** | free on both WROOM and WROVER modules, and not a strapping pin |
| Mic SD (data in) | **GPIO32** | mic drives this, ESP32 listens |
| Mic WS (word select) | **GPIO25** | ESP32 drives this, so it must be output-capable |
| Mic SCK (bit clock) | **GPIO33** | ESP32 drives this, so it must be output-capable |
| Mic L/R | **GND** | ties the mic to the left channel |
| Mic VDD | **3V3** | 3.3V part - never 5V |

Two constraints behind those choices, both of which bite silently:

- **Avoid the strapping pins GPIO0/2/5/12/15.** WLED's stock default data pin
  is GPIO2, which works but is a strapping pin and on many boards also drives
  the onboard LED. GPIO4 sidesteps both.
- **GPIO34-39 are input-only.** `SD` could live there, but `WS` and `SCK` are
  *driven by* the ESP32 and will simply never appear if assigned to one - a
  dead-silent mic with no error anywhere.

## Phase 0 - firmware, no hardware attached (~1h, do this first)

This is the phase that de-risks the whole project, because AudioReactive is a
*usermod* and is not in the stock WLED binary. If it flashes, the rest is
assembly. Do it before touching the strip.

1. **Confirm the board is an ESP32, not an ESP8266.** AudioReactive needs the
   ESP32's I2S peripheral and will not exist on an 8266. Read the module can
   (`ESP32-WROOM-32` / `ESP-WROVER`), or plug it in and run
   `esptool.py --port /dev/ttyUSB0 chip_id`.
2. **Flash the audioreactive build** from <https://install.wled.me> in Chrome
   or Edge (it needs WebSerial; Firefox will not work). Pick the **ESP32
   audioreactive** variant, not plain ESP32.
   - If the installer does not offer an audioreactive ESP32 build, this
     becomes a build-from-source job with the usermod enabled in PlatformIO
     (+1-2h, and the toolchain is not set up on either machine). That is the
     single biggest source of variance in the estimate - which is exactly why
     it is step 2 and not step 12.
3. **Get it on the LAN.** It comes up as the AP `WLED-AP` (password
   `wled1234`); connect, open `4.3.2.1`, enter the house WiFi credentials.
4. **Give it a stable address.** Set an mDNS name in WLED's WiFi settings and
   add a DHCP reservation, so the Home Assistant integration in Phase 5 does
   not lose it on a lease change.

**Gate:** WLED's web UI loads over the LAN and the effect list shows entries
marked with a **♪** or **♫** symbol. Those markers are the audio-reactive
effects, and their presence is the proof the usermod is actually in the
firmware. No markers means the wrong build got flashed - fix that here, not
three phases later.

## Phase 1 - strip on a breadboard (~1h)

Only about **30 LEDs** get driven in this phase, and that is deliberate: a
breadboard's rails and jumper wires are good for roughly an amp, with enough
contact resistance to get warm and drop voltage well before that. Strip power
for the real build never goes through a breadboard.

5. **Leave the strip uncut and coiled.** WLED only drives as many LEDs as it
   is told, so setting a count of 30 means only 30 draw current no matter how
   long the reel is. Keep it coiled at low brightness only - a coiled reel run
   bright cooks itself.
6. **Wire it up:**
   - ESP32 from **USB** (laptop or a phone charger), strip from the **2A
     supply**. Keeping them separate means a sagging strip cannot brown out
     the ESP32, and serial stays available.
   - **Tie the grounds together: strip GND, ESP32 GND, supply GND.** This is
     the one that fails most often. Without a common ground the data line has
     no reference and you get flicker, random colours, or nothing at all -
     and it looks exactly like a broken strip.
   - **470R inline on the data line**, between GPIO4 and the strip's DIN.
   - **1000uF capacitor across the strip's power in**, observing polarity
     (the stripe is negative). Optional at 30 LEDs, but it is already bought
     and it costs nothing to have.
   - The 74AHCT125 level shifter is **not needed for this phase**. 3.3V data
     is reliable over the few centimetres of a breadboard; it earns its place
     on a 5m run.
7. **In WLED's LED settings:** length `30`, type `WS281x`, data pin `4`, and
   **max current `800mA`** - the breadboard's limit, not the supply's.
8. **Verify in this order,** because each check isolates a different fault:
   - A solid colour at low brightness → power and data are good.
   - Solid **red**, then **green**, then **blue** → if red and green come out
     swapped, the colour order is wrong (WS2812B is GRB); fix it in LED
     settings.
   - A rainbow or chase effect → **different colours at different points at
     once** is the proof the strip is genuinely addressable and every pixel is
     reachable. A strip that changes as one block here is a dumb strip, and
     the project stops until that is sorted.

**Gate:** 30 pixels, individually addressable, correct colours.

## Phase 2 - mic on the same breadboard (~1h)

9. **Wire the INMP441** per the pin table above: `VDD`->3V3, `GND`->GND,
   `L/R`->GND, `SD`->GPIO32, `WS`->GPIO25, `SCK`->GPIO33. If the module
   arrived with its header pins loose in the bag, they need soldering on first
   - normal, and the iron is already on the parts list.
10. **Configure the usermod:** WLED -> Config -> Usermods -> AudioReactive.
    Set the microphone type to the generic I2S option and enter the three pin
    numbers.
11. **Check the level readout** in the usermod's section of WLED's info panel
    and clap. A number that moves means the mic works. A flat zero is almost
    always one of: `WS`/`SCK` assigned to an input-only pin (GPIO34-39), the
    mic fed 5V instead of 3.3V, or `L/R` left floating.
12. **Pick a ♪ or ♫ effect and talk at it.** This is the first moment the
    project does the thing it exists to do.

**Gate:** an audio-reactive effect visibly responds to sound. Everything
electronic is now proven, and only from here is it worth committing solder.

## Phase 3 - real power, real length (~30min)

13. **Swap to the proper supply and set WLED's max current to its actual
    rating.** The limiter then auto-caps brightness, which makes over-draw
    impossible by construction rather than by discipline.
    - 60mA per LED at full white: 300 LEDs is ~18A, which no sane supply for
      this build provides. The limiter is what makes a 10A supply correct
      rather than merely optimistic.
    - Still on the 2A? It works and it will look dim - and it will not tell
      you it is the problem. See PROJECTS.md for why that is the trap.
14. **Set the real LED count**, and **inject power at both ends with 18AWG**
    on a 5m run. The strip's own copper drops enough voltage over 5m that
    white drifts pink toward the far end even with an adequate supply.
15. **Move the strip and mic off the breadboard** onto the perfboard now that
    the pinout is proven. Strip power goes supply-to-strip directly and never
    through the perfboard either.

## Phase 4 - mount and diffuse (2-4h, the phase that always overruns)

16. **Aim the strip at the wall behind the makhar, not at the room.** Bare
    WS2812s read as a row of dots and look cheap; the bounce is free and looks
    better than any diffuser. This is a design decision already made, not a
    preference to relitigate at 11pm.
17. **Check it in the dark, at the real position.** Nothing about how this
    looks can be judged at midday on a bench.

## Phase 5 - Home Assistant (~1h)

18. **The WLED integration auto-discovers it** - accept the discovery prompt;
    the stable address from step 4 is what keeps it found.
19. **Save presets in WLED** for the two or three looks worth having (aarti,
    ambient, off), then expose them as HA scenes so the light is reachable
    without the WLED app.

## Phase 6 - tune in the room, in the evening, at real volume (1-2h)

20. **Tune gain and squelch last**, in place, with the actual aarti playing at
    the volume it will really be at. The room's acoustics and real volume are
    the only settings that matter and cannot be faked earlier. Squelch sets
    the noise floor the effects ignore; gain sets how hard they swing.

## If the deadline arrives mid-build

WLED with no working mic is still the full addressable strip - 100+ effects,
chases, palettes, phone app, HA. **A backdrop running programmed effects is a
finished decoration**, and the mic upgrades it to reacting to the live aarti
whenever Phase 2 lands. So if something has to give, give up Phase 2 and 6,
not Phase 4 - an unmounted strip looks like a project, a mounted one looks
like a decoration.
