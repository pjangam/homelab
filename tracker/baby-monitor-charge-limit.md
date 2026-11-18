# Charge-limit the baby monitor iPhone SE with the smart plug
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Claude, after 2026-11-25:** take `switch.smart_switch_bench_relay` out of the `diwali_lights_*` automations (the kandil's last off is sunrise 2026-11-25)
- [ ] **Together, after Diwali:** move the plug to the SE's charger; set up the two Shortcuts automations and the HA side below; time one 80->20% discharge on Alfred

**Why:** the iPhone SE running Alfred Camera (baby monitor, `docs/hardware.md` iphone_se) sits on its charger by the cot all day, which keeps the battery at 100% and ages it. The SE has no built-in charge limit (the 80% limit is iPhone 15 and later; Optimized Battery Charging is unreliable for a phone that never leaves the charger). User idea, 2026-11-05.
**State:** idea. Reuse the in-house smart plug from "In-house smart switch to replace Tinxy" (`projects/smart-switch/`, ESP32 + relay, `switch.smart_switch_bench_relay`, LAN-only) once the kandil comes down.
- **Phone side:** two Shortcuts personal automations on the SE, trigger **Battery Level** ("falls below 20%" -> charger on, "rises above 80%" (or 90%) -> charger off), set to run immediately without asking. Each does "Get contents of URL" POST to an HA webhook (a webhook-triggered automation per action, or one with the action in the body). The SE already does this pattern for the baby-cry alert to ntfy.
- **The failure that matters is a flat phone = no baby monitor.** Guard it from three sides: (1) an HA watchdog that turns the charger on if it has been off longer than one measured discharge, and on HA start; (2) if the SE has the HA companion app, also turn on when its battery sensor reads below ~15% (backup only: iOS updates it rarely in the background); (3) consider wiring the charger on the relay's **NC** this time, so a dead ESP32 or a power blip leaves it charging (the opposite of the kandil, which is safest off). NC means relay on = charger off: name the HA entity for what it does, or invert in firmware.
- **Name it:** rename the board/entity from "Smart Switch Bench" once it has a permanent job, and update `docs/hardware.md` and `endpoints.toml`.
#### Overlaps
- **"Replace Alfred Camera with a free, local baby monitor on the iPhone SE"** (2026-11-07): Alfred may be replaced on this phone. Time the 80->20% discharge on whichever app is running then, and keep the flat-phone watchdog alongside that entry's stream-down ntfy alert.

#### Log
- 2026-11-05: idea recorded (user): after Diwali the in-house plug moves from the kandil to the Alfred camera's charger, driven by the iPhone's battery level.
