# Speaker power slider: servo to switch the Apollo One on and off
**Status:** Backlog
**Priority:** P3
**Cost:** ₹200-300
**Effort:** ~2-3 evenings (4-7h)

#### Open items
- [ ] **Pramod:** check the Apollo One's power switch: is it a slide switch, how long is its travel (mm) and how stiff (photo + measurement)
- [ ] **Pramod:** decide how phase 1's manual on/off is pressed: a button on the box (ATtiny85 is enough) or a toggle from HA/phone (needs an ESP32)
- [ ] **Together, at the bench:** SG90 test sketch against the real switch: does it move it both ways, and at what angles
- [ ] **Together, at the bench:** after a servo power-on, check the speaker reconnects to xero over Bluetooth and plays
- [ ] **Pramod:** buy the servo parts (parts block below; the ESP32 group only if HA/phone control)

**Why:** user, 2026-11-16: "can we automate a slider switch using maybe servo motor or something", then "add that as a seperate project". The slider is the **Portronics Apollo One's power switch** (xero's Bluetooth speaker since 2026-11-14), confirmed by the user the same day.
**State:** idea only. Nothing bought, nothing measured. Goal decided by the user, 2026-11-16 - see "Goal" below.

#### Related entries
- **"USB charge switch (relay): ATtiny85 + current sensor to stop charging when full"** - same speaker. Its Digispark box (or the ESP32-C3 fallback) **could drive this servo too**: one more PWM pin, same 5V. Noted, not decided.
- **"USB charge switch (MOSFET)"** - same box, silent switch. Its "Digispark pin trap" applies here: PB0/PB2 go to the INA219, PB3 to the button, so a servo would take PB1 (the onboard LED does not matter for a servo signal) or PB4.
- **"xero's speaker over Bluetooth instead of AUX"** - the reconnect cron and `bt-speaker-mqtt` assume the speaker is on (see "Design notes / traps").

#### Goal (user, 2026-11-16)
"for now we can do manual on off. or automate it with timers or some other triggers in future".
- **Phase 1 - manual on/off.** A button on the box and/or a toggle from HA or the phone drives the servo. Nothing automatic.
- **Phase 2 - timers or other triggers, undecided.** Candidates, none chosen: a schedule, off when idle, off with the charge cycle (tie-in with the USB charge switch's "full"), on before a voice/Spotify "play" while the speaker is off (the `bt_speaker_xero/connect` hook that `bt-speaker-mqtt.service` already answers is the natural place).
- **Controller follows from phase 1:** a button only - the ATtiny85 is enough and can share the charge-switch box; an HA/phone toggle (and any phase 2) - an ESP32 with ESPHome. Picking the ESP32 now avoids a rebuild for phase 2.

#### Feasibility
**Yes, a known build.** A micro servo pushing a slide switch is a common hobby build ("servo light switch" / slide-switch pushers); ESPHome has a `servo` component driven from an `output` (LEDC on ESP32), so HA control is a few lines ([ESPHome servo](https://esphome.io/components/servo/)). On the ATtiny85 the usual route is a software servo library (e.g. Adafruit SoftServo) on a free pin.
- **Apollo One switch type not confirmed from the manual:** the [Apollo One manual](https://www.portronics.com/cdn/shop/files/Apollo_One_Manual.pdf) labels the control only as "Power." with no type (checked 2026-11-16). Hence the first open item.

#### Approach: micro servo only (user, 2026-11-16)
- **SG90** for the bench test, **MG90S** (metal gears, ~2.2 kg-cm) only if the slider is too stiff. The speaker is never opened, and the slider keeps its position when the box loses power.
- **Not doing:** opening the speaker to wire a relay across its switch - risky, dropped for good (user, 2026-11-16). Linear actuators and solenoids are not pursued either.

#### Design notes / traps
- **Mounting is the hard part, not code.** The servo must be rigidly fixed to the speaker body, its arm in line with the slider. **No 3D printer** (user, 2026-11-07), so the fork is a servo horn with a bent wire or a cut acrylic/aluminium tab, and the mount is a small bracket stuck on with 3M VHB tape or epoxy. A print service is the fallback for a printed fork.
- **Detach after moving.** Move, wait ~0.5 s, stop the PWM (ESPHome `servo.detach`; on the ATtiny stop the pulses). A held servo jitters, hums and draws current, and the slider holds its own position anyway.
- **Do not overdrive into the end stop.** Calibrate the two angles a few degrees short of where the arm stalls against the slider's end; a stalled SG90 draws ~0.6-0.7 A and cooks itself.
- **Power the servo from the charger's 5V, not the board's regulator.** Add a 470-1000 µF capacitor across the servo supply; the start-up current spike otherwise browns out an ATtiny or ESP32.
- **State: never lie.** The servo only knows its commanded angle. Real state options:
  - **Bluetooth on xero** - connected = on; free, but "off" and "out of range/asleep" look the same.
  - **The charge box's INA219** - if shared, the speaker's draw differs on/off; measure it at the bench.
  - **A limit switch** at one end - one more part, true mechanical position.
  - In HA, report "unknown" when the signals disagree; an ESPHome node gives an availability topic for free.
- **Reconnect needs no change while the speaker is off** (decided 2026-11-16, checked against the repo). With the speaker off, `projects/spotifyd/bt_speaker_reconnect.sh` (cron every minute) fails fast and exits quietly, no log spam; PipeWire falls back to the USB adapter. The same script is what reconnects it within a minute after the servo turns it back on. Pausing it only matters if the speaker should play from the phone instead of xero (it takes one source at a time).
- **After switching on, check it reconnects to xero.** xero has auto-reconnect since 2026-11-14 (`bt_speaker_reconnect.sh` every minute, `bt-speaker-mqtt` on a voice "play"), but the speaker boots into Bluetooth mode and must actually pair back, or playback after a power-on is silent. Test it at the bench: servo on, time until xero's sink is back; worst case is ~1 min (the cron interval) unless the on command also kicks `bt_speaker_xero/connect`.
- **Power cuts:** the speaker has its own battery, xero is on the UPS. A box reboot or power loss changes nothing: the slider stays where the servo left it.

#### Readymade alternatives
- **SwitchBot Bot / Fingerbot-style button pushers** - made to **press** a button, not slide one; a slider needs a push in two directions along its face. They are BLE + vendor cloud/hub (SwitchBot needs a Hub, or HA's BLE integration via xero's Bluetooth or an ESP32 proxy - see "Remote controlled curtains"). Not a fit for a slider; ~₹2,000+ (estimate) vs ~₹200 for a servo.
- No off-the-shelf slide-switch actuator found.

#### Parts
Resistors, jumpers and a 5V supply assumed owned (`docs/hardware.md` parts on hand); controller and 5V come from the USB charge switch box if shared.
```parts
qty | item | est | note
1 | SG90 micro servo (plastic gears) | 100-150 | local - for the bench test; estimate
1 | Electrolytic capacitor 1000uF 10V+ (25V fine) | 5-15 | local - across the servo's 5V, stops brown-outs. Same type as the Diwali strip's 1000uF 25V 105C, which is fitted there: buy another, or reuse it once the Diwali lights come down
1 | 3M VHB double-sided tape (small roll) or 2-part epoxy | 100-200 | local hardware shop - fixes the servo bracket to the speaker; estimate
1 | Small acrylic or aluminium sheet offcut | 50-100 | local - bracket and fork; no 3D printer here; estimate
# Stiff slider: MG90S
1 | MG90S micro servo (metal gears, 180 deg) | 200-250 | local, or online Robu ~199 / Robocraze ~229 (search, 2026-11-16) - only if the SG90 cannot move the slider
# Position feedback: limit switch
1 | Micro limit switch (lever) | 10-20 | local - only if true position feedback is wanted; estimate
# ESP32 controller (if HA control, not sharing the ATtiny box)
1 | ESP32-C3 SuperMini | 250 | local - or a spare ESP32 dev board from the stash (skip then)
```
**Cost detail:** servo option ~₹200-300 (SG90, tape, offcut, capacitor); ~₹300-450 with an MG90S. Add ~₹250 for an ESP32-C3 if not sharing the charge box or a spare board. All estimates except the MG90S online prices.

**Effort detail:** ~4-7 h for the servo option.
- Measure the switch, bench-test an SG90 with a test sketch: 1 h - **decides the whole thing**.
- Bracket, fork and alignment on the speaker: 2-4 h - **the phase that overruns**, as mechanical work always does on this repo.
- Firmware (angles, detach, state): 0.5-1 h on the ATtiny; ESPHome + HA tile ~1 h.
- Reconnect-cron tie-in: 0.5 h.
- If it ends up as its own device (ESP32), it needs a `docs/hardware.md` entry, and an HA name, area and Home dashboard tile.

#### Log
- 2026-11-16: idea recorded (user), right after the USB charge switch entries. The slider is the Apollo One's power switch (user). Options compared: wire-across, servo, actuator/solenoid, button pushers.
- 2026-11-16: goal set (user): phase 1 manual on/off, phase 2 timers or other triggers later. Controller still open.
- 2026-11-16: reconnect cron and `bt-speaker-mqtt` need no pausing while the speaker is off (user asked; checked against the repo).
- 2026-11-16: servo only (user): wire-across dropped as risky (would mean opening the speaker), actuator/solenoid dropped too; parts block reduced to the servo build.
