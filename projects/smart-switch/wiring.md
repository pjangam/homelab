# Smart switch wiring: ESP32 + relay module for the akash kandil

One ESP32 devkit switching the stash relay module, which switches the akash kandil's
230V bulb on the Diwali timer. Two halves:

- **Low voltage:** USB, ESP32, switch, relay module. Safe to get wrong and try again.
- **Mains:** wired with the plug out, checked with a meter, and closed in a plastic box
  before it ever goes into a socket.

Firmware: `esphome/smart-switch-bench.yaml`. How to flash it: `README.md`.

## 1. ESP32 to the relay module

![ESP32 wired to the KY-019 relay module](wiring-svg/01-esp32-to-relay-module.svg)

| From (ESP32) | To | Why it matters |
|---|---|---|
| `VIN` (`5V` on 38-pin boards) | module **+** | USB 5V through the board, ~4.7V. The coil needs ~70mA and closes at 3.75V or more. Never `3V3`. |
| `GPIO26` (`D26`) | module **S** | The relay command. High = relay on (`relay_inverted: "false"`). Not a strapping pin, so it can't stop the board booting. |
| `GND` | module **−** | One supply, one ground. Any GND pin on the board. |
| `GPIO27` (`D27`) | rocker switch, other side to `GND` | **Optional** manual on/off on the box, Tinxy-style: flip on = relay on, flip off = relay off; HA and the timer can change the relay in between. Works without WiFi. Low voltage only. Leave it out and HA + the timer still work. |
| onboard LED (`GPIO2`) | nothing to wire | The firmware mirrors the relay on it. |

The module is a KY-019 type: header **S + −**, an NPN transistor (Q1), a 1.5k base
resistor (R1, printed "152"), a flyback diode and an LED. No optocoupler. 3.3V on S
is plenty: about 1.7mA of base current for a ~70mA coil.

**Finding the pins:** on the ESP32, all four are on one header row. The print may say
`D26`, `IO26`, `G26` or just `26`, so read the labels rather than counting pins. The
module's header pins and the devkit's pins are both male, so use **female-female**
jumpers.

## 2. Mains side: the kandil bulb

![Mains wiring for the kandil bulb](wiring-svg/02-mains-wiring-for-the-kandil.svg)

The relay is a switch in the live wire. Wired to NO, a dead ESP32 means the bulb is
off, never stuck on.

| From | To | Why it matters |
|---|---|---|
| plug **L** | relay **COM** (middle terminal) | Switch the live, never the neutral. Switching neutral turns the bulb off but leaves the holder at 230V. No inline fuse: **plug the kandil into a power strip with its own fuse**, which protects the same wire; the house MCB backs it up. |
| relay **NO** (the end opposite the NC marking) | bulb holder L (centre contact) | Relay unpowered = bulb off. |
| plug **N** | bulb holder N | Straight through, joined in a lever connector in the box. Never through the relay. |
| plug **E** | holder earth screw, if any | A plastic B22 holder has none: end the earth core in its own lever connector. |
| relay **NC** (marked) | nothing | Leave it empty, screw done up. |

**Confirm the terminals before wiring**, multimeter on continuity, module unpowered:
middle to the NC end beeps, middle to the other end stays silent.

## 3. Safety

- **Plug out for every mains step.** Not just the socket switch off: out of the wall.
  The box lid goes on before the plug goes in.
- **Keep the two halves apart in the box.** ESP32, USB cable and switch in one corner;
  fuse, relay terminals and lever connectors in the other, a few cm apart. Cable-tie the
  mains cores so a loose one can't swing across. Clamp the mains cable where it enters
  the box, so a tug pulls on the box, not on the screw terminals.
- **Use a 3-pin plug.** A 2-pin plug fits either way round, so half the time the relay
  would switch neutral and leave the holder live while the bulb is "off".
- **The 40-60W bulb is the heat source, not the relay.** The kandil is jute and keeps
  its incandescent bulb on purpose (the clear filament throws the weave as shadows).
  The glass runs well over 100°C, on a timer, unattended. Hang the bulb in the middle
  of the lantern, clear of the jute on every side, with the top and bottom open so heat
  rises out. After the first hour, feel the jute nearest the bulb: warm is the limit,
  hot means more clearance (or the 40W instead of the 60W).
- **Lights only.** The module's tracks and screw terminals are the weak link, not the
  cube's 10A rating. Fine at 0.26A, not for a heater, geyser or iron.

## 4. Parts checklist

Prices are rough local-shop figures.

| Part | Have it? | If buying, ₹ |
|---|---|---|
| ESP32 devkit (esp32dev, WROOM-32) | yes, the spare | |
| SONGLE relay on the KY-019 module | yes | |
| 3 female-female jumper wires | likely | 40-60 |
| USB data cable + 5V charger, 1A or more | yes | |
| Small rocker or toggle switch, latching (optional; a jumper wire works for the bench) | maybe | 15-30 |
| Multimeter with continuity | yes | |
| 3-pin 6A plug | maybe | 40-80 |
| 0.75mm² flexible cable, 3-core, 2-3m | maybe | 25-40 / m |
| B22 pendant bulb holder | probably, with the kandil | 30-60 |
| Bulb: 40-60W incandescent, clear | yes | |
| Power strip with a built-in fuse, to plug the kandil into | yes | |
| Plastic junction box with a screw lid | maybe | 60-150 |
| 2-3 lever connectors (WAGO 221 or similar) | maybe | 20-40 each |
| Cable gland or grommet + cable ties | maybe | 10-30 |
| Insulation tape, heat shrink | yes | |

## 5. Check in this order

Each step adds one thing, so a failure points at that thing. Steps 1-6 are low voltage.
Build the mains side only after step 6 passes.

1. **ESP32 on USB, nothing attached.** Flash it and add it to HA (`README.md`), then
   toggle `Relay` in HA. *Expected:* the blue onboard LED follows. If not, the problem is
   firmware or HA, not wiring: read `./esphome.sh logs`.
2. **Optional: add the rocker** (or a jumper wire) between `GPIO27` and `GND`.
   *Expected:* flip on = blue LED on, flip off = LED off, and HA's `Switch position`
   follows. Then with the rocker on, turn `Relay` off in HA: it stays off until the
   rocker is flipped off and on again. Nothing = wrong pin. Never jumper a GPIO to `VIN`.
3. **Unplug USB, wire the module** (S, +, −), plug back in. *Expected:* no click at boot,
   one click per toggle in HA, and the module's LED follows. On when HA says off = the
   wrong `relay_inverted` setting.
4. **Meter on COM-NO while toggling.** *Expected:* beeps when on, silent when off. The
   reverse = you are on COM-NC.
5. **Without the network** (only if you fitted the rocker): unplug the router (or block
   the board's WiFi) and flip it. *Expected:* the relay still follows.
6. **Power loss:** pull USB with the relay on, plug back in. *Expected:* it comes back on.
7. **Plug out of the wall:** build the mains side, then meter it from the plug's pins
   with the bulb fitted and the ESP32 on USB. L to N, relay off: open. Relay on: ~60-90Ω
   for a 60W bulb (cold filament). E to L and E to N: open. 0Ω when on = a short at the
   holder, don't plug in. Reads through when off = the bulb is on NC.
8. **Lid on, then plug in.** Toggle from HA and from the switch: the bulb follows. Let it
   run an hour inside the kandil and feel the jute before trusting it to the timer.

## The numbers

- **Coil:** ~70Ω, 67-71mA at the 4.7-5V the `VIN` pin gives; closes at 3.75V or more.
- **USB budget:** ESP32 ~250mA peak on WiFi + 70mA coil ≈ 320mA. Any 1A charger.
- **Bulb:** 60W / 230V = 0.26A steady; ~2.6A for a few milliseconds when the cold
  filament switches on. Fine for 10A contacts, and far below any power strip's fuse.

## 6. Later: in-wall version, two ways to read the wall switch (not built)

A design study for "In-wall smart switch (Tinxy replacement, phase 2)" in `PROJECTS.md`,
drawn 2026-11-05 to compare the two options. Nothing here is wired yet. Both options
share the same core: inside the switchboard back box, phase from the MCB goes
**straight to relay COM, never through the wall switch**, NO goes to the existing load
wire, and neutral goes to the load as before. A mains-to-5V module (HLK-PM01 class) on a
fused phase feed replaces the USB charger. Mains parts on one side of the box, low
voltage on the other; the relay, 5V and opto modules each sit across that line.

Only the switch input differs: option A keeps the wall switch on 230V and senses it,
option B takes it off mains and wires it like the prototype's rocker.

### Option A: keep the wall switch on 230V, sense it with an AC opto module

![In-wall option A: the 230V wall switch read by an AC opto module](wiring-svg/03-inwall-option-a-ac-sensing.svg)

| From | To | Why it matters |
|---|---|---|
| phase from the MCB | relay **COM** | The relay switches the load directly. The wall switch never carries the load. |
| relay **NO** | existing load wire (light / fan) | Dead ESP32 = load off. NC stays empty. |
| neutral | load N, 5V module AC, opto **N in** | Straight through, as now. |
| phase, through a T500mA-T1A fuse | 5V module **AC** | The fuse protects the small module and its thin wires; the MCB is rated for the room's wiring, not for them. |
| phase, through the **existing wall switch** | opto **L in** | The switch only feeds the opto's sensing current. This is how Tinxy wires it (L also goes through the switch into its "TO SWITCH" terminal). |
| 5V module **+Vo** | ESP32 `VIN` and relay module **+** | One 5V supply for the board and the coil. |
| 5V module **−Vo** | ESP32 `GND`, opto **GND** | Common ground on the low-voltage side. |
| relay module **−** | ESP32 `GND` | Any GND pin; the devkit has more than one. |
| ESP32 `GPIO26` | relay module **S** | Same as the prototype. |
| ESP32 `3V3` | opto **VCC** | 3.3V, not 5V: the output goes into a GPIO, and ESP32 pins are not 5V tolerant. |
| opto **OUT** | ESP32 `GPIO27` | The output pulses at 50Hz while the switch is on (the LED inside only lights on one half of each cycle). Firmware needs a `delayed_off` filter of ~50-100ms so it reads as steady on. Check on the bench which level means "on": many of these modules pull OUT low. |

- **For:** the switchboard stays normal 230V wiring that any electrician understands. No
  low-voltage wire goes near the plate's switches. The opto isolates the ESP32 from mains.
- **Against:** one more module in a crowded back box. One firmware
  change: the `delayed_off` filter, and possibly an `inverted` flag.

### Option B: reuse the wall switch as a low-voltage input

![In-wall option B: the wall switch rewired as a 3.3V input](wiring-svg/04-inwall-option-b-low-voltage-switch.svg)

| From | To | Why it matters |
|---|---|---|
| phase, relay, 5V module, load | as in option A | Identical mains side, minus the opto module. |
| phase loop on the plate | the other switches only | Indian plates loop phase from switch to switch. Break the loop at **this** switch only; the others must keep theirs. |
| wall switch, one terminal | ESP32 `GPIO27` | Internal pull-up, same as the prototype rocker. Firmware unchanged. |
| wall switch, other terminal | ESP32 `GND` | Joins the low-voltage ground. |

- **For:** no extra part, and the firmware already works.
- **Against:** 3.3V wiring now shares a 230V box: use mains-rated wire for it and keep it
  away from the mains side. The switch looks like every other switch on the plate. If an
  electrician later "fixes" it back onto the phase loop, 230V goes straight into the
  ESP32. **Label it LOW VOLTAGE - NOT MAINS** on the plate and inside the box.

**Recommendation: option A.** The board stays normal 230V wiring an electrician
understands; it costs one module and one firmware line (`PROJECTS.md`, phase 2 entry).
