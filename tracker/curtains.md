# Remote controlled curtains
**Status:** Backlog
**Priority:** P1
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** measure the rod diameter and shape, count the windows (one motor each), weigh or estimate each curtain
- [ ] **Claude:** check whether SwitchBot or an authorised Indian seller lists the Rod 2.0 cheaper than this reseller (or wait for a sale)
- [ ] **Claude:** check whether xero has working Bluetooth; if not, budget the ESP32 proxy

**Why:** long-standing idea - open/close curtains from HA (and on a schedule/scene) instead of by hand.
**State:** not started, parked on price. **Wanted: a clip-on "curtain robot" that sits on the existing rod** - no new track, no wiring, battery-powered. Reference product (user, 2026-09-25): [SwitchBot Curtain, Rod 2.0 version on Amazon.in](https://www.amazon.in/dp/B0FLQ46BQW). **Stuck between two bad options:** readymade robots are expensive, and a DIY build is difficult for this kind of curtain. Two options, both kept open: (1) clip-on robot, (2) DIY pulley + motor cord loop. The measurements and checks in Open items come before buying.

#### Design notes
- **The curtains are fabric on a rod with rings.** That is exactly what the "Rod" variant of these robots is for: it rides on the rod and pushes the rings along. The listing notes it does **not** fit square rods, so check the rod's shape and diameter first.
- **Price is the blocker.** That listing is ₹8,199 **per motor**, from a reseller (brand shown as "Generic", 3 reviews). This looks like the same import markup found for Flic and Shelly in India.
- **One-side opening, decided 2026-09-25.** Each curtain opens to one side as a single panel, not from the middle. So it is **one motor per window**, not two. The whole curtain rides on one robot, so check its weight against the motor's rating (SwitchBot quotes ~8kg max).
- **HA fit is good without SwitchBot's hub or cloud.** The robot talks Bluetooth LE (the listing says "Wi-Fi", but Wi-Fi only comes through SwitchBot's own Hub). HA's built-in SwitchBot integration controls it locally over BLE. It needs either Bluetooth on xero or an ESP32 running ESPHome's `bluetooth_proxy` near the window (~₹500, a spare dev board will do).
- **Same form factor, other radios:** Aqara Curtain Driver E1 Rod (~US$100, Zigbee) and generic Tuya Zigbee rod robots (~US$60). These are only cheaper if a Zigbee coordinator gets bought anyway, for example for the "In-house smart switch to replace Tinxy" or door sensor projects. Otherwise BLE is the simpler route.
- **DIY: a cord-loop drive, not a friction drive.** A friction drive gripping a ring rod is fiddly to make reliable. The cheaper DIY route (option 2 below) is the old traverse-rod trick: a closed cord loop runs between a motor-driven pulley at the stack end and a sprung idler at the far end, with only the lead ring clamped to the cord. It needs a socket near the window. The mechanics are drawn in `projects/curtains/cord-loop.html` (https://claude.ai/artifact/QwLF6BaaWgt55EFHwKPZqu). Part sizes there are proposals, not checked against the real rod. **End-of-travel switches: option B, decided 2026-09-25.** Beads crimped on the cord trip both switches at the motor end, so the switches, controller and motor form one cluster and no cable runs along the rod.

#### Parts
**Two options, both kept open.** Both are per window. The dashboard's parts table lists the two options together, so do not total it - tick one option's lines.

```parts
qty | item | est | note
# Option 1 - clip-on robot (SwitchBot Curtain Rod 2.0 class)
1 | Robot: clip-on rod curtain robot | 6000-8200 | online - ₹8,199 is the reseller listing; an authorised seller or a sale may be lower. Tuya/Aqara rod robots are the cheaper alternative if Zigbee happens anyway
1 | Robot: ESP32 dev board, as ESPHome Bluetooth proxy | 0-600 | local - only if xero's Bluetooth cannot reach the window; one covers several windows, and a spare board costs nothing
1 | Robot: 5V USB charger + cable for the proxy | 0-300 | household - likely already on hand
# Option 2 - DIY pulley + motor cord loop (projects/curtains/cord-loop.html)
1 | Pulley: 12V geared DC motor, JGA25-370 class, 60-100 RPM | 350-600 | local/Robu - check torque against the real curtain's weight first
1 | Pulley: DRV8871 motor driver (or L298N) | 150-300 | local
1 | Pulley: ESP32 dev board with USB | 400-600 | local - a spare board costs nothing
1 | Pulley: 12V 2A DC adapter | 250-400 | local - needs a socket near the window
1 | Pulley: buck converter 12V to 5V (LM2596 class) | 60-120 | local - powers the ESP32 from the same adapter
2 | Pulley: lever microswitch (end stops) | 40-80 | local - both at the motor end, tripped by beads on the cord
1 | Pulley: grooved drive pulley for the motor shaft + idler pulley/bearing | 150-350 | local/Robu - a GT2 pulley pair plus belt is the fallback if cord slips
5 | Pulley: braided non-stretch cord, per metre | 50-150 | local - hardware/sailing-cord shop; about 2x the rod length plus spare
1 | Pulley: cord lock + crimp beads | 30-80 | local - cord lock on the lead ring, beads trip the end stops
1 | Pulley: L-bracket, idler plate, extension spring, screws and anchors | 150-300 | local hardware shop
1 | Pulley: small ABS project box + hookup wire | 100-200 | local - holds the controller by the motor
```

#### Budget, per window
- **Option 1, robot: about ₹6,000-8,200,** plus ₹0-900 once for the Bluetooth proxy.
- **Option 2, pulley and motor: about ₹1,700-3,000,** or about ₹1,300-2,400 reusing a spare ESP32.

The window count, still to be taken, multiplies either one.

#### Time
- **Option 1: about 2-3 hours for the first window, then about 30 minutes for each extra one.**
  - **Bluetooth path to HA - 0.5-1.5h.** Check xero's Bluetooth first. If it cannot reach, flash a spare ESP32 with `bluetooth_proxy` and plug it in near the window.
  - **Mount and calibrate - 0.5h.** Clip it onto the rod and set the open and closed ends in SwitchBot's app once. After that, HA drives it locally.
  - **HA - 1h.** Add the SwitchBot integration, then set up open/close automations (sunrise, bedtime) and a dashboard tile.
  - Charging is the ongoing cost: the battery lasts months, so plan a USB top-up. The optional SwitchBot solar panel removes that job.
- **Option 2: about 10-15 hours for the first window, then 3-5 hours for each extra one.**
  - **Mechanics - 5-8h.** Mount the motor bracket and the idler plate, run and tension the cord, fit the lead-ring clamp, and set the beads. This is where it overruns.
  - **Controller and firmware - 2-4h.** ESPHome's `endstop` cover, with a maximum run time as a backstop.
  - **Tuning and HA - 2-3h.** Get the travel speed and stop points right, then set up the same automations as option 1.

#### Difficulty
- **Option 1: easy.** Everything is off the shelf and HA supports it natively. The only real risk is fit (rod shape, ring clearance, curtain weight), which is why measuring comes first.
- **Option 2: medium.** The software is easy. The mechanical fitting is the work: cord slip, tension, and rod brackets sitting in the cord's path. It needs mains power at the window but no charging, and it is fully local.

#### Log
- 2026-09-04: noted.
- 2026-09-25: user picked the SwitchBot Curtain Rod 2.0 listing as the reference product; decided one-side opening (one motor per window) and end-of-travel switch option B for the DIY build.
