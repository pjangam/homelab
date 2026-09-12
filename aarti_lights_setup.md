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

**Flash WLED 0.14.4, not the latest.** Checked against the GitHub release
assets on 2026-09-12: WLED stopped shipping a prebuilt
`_ESP32_audioreactive.bin` after **0.14.4**, and every release from 0.15.0
through the current 16.0.1 has no audioreactive asset at all. Since
install.wled.me builds its variant list from those assets, the "audio" option
does not appear for current versions - so following the installer's default
lands you on a binary with no AudioReactive in it. 0.14.4 is the newest
release where the usermod is a download rather than a PlatformIO build, which
is the difference between ten minutes and a toolchain afternoon. Take the
older version; nothing this project needs arrived after it.

1. **Plug the ESP32 into `xero`** (rather than the MacBook) if there is a
   choice - the flash is then scriptable and its output reviewable, instead of
   a browser dialog whose result gets relayed by hand.
2. **Add the user to `dialout` once, before plugging in.** On Linux the serial
   device is `root:dialout`, and this user is not in that group by default, so
   the first flash attempt dies on permissions:
   ```
   sudo usermod -aG dialout $USER
   ```
   Then **log out and back in** (or `newgrp dialout` in the shell you will use).
   Group membership is only picked up at login, so skipping that makes the fix
   look like it did not work.
3. **Verify the board, writing nothing:**
   ```
   ./scripts/flash-wled-audioreactive.sh
   ```
   Read-only. It finds the port, reads the chip back, and refuses to go on if
   it is an ESP8266 or an S2/C3 variant - AudioReactive needs the original
   ESP32's I2S peripheral, and there is no audioreactive build for the others.
   It also flags a flash smaller than the 4MB WLED needs.
4. **Flash it:**
   ```
   ./scripts/flash-wled-audioreactive.sh --flash
   ```
   Downloads the 0.14.4 audioreactive image, erases the flash and writes it at
   `0x0`. Erasing wipes any existing WiFi credentials, which is the standard
   path for a first install. The script refuses an implausibly small download,
   because a truncated image flashes "successfully" and then bootloops.
5. **Get it on the LAN.** It comes up as the AP `WLED-AP` (password
   `wled1234`); connect and open the setup page, then enter the house WiFi
   credentials.
6. **Give it a stable address.** Set an mDNS name in WLED's WiFi settings and
   add a DHCP reservation, so the Home Assistant integration in Phase 5 does
   not lose it on a lease change.

**Resolved on 2026-09-12: it was a dead USB port on `xero`.** Three cables and
two hosts were tried before the port was; the board turned out fine
(ESP32-D0WD-V3 rev 3.1, 4MB flash) the moment it went into a port with a
proven working device in it. The lesson is step 4 below - swap into a port
something else is already using, early, because a machine with working USB
devices hands you a free control and this cost an hour without it.

### If the board does not show up at all

Run `./scripts/watch-usb-serial.sh` only if you are about to **replug**
something - it is a change detector and reports nothing for a board that is
already sitting in the port. For a board that is plugged in right now, check
the steady state instead:

```
ls /dev/ttyUSB* /dev/ttyACM*
lsusb -d 1a86:7523; lsusb -d 1a86:55d4   # CH340, CH9102
lsusb -d 10c4:ea60; lsusb -d 0403:6001   # CP2102, FTDI
```

Diagnosing this on 2026-09-12 cost far longer than it should have, so the
tree, in the order that actually splits the possibilities:

1. **Is a power LED lit on the board?** This is the fastest question and it
   splits the problem in half.
   - **Lit, but nothing on the USB bus** -> the cable carries VBUS and GND but
     not the D+/D- pair. A **charge-only cable**, and by a wide margin the most
     common cause. Cables bundled with power banks and wall chargers are
     frequently power-only. Swap for one that has demonstrably moved data - an
     old Android phone or Kindle cable.
   - **No LED at all** -> no power is reaching the board: dead cable, or dead
     port.
2. **Does the board even have a USB socket?** A bare ESP32-WROOM module on a
   pin-header breakout has **no USB-serial bridge at all**, so it can never
   appear on the bus no matter what cable is used. It needs an external
   USB-to-TTL adapter (CH340/CP2102, ~Rs 100-150 local) wired to TX/RX/EN/GND.
   Establish this before swapping cables, not after.
3. **Is the software side actually implicated?** Almost never - check it once
   and stop wondering. `lsmod | grep -E 'ch341|cp210x|ftdi_sio'` shows what is
   loaded, and `modinfo -n ch341 cp210x ftdi_sio` shows they are available to
   auto-load on attach. If the modules exist, a missing device is physical.
4. **Isolate the port from the cable** using a device known to work. Anything
   already enumerating (a phone, a receiver) proves its port carries both power
   and data - move the board to that port to test the port, or change only the
   cable to test the cable. One variable at a time.
5. **Still nothing? Try the MacBook** - `ls /dev/cu.*` there. The board's
   bridge either enumerates on another machine or it does not, and that single
   command separates "this machine's cable/port" from "this board is faulty"
   better than any further testing on one host.

Note that `dialout` permissions are a **later** problem than any of this: a
permission error means the device node exists. No device node at all is never
a permissions issue.

**Gate:** WLED's web UI loads over the LAN and the effect list shows entries
marked with a **♪** or **♫** symbol (single note = volume-reactive, double =
frequency-reactive). Those markers exist only when the AudioReactive usermod
is actually in the firmware, so they are the proof - not the version number,
and not that the flash reported success. No markers means the wrong image got
flashed; fix it here, not three phases later.

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
