# Pegboard backlight as the clawlight (leftover WS2812B on Pi GPIO13)
**Status:** Parked
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** measure the leftover strip and the pegboard (size, material, gap from the wall)
- [ ] **Together:** pixel test from the Pi on GPIO13 with audio off, before any mounting

**Why:** the shipped clawlight LED is not noticeable enough by day. There is leftover WS2812B strip, probably the ~2m spare from the aarti lights reel. Mounted on the back of the pegboard the wol-sender Pi already hangs on, it would throw clawlight state onto the wall as a glow visible across the room. It would replace the single red/green LED on the same pins.
**State:** idea, direction decided, nothing built. **Nothing is on the pegboard yet; the clawlight is still the single common-cathode RG LED on GPIO13/19.** A WLED version's software exists but is stopped (see Alternative below).

#### Alternative: the WLED mirror that already exists

Software for a WLED version exists: `clawlight/wled-mirror.py`, run as `clawlight-wled-mirror.service` (2026-09-25, `clawlight/README.md`), set the aarti strip - wherever it stood - to the clawlight colour. It is stopped since the strip was packed away on 2026-10-02, with the unit left installed. So mounting the freed aarti board and strip on the pegboard and starting that unit is a no-new-code alternative to the Pi GPIO13 build below, at the cost of polling state every 2s and a second mains-only board.

#### Why the LED is dim, and why a diffuser does not fix it

It is the drive current, not the LED. A GPIO pin through 220R at 3.3V gives the red die ~6mA and the green ~1.5mA, and the Pi's pins cannot supply much more without a transistor. A ping-pong ball spreads that same small amount of light over a bigger surface: it helps at night and makes daytime worse. WS2812B pixels are driven from their own 5V supply at up to ~20mA per colour, so the strip has headroom to run bright by day and dim at night by schedule or HA's sun state. It is also full RGB, which brings back the dim white idle the RG LED could not show. Bouncing off the wall diffuses it for free.

#### Why the Pi drives it, not an ESP32 on WLED

- **Nothing moves.** The pegboard is where the Pi already is, so the data run is short. The earlier "behind the monitor" version meant relocating the Pi along with its button wiring and fan, and hiding the existing LED.
- **The pins already exist.** A strip takes one data wire: **GPIO13 (pin 33)**, today the LED's red leg. It is a hardware PWM pin (PWM1) that `rpi_ws281x` supports. GND stays on pin 39. **GPIO19 (pin 35) is freed** - it shares PWM1 with GPIO13, so it cannot drive a second strip.
- **The logic stays in `clawlight-led.py`.** It moves from gpiozero to `rpi_ws281x` for output. The MQTT side is unchanged, including the retained `clawlight/state` and the last-will that turns an unknown state into a pulse, so no WLED realtime-timeout trick is needed.
- An ESP32 on WLED remains the answer if the strip ever has to be somewhere away from the Pi.

#### What changes on the Pi

- **Analog audio off:** `dtparam=audio=off` in `/boot/firmware/config.txt`, then reboot. PWM output shares hardware with the headphone jack and glitches the strip otherwise. Checked 2026-09-16: nothing plays audio there, pipewire only holds the MIDI sequencer.
- **The service runs as root:** `rpi_ws281x` needs root for the PWM hardware. `clawlight-led.service` is `User=pramod` today, so the unit and `scripts/clawlight/deploy_clawlight_led_pi.sh` change with it.
- **The strip gets its own 5V supply, never the Pi's 5V pin.** The Pi has an unresolved undervoltage problem from its wall-mount cable. The supply's ground joins the Pi's GND. A 470R goes in series on the data line, and a 1000uF capacitor across the strip's input.
- **3.3V data into a 5V strip is outside spec,** but the aarti ESP32 is also 3.3V and drives this same strip without a level shifter. A 74AHCT125 is the fix if the first pixel flickers.
- **Cap brightness in software** and size the supply from the LED count. A clawlight piece is only ~30 pixels (~0.5m), so most of the spare reel stays free - the wall display entry below does the maths for digits on what is left. A strip around the whole pegboard edge is many more LEDs than this needs. Only part of the edge can be lit, or the whole edge at a low cap.

#### Pegboard-specific

- **Standoff decides the glow.** The halo needs a few cm between the board and the wall. Mount the strip facing the wall, or angled out, on the back edge.
- **If the pegboard is metal,** insulate the strip's cut ends and solder joints (heatshrink or tape). Bare 5V pads against a metal board are a short.
- **LED "strings" from reels are this same part:** WS2811/WS2812 pixels on wire instead of a flexible strip, one data line, no common cathode or anode to choose. Plain non-addressable RGB strings are usually 12V common anode and need a MOSFET per colour, so they are not a better buy than strip already owned.

#### Unknowns to settle first

How much strip is left and its LED density; that it is really 5V WS2812B, not 12V WS2815; the pegboard's size, material and gap from the wall; and whether there is a spare socket for the strip's supply.

#### Parts

```parts
qty | item | est | note
1 | 5V 2-3A power supply | 250-500 | local - size from the LED count; skip if the aarti 5V 4A supply is freed after the festival
1 | 470R resistor | 2 | local - series on the data line, same as the aarti build
1 | 1000uF 10V electrolytic capacitor | 15 | local - across the strip's 5V/GND at the input
1 | Heatshrink assortment | 50-100 | local - insulate cut ends, essential on a metal pegboard
```

When built: update `docs/gpio_pinout.md` (GPIO13 = strip data, GPIO19 free), `docs/hardware.md` (see `CLAUDE.md`), and the clawlight LED entry in Done.

#### Log
- 2026-09-16: noted; started as "a bias light behind the monitor" and moved to the pegboard in the same conversation. Checked that nothing plays audio on the Pi.
- 2026-09-25: `clawlight-wled-mirror.service` set the aarti strip to the clawlight colour.
- 2026-10-02: aarti strip packed away; the mirror unit stopped, left installed.
- 2026-10-16: parked (user): the clawlight stays on the single common-cathode LED, no move to a strip planned. The spare reel's pixels are spoken for instead: 16 for the voice satellites (8 each), the rest for Diwali lights.
