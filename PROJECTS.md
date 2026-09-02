# Projects

Working list of homelab projects and their state, so context survives across sessions instead of living only in chat history. Update this whenever a project's status changes — new project, next step decided, or something completed.

Status: 🟢 active · 🟡 parked (revisit when it becomes a real problem, not proactively) · 💡 backlog idea (not started) · ✅ done

---

## 🟢 Active

### ESP32 UPS LED monitor
**Why:** `watchdog_power.sh` (below) currently guesses "90 minutes on battery is probably safe" before shutting down cleanly. The RouterUPS has 4 status LEDs (plug=mains, battery-full=on-battery-ok, lightning=charging, battery-low=critical) - reading the actual battery-low LED would replace the time guess with the UPS's own real signal.

**State:** LED behavior mapped.
- **Physical blocker found:** the 4 LEDs are only 5mm apart, too tight for discrete sensors + individual light shields (ruled out phototransistors/LDR modules + heat-shrink light shields - the sensor packages themselves don't fit at that pitch).
- **Two options considered:** (A) fiber-optic light pipes to relay light to normally-spaced sensors, or (B) a small camera reading pixel brightness at fixed, known coordinates in software (not image recognition/ML - just a threshold check on specific pixels, since the camera would be in a fixed mount).
- **Leaning toward B** - turns a hard mechanical problem into an easier, more debuggable software one.

**GoPro HERO4 Black considered for (B) instead of buying anything - ruled out for the *permanent* build:**
- No official USB webcam mode (that's HERO7+), only a WiFi AP-based UDP preview stream (community-documented, works, but the camera can't join the home WiFi as a client - only broadcasts its own isolated AP).
- A permanent monitor would need a second network path entirely (dual WiFi radios, or WiFi+Ethernet on something like a Pi) just to reach MQTT/HA while also being connected to the GoPro - real added complexity the ESP32-CAM avoids by just joining the home WiFi directly like any other IoT device.
- Also unverified whether a 2014-era action camera can even focus sharply on something a few cm away.
- Still useful as a one-time proof-of-concept (temporarily join its WiFi, confirm the 4 LEDs are resolvable and readable) before committing to real hardware.

**ESP32-CAM pricing checked:** ~₹400-700 for the module alone (Robokits ₹400, Robocraze from ₹599, Robu.in ₹699), plus a separate USB-to-serial programmer board since the bare module has no USB port (~₹150-250, e.g. Robu's ESP32-CAM-MB) - realistically ~₹550-950 total for one working, flashable unit. Not yet purchased.

**Fiber-optic (option A) cost/complexity/reliability compared directly against the camera (option B):**
- **Cost: cheaper than the camera.** PMMA optical fiber (0.75-1mm) is sold as bulk craft/decor rolls, ~₹200-500/roll (estimate, not a confirmed price) - only need ~20-30cm total across 4 strands, so cost is a rounding error of any roll bought. Plus ~₹100-150 for 4 phototransistors and ~₹10-20 for resistors. Total ~₹300-700 in new parts, and reuses an already-owned ESP32 dev board (which usually has its own USB port, unlike the bare ESP32-CAM that needs a separate programmer) - genuinely cheaper than the ~₹550-950 camera path.
- **Software complexity: lower than the camera.** Plain ESPHome YAML reading 4 analog pins against a threshold - no custom firmware, no pixel calibration.
- **Physical build complexity: higher than the camera, and it's the hard part.** Hand-aligning 4 fiber tips (~0.75mm) against 4 LEDs 5mm apart, glued in place, without light leaking sideways between adjacent channels or ambient light leaking in around a loose fit - with no live feedback loop while doing it (unlike the camera, where you can watch a preview and nudge things in real time, fiber alignment is done blind: glue it, power up, test, redo if wrong).
- **Reliability: robust once aligned correctly, but a real long-term risk specific to this device.** A passive optical path has nothing to drift on its own - but the UPS itself heats up during charging/operation, and heat cycling can soften/creep the glue holding fiber alignment over time, silently degrading a channel with no obvious external symptom (just a dimmer or dark reading, discoverable only by physically reopening the enclosure to check). That's a worse failure mode than the camera's for something meant to trigger an automatic shutdown reliably - camera drift is at least visible in a preview image; fiber misalignment isn't visible at all without disassembly.
- **Verdict:** fiber is cheaper and has less code, but the build is fiddlier with no feedback loop, and its failure mode (heat-driven glue creep) is quieter and harder to catch than the camera's. Still leaning toward the camera (B) for the trust/debuggability reasons, but fiber remains a legitimate lower-cost alternative if comfortable with occasional physical re-checks.

**Two more options considered, (C) and (D):**
- **(C) Pinhole mask + hollow chamber** - a single rigid opaque card with 4 tiny pinholes punched at the LEDs' actual 5mm spacing, held against the LED cluster; behind it, a small light-tight box (blackened inside to kill internal reflections) extends back a few cm to a second board where the 4 phototransistors sit with *normal* spacing - same pinhole-camera physics, light diverges enough over that distance that crowding stops being a problem. Combines fiber's advantages (cheap, ~₹100-150 in parts beyond what's on hand, plain ESPHome analog reads, no custom firmware) without its weaknesses: no per-strand precision gluing (one rigid mask instead of 4 floppy fiber tips), and much more heat-tolerant than fiber since a rigid mask held by friction/a snug enclosure doesn't rely on a glue joint holding sub-mm alignment. Currently looks like the strongest option overall - cheaper and simpler-firmware like fiber, without fiber's alignment fragility or heat-driven failure mode.
- **(D) Tap the LED driver circuit directly, skip optics entirely** - open the UPS, find the PCB traces feeding each of the 4 LEDs, tap a wire to each with a voltage divider into an ESP32 GPIO. Sidesteps every optical problem at once (no alignment, no ambient light, no heat/glue concerns, nothing to ever drift). Most robust option in principle, but real safety stakes: opening a device with a rechargeable lithium battery and active charging circuit risks a short circuit, battery damage, or fire if a probe slips or a trace is misidentified, plus voids any warranty. Only worth doing with genuine confidence probing live boards carefully - not a casual default choice.
- **(E) Inline voltage/current sensor on the DC power cable, bypassing the UPS's LEDs entirely** - splice an INA219/INA226 sensor breakout (~₹150-300, I2C, plain ESPHome sensor support) directly into the DC cable between the RouterUPS and the server. Measures actual power reaching the server directly - voltage sag or current-draw shift as the battery depletes - rather than inferring state from the UPS's own indicator LEDs. No need to open the UPS at all (splicing an external cable, not touching internals near the battery - none of (D)'s safety stakes), and no LED-reading problem at all (no 5mm spacing, no optics, no fiber/pinhole/camera build). Same caveat as everything else: still needs the actual voltage/current curve for this specific UPS+server pairing characterized during a real discharge to know what threshold means "critical" - same underlying need as the pending runtime-measurement test below, just answering a different question from it.
- Also considered: a microphone/sound sensor listening for a low-battery beep, if the UPS has one - would be even simpler than (E). Unconfirmed whether this UPS actually beeps on low battery; user believes not but hasn't observed it for real. Free to check during the runtime-measurement test below rather than a separate step.
- **Current ranking:** (E) inline power sensor looks like the strongest option now - avoids every problem raised so far (no LED optics, no UPS-internals safety risk) by measuring the thing that actually matters directly. (C) pinhole mask remains the best of the LED-reading approaches if E doesn't pan out. (B) camera is a solid fallback for debuggability. (A) fiber has the weakest reliability story. (D) electrical tap is the most direct read of intent but carries real safety stakes.

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

**Next step:** open the UPS case (if possible) and inspect: enclosure fastening (screws/glue), LED wiring style (flying leads vs PCB-mounted), and PCB pad spacing if applicable. This inspection determines whether (D) is actually viable before any parts are bought or other options are pursued further.

### Check if server RAM is expandable
**Why:** Immich re-enablement (parked below) is blocked specifically on 8GB RAM being insufficient with ML enabled, currently parked "at least a couple quarters" waiting for a full hardware upgrade due to the chip-price spike. If this Beelink Mini PC's RAM is actually expandable (a free/accessible SO-DIMM slot, not soldered), adding RAM alone could be a much cheaper and faster path back to Immich than waiting out the price spike for a whole new machine - but many ultra-compact fanless mini PCs in this class have soldered, non-expandable RAM, so this isn't guaranteed.
**State:** **confirmed expandable (2026-08-21)** - opened the case. RAM is a removable SO-DIMM: 8GB DDR4 2666MHz. Also noted while inside: the boot SSD is a Biwin NP202 128GB.
**Next step:** RAM being genuinely upgradeable reopens the cheaper-path option - price a second/replacement DDR4 2666MHz SO-DIMM (check whether the second slot is free for a straight add, or occupied meaning it'd need a swap to a larger single stick) and re-evaluate the Immich parking decision against that cost instead of waiting out the chip-price spike for a whole new machine. Separately, 128GB is small for a boot drive running 7+ containers - worth keeping an eye on free space, though not urgent unless it becomes one.

### Local Qwen (Ollama) delegation experiment
**Why:** wanted to test routing trivial subagent tasks to a locally-hosted model (Qwen via Ollama) instead of Anthropic's cloud models, to see if cost/latency can be saved on simple work while keeping a cloud Claude model for anything nontrivial. Manual/semi-automatic invocation is an explicitly acceptable bar for a first pass, full auto-detection would be a bonus.
**State:** researched thoroughly, nothing built yet.
- **Key finding:** Claude Code (CLI or the Agent SDK library, which is Claude Code packaged as a library) validates model names against an Anthropic-only allowlist - there is no way, via `ANTHROPIC_BASE_URL`, agent-definition frontmatter, or any env var, to point the main session or a subagent at Ollama or any local model. That rules out the originally-envisioned approach entirely.
- **The viable path is different:** a **standalone script** using the Anthropic SDK's Tool Runner (`client.beta.messages.tool_runner`, not Claude Code at all), where Ollama/Qwen is wrapped as a *custom tool* (e.g. `delegate_to_local_model`) that a cloud Claude model can choose to call based on the tool's description - this gives genuine LLM-driven auto-routing (Claude itself judges what's trivial), which is actually closer to the original ask than manual routing.
- **Tradeoff:** this is a bare API loop, not a Claude Code replacement - no built-in file/bash tools, no session persistence, none of Claude Code's actual UX beyond what we hand-built (a minimal REPL).
- **Claude Agent SDK ruled out** (would've been a closer-to-Claude-Code chat experience) - it's the same harness under the hood and almost certainly has the same Anthropic-only model restriction, so it wouldn't solve the actual goal even though it looks closer to "chat normally."

**Target machine changed to a Mac M2, not the homelab server.** This box (Celeron N5105, no GPU, ~5GB actually free, already running 7+ production containers with a history of memory-pressure lockups) is a poor fit for local inference even at small model sizes - too weak to be useful and too risky to share resources with. The Mac M2 has real unified memory and Metal acceleration Ollama uses natively, and nothing production running on it. Chose `qwen2.5:1.5b` as the model size for that machine.

**State:** `scripts/qwen_delegate_repl.py` written and committed - a REPL loop (`while True: input() -> tool_runner turn -> print reply`) that persists conversation history across turns, defines `delegate_to_local_model` as a custom tool wrapping Ollama's local HTTP API, and prints `[-> delegating to qwen2.5:1.5b: ...]` / `[<- ... replied: ...]` markers so delegation is visible live. Orchestrator defaults to `claude-opus-5` (swappable to sonnet/haiku for cost). Syntax-checked only - **not yet run**, since it needs to execute on the Mac, which I (Claude, running via SSH on the homelab server) have no access to.
**Next step:** on the Mac - install Ollama, `ollama pull qwen2.5:1.5b`, set `ANTHROPIC_API_KEY`, then `uv run scripts/qwen_delegate_repl.py` (needs `uv`, or fall back to `pip install anthropic requests` and drop the `uv run --script` shebang). User will need to run and debug this themselves since it's on a different machine.

### Check RAM in Lenovo Flex
**Why:** separate from the homelab server RAM check above - user's Lenovo Flex (personal laptop) has 2 RAM sticks, believed to be 16GB total, but unsure whether DDR3 or DDR4. Needs confirming to know what upgrade options (if any) exist.
**State:** not checked yet.
**Next step:** user to physically check the sticks (or pull exact specs via OS tooling) and report back exact capacity/type/speed, then evaluate whether replacing makes sense.

### Home power audit - smart/network devices + major appliances
**Why:** triggered by a tangent while discussing whether a new WiFi button (Shelly) would raise the electricity bill - user wants to know the actual continuous background draw of always-on smart/network gear versus the usage-driven draw of major appliances, to know where money is actually going.
**State:** first pass done (2026-08-22), estimated from specs/datasheets (no plug meter available - see caveat below).

Confirmed real hardware details for two of the "always-on" devices by querying them directly:
- `xero` is a Beelink mini PC, Celeron N5105 (10W TDP), 2x SSD (Kingston SA400 960GB + Biwin 128GB boot), no spinning disk.
- The wol-sender Pi is a **Raspberry Pi 3 Model B Rev 1.2** (not 4 or Zero as assumed) with a GPIO-wired fan as extra continuous load, and `vcgencmd get_throttled` shows a sticky historical under-voltage flag consistent with the known wall-mount power-cable issue tracked elsewhere (not current-state undervoltage).

Estimated always-on draw (rounded, spec-based):
| Device | Est. watts (continuous) | Basis |
|---|---|---|
| Airtel router | ~8W | general router range (5-20W), no exact model datasheet found |
| TP-Link WiFi extender | ~4W | TP-Link range-extender models measured 3-4.8W |
| xero (Beelink N5105, 2 SSD) | ~12W | N5105 mini PCs commonly idle 10-14W depending on PSU/RAM config |
| wol-sender Pi 3B + fan | ~2.5W | Pi 3B measured idle ~1.2-2W; GPIO fan adds continuous draw on top |
| Tinxy 4-node switch x2 (self-consumption only, not switched load) | ~2W each (~4W total) | no official datasheet number found; general WiFi relay module self-consumption is ~0.5-1.5W per relay, shared control board per unit |
| **Total** | **~30W continuous** | → ~21.6 kWh/month → roughly ₹130-175/month at typical India residential rates (₹6-8/kWh) |

Fridge is the only major appliance with a comparable continuous-ish profile (compressor duty-cycling): a typical double-door fridge averages ~60-90W day-long, a 5-star inverter model less (~30-50W) - likely **larger than the entire smart/network stack combined**, but wasn't measured here. Washing machine, dishwasher, and microwave standby draw is negligible (~1-3W each when idle); their real cost is almost entirely usage-frequency driven (cycles/week, not standby watts) and wasn't estimated - needs the user's actual usage pattern to be worth calculating.

**Caveat:** all "always-on" numbers above are spec/datasheet estimates, not measured - could realistically be off ±30-40% per device without a real inline meter. Good enough to rank contributors and sanity-check "does this add to my bill" questions (context: prompted by the Shelly WiFi-button power question), not precise enough to reconcile against an actual bill.
**Next step:** if precision matters, a cheap plug-in energy meter (or checking whether the Tinxy app/HA integration exposes real energy-monitoring data for whatever's wired behind the two Tinxy units) would replace the router/extender/xero/Pi estimates with real numbers cheaply. Fridge is the highest-value next target to actually measure, since it's likely the single biggest line item of everything in this audit.

---

## 🟡 Parked

### Easier HA control for household + house help - approach 2/3 remaining
**Why:** the rest of the household and house help don't want to use the HA app/voice - need a simpler physical way to trigger scenes, white noise, scripts etc. Three approaches were considered:
- **(1) Remote control/buttons**
- **(2) A cheap wall-mounted tablet** running HA (kiosk-style) plus a client for Claude/Alfred-style assistant access
- **(3) Physical USB/GPIO buttons** for specific controls HA doesn't otherwise expose a hardware affordance for

**State:** approach (1)/(3) (GPIO buttons on the wol-sender Pi) is done - see ✅ Done below for the full build. Approach (2) (tablet) was never explored. Also still open: whether to move to ESP32/ESPHome for button locations not near an existing host (the Pi's GPIO approach only works because this button happens to sit next to it).

**Approach 1 findings - dedicated remote/button device (superseded by the DIY GPIO build, kept for reference):**
- Preference throughout: WiFi/Bluetooth-native devices that join existing infra directly, over Zigbee/IR which need an extra gateway/coordinator.
- **Shelly Plus i4** is discontinued; successor is **Shelly i4 Gen3** - WiFi-native 4-input scene controller, input-only (no relay/load-switching, unlike Tinxy where the module IS the switch), local API, native HA integration. Normally mounted behind a wall switch box.
- **True Shelly cost is roughly double the bare-device price** once a surface board, switches, wiring, and casing are added - bare device alone isn't a fair comparison to a self-contained button.
- **Shelly Plus i4 DC** (5-24V DC variant) is technically portable off a battery/power bank, but it's an always-connected WiFi/ESP32 device (not deep-sleep), so battery life is realistically days, not weeks/months - a fundamentally different portability story than a BLE device. Separately, its power draw is negligible enough that running one would **not** meaningfully affect the electricity bill (a few watts continuous, same order as the always-on devices in the power audit above).
- **Flic 2 + Flic Hub LR**: Bluetooth puck buttons, single/double/hold triggers, HACS integration with HA, genuinely portable (real BLE sleep, coin-cell-class battery life). **Shelly BLU Button1** is Shelly's own closer analog to Flic - BLE, coin-cell, real sleep, rather than the always-connected DC variant above.
- **Tinxy** sells 4/8-button RF remotes, but only as accessories for their own RF-paired relay switches - not standalone WiFi/BLE scene buttons usable independently.
- **SwitchBot Button Pusher**: a different category entirely - a BLE "fingerbot" that physically presses an *existing* wall switch, not a programmable scene button. Genuinely available on Amazon.in, but needs a SwitchBot Hub Mini for HA integration.
- **India availability blocker:** user confirmed neither Flic nor Shelly are reliably available as genuine local stock in India (Amazon.in listings suspected to be reseller/import markups, not real local retail) - this ruled out both as the primary recommendation despite fitting the spec well.
- **DIY ESP32/ESP8266 + ESPHome button** was the recommendation pending user decision - not needed for the wol-sender Pi buttons since GPIO wired directly there instead, but still the likely answer for a button location not near an existing host.

**Next step:** revisit if/when a button location comes up that isn't next to the wol-sender Pi (then it's ESP32/ESPHome), or if the tablet approach becomes worth exploring. Not proactive - parked until one of those becomes a real need.

### ZFS mirror (real redundancy for datapool)
**Why:** `datapool` is a single disk (`sda`, Kingston SA400 - budget SSD, no power-loss protection) with no mirror, despite the Readme claiming one exists. That false assumption is also why backup was skipped for this data. `copies=2` (done, see below) gives free self-healing for isolated corruption but not full-disk failure - only a real second disk fixes that.
**State:** not started. Needs a physical second disk (same/larger than 894GB) and `zpool attach`.
**Next step:** decide on and buy a second disk, whenever justified.

### Offsite backup for Immich photo data
**Why:** Vaultwarden and HA config are already backed up daily to Dropbox via rclone. Immich's photo data (`datapool/immich-upload`, `datapool/immich-db`) has no offsite copy - only the ZFS pool itself (single disk, see above) and the original Google Takeout zips on a separate local disk.
**State:** reconsidered, not started. A naive rclone-to-Dropbox push (same pattern as Vaultwarden/HA) doesn't actually make sense here: the whole point of self-hosting Immich is avoiding paying for cloud photo storage, so continuously syncing the full photo set to cloud storage undermines that. If pursued, needs a different shape - compress/archive first, and use a cold-storage tier (e.g. S3 Glacier / Glacier Deep Archive) priced for rarely-accessed disaster-recovery data rather than active-sync storage, not a Dropbox-style always-on sync.
**Next step:** none for now - needs the compress + cold-storage approach worked out before this is worth starting, not just "run rclone".

### Peer-to-peer sensitive document sync (Syncthing) - Dropbox replacement
**Why:** currently uses Dropbox to keep sensitive personal documents (ID cards, tax documents, etc.) available across devices.

Problems with that:
- Cloud storage is a leak risk for this class of document.
- Has a storage limit.
- Needs internet connectivity.
- The work laptop specifically avoids Dropbox's offline-files feature out of concern the employer could flag/ban Dropbox on a work machine - meaning that device currently has no reliable access at all.

This is a distinct need from the iPhone-upload SMB share (Done section) - continuous, automatic, always-available-everywhere sync, not a manual one-off drop zone.
**State:** not started. Syncthing identified as the right fit - true peer-to-peer, no cloud storage or third-party leak surface, no storage cap, works over LAN and (via Tailscale) when away from home. Homelab server would act as an always-on peer so devices stay in sync even when not simultaneously online.
**Open question:** how the work laptop fits in - same policy-visibility risk that ruled out Dropbox offline-files there could apply to installing any sync client. Not yet decided whether that machine gets a full Syncthing client, browser/web-GUI-only access, no access at all, or gets figured out later. Scope for phone + personal devices + homelab server first.
**Next step:** none yet, not started.

### Immich re-enablement
**Why:** ~13k photos already migrated from Google Takeout, but Immich is disabled - 8GB RAM isn't enough with ML enabled.
**State:** **on hold indefinitely (2026-08-26)** - previously parked "at least a couple quarters" pending a hardware/RAM upgrade, now open-ended rather than time-boxed. Fastest partial fix (disable just `immich-machine-learning`, keep the server running without face/object search) was suggested but not applied, since the user wants it parked entirely for now.
**Next step:** none for now - revisit whenever it becomes a real priority again, not on any schedule. All 6 corrupted blocks found in `datapool` (see ZFS corruption entry in Done) are now fully resolved and verified clean via scrub (2026-07-31) - no longer a blocker whenever this resumes. 2 recovered videos (`VID_20170311_210204.mp4`, `VID_20170729_134921.mp4`) are sitting in `datapool/recovered-media/`, not yet re-uploaded since there's no Immich to upload them to yet.

**Google Takeout export - incomplete, gap unresolved (2026-08-26).** The full export (23 parts, `takeout-20260625T094226Z-3-*.zip`, downloaded 2026-06-25/26) is missing part `019` - re-downloading just that part turns out not to be possible. Moved the 22 complete parts off the nearly-full boot disk to `datapool/google-takeout/` (see disk-space cleanup below) regardless, since they're safe to keep either way. How to actually fill the gap (full fresh re-export vs. living with one missing part) is unresolved - deferred, not blocking anything while Immich itself is on hold.

## 💡 Backlog ideas

### Miraie AC self-healing
**Why:** Readme documents a known paper cut - "if entity shows Unavailable, turn the AC on/off physically to trigger a state update." Same shape of problem as the Tinxy watchdog (auto-recover after a sustained bad state) but for the Miraie AC MQTT integration.
**State:** not started - the healthcheck/notification project was picked over this one when choosing what to build.
**Next step:** none, purely a backlog idea.

### Tinxy: remove stale/decommissioned devices from account
**Why:** some Tinxy devices are old/decommissioned and will always show offline, which is just noise (they made up ~60% of registered entities being unavailable even in the healthy baseline, discovered while tuning the watchdog's detection threshold below).
**State:** not started, explicitly not urgent.
**Next step:** remove the stale/unused devices from the Tinxy account so only in-use devices show up in HACS.

### Backup restore drill
**Why:** Vaultwarden and HA config are backed up daily to Dropbox via rclone, but the restore path has never actually been tested - only that the upload step succeeds. "Untested backups aren't backups."
**State:** not started, explicitly for later.
**Next step:** pull a recent backup down and actually restore it (to a scratch/test location, not overwriting production) to confirm it works when needed.

### Shopping list display (touchscreen e-ink)
**Why:** an always-visible, low-power household shopping list mounted somewhere shared (e.g. kitchen) - anyone can add/check off items via touch without opening an app. E-ink specifically for the always-on, no-glow, negligible-power display characteristics (fits the same "no app needed" philosophy as the physical GPIO buttons).
**State:** idea only - had been in mind but never written down anywhere until now (2026-09-02). No hardware chosen, no research done yet.
**Next step:** research touchscreen e-ink modules (existing all-in-one boards like Inkplate, vs. a bare e-ink panel + separate touch overlay + driving MCU) and how list state would sync back to HA/a shared list source.

## 🔌 ESP32 Projects

### In-house smart switch to replace Tinxy
**Why:** Tinxy relay switches are cloud-dependent (`mqtt.tinxy.in`) - two concrete problems: (1) a data-breach/privacy exposure since control routes through Tinxy's cloud rather than staying local, and (2) they stop working during an ISP outage even though the LAN itself stays up (confirmed elsewhere - the whole house doesn't lose network, just internet), which defeats the point of switches that are physically on the same LAN as the HA server.
**State:** not started - brainstormed 2026-09-02. Two directions considered:
- **Reflash existing Tinxy units with Tasmota/ESPHome** - cheapest, reuses hardware already wired into the walls, would get fully local MQTT control with zero cloud dependency. Risk: Tinxy isn't a known-flashable brand like Sonoff, so it's a per-unit gamble (open one up, identify the chip, risk bricking it) before knowing if it's worth doing for the rest.
- **Replace with switches built for local control from the start** - Shelly (local HTTP/MQTT API) or Zigbee units behind a local Zigbee2MQTT coordinator. Zigbee in particular never touches the internet at all, only local HA, so it sidesteps the ISP-outage problem structurally rather than depending on a reflash succeeding. Real cost: these are wall-mounted and already installed, not a five-minute swap, and Shelly historically runs ~2x the bare-device price once wiring/casing is counted (see cost note under "Easier HA control" above).
**Next step:** crack open one existing Tinxy switch to see what's actually inside (chip ID, whether it's a known-flashable module) before committing to either path.

### Remote control for scenes/scripts (Spotify, white noise, etc.)
**Why:** the existing physical GPIO buttons (wol-sender Pi, see ✅ Done) prove the pattern - a button publishes an MQTT message, an HA automation fires a scene/script - but that only works for locations physically next to a host with GPIO. An ESP32/ESPHome-based remote would extend the same no-app physical-control idea (see "Easier HA control for household + house help" above) to a standalone battery/USB device controllable from anywhere, not tied to the Pi's location - e.g. a bedside remote for white noise start/stop or Spotify play/pause/skip without opening the HA app.
**State:** not started - the ESP32/ESPHome route was already flagged as the likely answer for "a button location that isn't next to an existing host" in the parked scene-buttons project; this generalizes that to Spotify/media control specifically.
**Next step:** decide button layout/count needed (e.g. white noise on/off, Spotify play/pause/skip) and whether to build on ESPHome's native HA integration (least custom code, matches the existing MQTT-bridge pattern) or a fully custom firmware.

---

## ✅ Done

### Claw Light (clawlight.dev) - agent status indicator, software-only version
**Why:** a desk light that shows at-a-glance status for coding agent sessions (Claude Code, Opencode, Codex CLI, GitHub Copilot CLI) via color-coded signal - green for active work, red when input is needed - so a running session doesn't need active alt-tabbing to check on.
**What shipped (`clawlight/`, 2026-09-02):** no hardware - a web page (`clawlight/web/index.html`) served by `clawlight/server.py` on xero (port 8126, proxied at `/clawlight` by Caddy), showing green/red/gray states. "Always on top" is done via native video Picture-in-Picture (canvas → `captureStream()` → PiP), which works the same way on desktop Safari/Chrome and iOS Safari - one page covers both Mac and iOS, no OS-level always-on-top tooling needed. Confirmed floating and readable on both.
- Status is driven by 10 Claude Code hooks (`UserPromptSubmit`→active, `Stop`/`Notification`/`PermissionRequest`→waiting, `PostToolUse`→active, `SessionEnd`→end, `SubagentStart`/`TaskCreated`→task_start, `SubagentStop`/`TaskCompleted`→task_end) calling `clawlight/set-status.sh`, which POSTs to the server. The server aggregates across **all** reporting sessions, on **any** host (xero and the MacBook, over Tailscale) - red if any session needs input, green if any is active, gray otherwise. Both of the user's accounts (personal, enterprise) share one login per machine at a time, so no per-account tracking is needed.
- Each session tracks a separate foreground (active/waiting) and background (subagent/task counter) state, so a forked/background agent still working doesn't falsely flip the light to "needs input" just because the main turn ended. `PostToolUse`→active closes a gap where approving a permission prompt had no dedicated "resolved" hook to flip the light back from red.
- **State:** done and running - `clawlight-server.service` live on xero, Caddy proxying `/clawlight`, all 10 hooks wired on xero; Mac hooks being finalized by the user.
- Known limitation, not planned to be fixed: stale sessions from force-closed terminals (no graceful `SessionEnd`) only clear after a 30min timeout or a manual `systemctl --user restart clawlight-server.service` - user explicitly chose to leave the timeout as-is rather than shorten it.

**Possible future scope, not started: hardware version.** ESP32-C6, diffused RGB LED (3-lens beacon), USB-C powered, <0.5W. Open-source - firmware, CLI daemon, and hardware design all public on GitHub; sold pre-flashed but self-buildable/flashable too. Would replace "open a browser tab" with an always-visible physical light, same status source (could reuse `clawlight/server.py`'s API rather than needing its own daemon). Not proactive - revisit if the software version's browser-tab requirement becomes a real annoyance.

### Physical GPIO buttons (wol-sender Pi) - white noise start/stop + oju sleep/awake scenes
**Why:** the rest of the household and house help don't want to use the HA app/voice - physical buttons wired to the wol-sender Pi's GPIO give a simple, no-app way to trigger white noise and the sleep/awake scenes. Part of "Easier HA control for household + house help" - see 🟡 Parked for the still-open tablet/ESP32 threads.
**State:** four buttons across two bridge services, both confirmed working end-to-end against live HA switches/scenes (verified 2026-08-31).

- **First physical button in progress (2026-08-24):**
  - User has a salvaged latching/toggle mechanical switch and jumper cables on hand - decided to wire it directly into the wol-sender Pi's GPIO (not xero, which has no GPIO; not ESP32, since this button's location is right next to a host already, the case where GPIO wins per the earlier build-effort discussion).
  - `scripts/toggle-button-mqtt.py` written (committed) - publishes the switch's ON/OFF position as an HA `binary_sensor` via MQTT discovery (topic `homeassistant/binary_sensor/toggle_switch_1/config`), matching the existing `white-noise-mqtt.py` bridge style.
  - Wiring: GPIO17 (physical pin 11) to GND (physical pin 9), no resistor (uses the Pi's internal pull-up).

- **PoC method until the real switch/housing exists (2026-08-25):**
  - Couldn't find the salvaged switch right now - standing in for it by manually bridging GPIO17 (physical pin 11) to GND (physical pin 9) with a female-to-male jumper cable, plugging/unplugging by hand.
  - Confirmed safe: that pin is 3.3V logic (not the 5V rail, which is separate physical pins 2/4), current-limited to microamps by the internal pull-up - fine for repeated manual make/break.
  - This stands in for the real switch until it's found (or a replacement bought) and a housing is built.

- **Running as a systemd service (2026-08-25):**
  - Installed as `toggle-button-mqtt.service` on the Pi so it survives SSH sessions ending and reboots.
  - Needed two systemd-specific fixes beyond the original `RPi.GPIO` → `rpi-lgpio` dependency swap: (a) `ExecStart` must call `uv` by full path (`/home/pramod/.local/bin/uv`), since systemd's default `PATH` excludes `~/.local/bin`; (b) `WorkingDirectory=/home/pramod` is required - `lgpio` writes a notification file into the process's current working directory at import time, which defaults to `/` under systemd (unwritable by `pramod`), and without `WorkingDirectory` set, `gpiozero` silently falls back to a broken legacy sysfs backend instead of raising a clear error.
  - Service confirmed stable (`active`, 0 restarts).
  - Wired to a first automation: `binary_sensor.toggle_switch_1` on/off now calls `switch.turn_on`/`turn_off` on `switch.white_noise` (`toggle1_white_noise_on`/`_off` in `HOMEASSISTANT_CONFIG/automations.yaml`) - edge-triggered on the switch's own state transitions only, so scenes/dashboard control of white noise are untouched unless the physical switch is also flipped.

- **Reconnect-loop bug found and fixed (2026-08-25):**
  - First automation test immediately turned white noise back off every time it was turned on via a scene, with the physical switch never touched.
  - Root cause: `scripts/toggle-button-mqtt.py`'s manual MQTT reconnect loop (`while client.is_connected(): sleep(...)` right after `loop_start()`) was racy and reconnected on a ~5s cycle indefinitely (confirmed via Mosquitto's own log, not just the Pi's systemd restart count, which stayed at 0 the whole time since the process itself never crashed). Each reconnect briefly republished the switch's retained state through an "unavailable" transition, which was enough to refire the `to: 'off'` automation trigger every 5 seconds.
  - Fixed by replacing the manual loop with `client.connect_async()` + `client.loop_forever()` (paho's built-in reconnect handling, no race). Confirmed stable via Mosquitto's log (90+ seconds with zero reconnects) before re-enabling the automation.

- **Working end-to-end (2026-08-26):** user confirmed the physical switch + automation combination now works correctly - flipping the switch reliably toggles white noise, and scene/dashboard control of `switch.white_noise` is no longer overridden by the switch's resting position.

- **Scene buttons deployed (2026-08-26):**
  - Two momentary push buttons for `scene.ojaswi_sleeping`/`scene.ojaswi_awake` (previously only reachable via NFC tag automations).
  - Considered a single two-position toggle (ON → sleep, OFF → awake) vs. two independent push buttons - **decided: two push buttons**, since sleep/awake are one-shot scene triggers, not a persisted state like white noise, so a toggle's resting position doesn't map cleanly onto them (re-triggering sleep via a toggle would mean flipping OFF→ON, firing the awake scene on the way through - the same spurious cross-firing already fought off for white noise).
  - `scripts/scene-buttons-mqtt.py` (GPIO27/pin 13 → sleep, GPIO22/pin 15 → awake) deployed and running as `scene-buttons-mqtt.service` on the Pi.
  - The two HA automations (`scene_button_oju_sleep`/`_awake`) applied to `automations.yaml` and confirmed working.
  - Deliberately a different shape from the toggle switch's bridge: publishes a plain non-retained MQTT message only on an actual press, no persisted state/availability topic at all, sidestepping the whole reconnect-loop bug class rather than just this instance of it.
  - `gpio_pinout.md` added as a standing reference for the Pi's 40-pin header.

- **GPIO17 toggle switch swapped for two momentary push buttons (2026-08-31):** the latching toggle switch was replaced with independent start/stop push buttons - GPIO17 (pin 11, existing) now starts white noise, GPIO18 (pin 12, newly wired) stops it, both to GND, no resistor. Rebuilt in the momentary-button shape already proven out for the scene buttons: `scripts/white-noise-buttons-mqtt.py` (replaces `toggle-button-mqtt.py`) publishes a plain non-retained MQTT message per press, no retained `binary_sensor`/availability topic - sidesteps the reconnect-loop bug class entirely rather than just fixing this instance of it. New automations `white_noise_button_start`/`_stop` replace the dead `toggle1_white_noise_on`/`_off`. Details: `white_noise_buttons_setup.md`.
- **Same-day, separate bug:** while debugging why the HA white-noise switch wasn't responding, found `white-noise-mqtt.py` (the switch's own MQTT bridge, unrelated to the physical buttons) had the identical unfixed reconnect race from before the 2026-08-25 fix - `whitenoise/available` was flapping offline/online every ~5s. Fixed the same way (`connect_async()` + `loop_forever()`); see `Readme.md`'s White Noise section.
- **Confirmed working (2026-08-31):** user verified both the start and stop buttons correctly toggle `switch.white_noise` in HA.

### Spotcast fix (v4 -> v6 reinstall) + spotifyd zeroconf bug found and fixed
**Why:** spotcast (the HACS integration for triggering Spotify playback from HA) was broken account-wide - `spotcast.start` failing with `KeyError: 'serverTime'`. Initially assumed to be expired `sp_dc`/`sp_key` cookies (the known failure mode - see Readme/memory), but fresh cookies didn't fix it either, pointing at something deeper.
**What shipped (2026-09-02):**
- **Root cause found:** the failing call was to `open.spotify.com/server-time`, an unauthenticated endpoint hit *before* cookies are ever used - confirmed via direct `curl` that it now 404s for everyone. A known, actively-discussed upstream break: Spotify removed web-browser-based Chromecast device listing, which the installed spotcast v4.0.1 depended on. Not a cookie problem at all.
- **Reinstalled spotcast v4.0.1 -> v6.0.0-a16** (alpha, ground-up rewrite for the new API shape) - old version backed up outside `custom_components/` (a first backup attempt left inside `custom_components/` with its own `manifest.json` caused a separate HA-loader import bug, since fixed). Also manually installed a missing `rapidfuzz` Python dependency that didn't auto-install.
- **v6 replaces `sp_dc`/`sp_key` cookies entirely with OAuth** - reused the existing Spotify Developer app (same one behind the official Spotify integration) rather than creating a new one. Hit and fixed one more spotcast bug along the way: its "Desktop Token Authorization" step hardcodes `http://127.0.0.1:8080/login` as its redirect URI in spotcast's own source (not Spotify's) - patched to `8765` locally since 8080 was already in use on the user's Mac, and added that port to the Spotify Developer app's allowed redirect URIs. A small local relay script (run on the Mac, not xero) forwards that fixed loopback redirect on to HA's real Tailscale callback URL.
- **Confirmed working end-to-end:** `sensor.spotcast_..._spotify_devices/playlists/liked_songs/product` all show real live account data (26 playlists, 587 liked songs, "premium") - previously came back empty/erroring.
- **Separate, deeper bug found: spotifyd's local Spotify Connect discovery was silently broken since at least 2026-07-22** - `xero` never appeared as a Connect device in the Spotify app, on any device, despite spotifyd itself looking perfectly healthy. Root cause: an orphaned Docker network (`homelab_node-red-net`, leftover from the Node-RED -> Pi migration, 0 containers attached) broke spotifyd's `libmdns` interface enumeration entirely, silently aborting zeroconf setup on every single startup with no crash and no obvious symptom. Fixed by removing the orphaned network and restarting spotifyd - confirmed via `avahi-browse` that `xero` now genuinely advertises `_spotify-connect._tcp`. Full writeup: `incidents/2026-09-02-spotifyd-zeroconf-broken-by-orphaned-docker-network.md`.
- **New HA script/button:** `script.play_bedroom_track`, assigned to the Bedroom area (so it shows up automatically on the auto-generated Overview dashboard with no manual dashboard editing needed) - plays a specific track via `spotcast.play_media` targeting `media_player.xero_..._spotcast`. Confirmed working after the zeroconf fix.
**Next step:** none - fully working. Worth keeping an eye on: spotcast v6 is still alpha, so future updates could introduce new breakage.

### Power-outage watchdog - real UPS runtime measured, threshold updated, armed
**Why:** this server runs on its own RouterUPS battery, separate from the router's UPS. An uncontrolled crash when the battery dies is the likely cause of the ZFS corruption found in `datapool` (see below) - a clean shutdown before that happens avoids torn writes entirely.
**State:** `watchdog_power.sh` built and cron-wired (every 5 min), detects `enp1s0` losing carrier (proxy for "on battery," via the existing WiFi-failover extender). Defaults to dry-run (logs only, never shuts down) until armed via `touch ~/.power-watchdog-armed` - **armed** (see confirmation below).

**Real runtime measured (2026-07-31 live outage test).** Deliberately unplugged the UPS to measure actual runtime under load.
- Outage started (carrier lost) at 16:55; a separate heartbeat logger (timestamping to local disk every 2s, independent of network state) proved the machine itself kept running until 21:43:40 - **~288 minutes (4h49m) of real runtime**, far more than the old "~3-4hr" rough guess.
- Since the watchdog was still unarmed/dry-run the whole time, it never triggered a shutdown - the server crashed hard, uncontrolled, exactly the failure mode this project exists to prevent.
- ZFS came back `all pools are healthy` afterward (likely thanks to `copies=2`/`sync=always`, though not something to rely on repeating).
- Machine rebooted on its own around 22:30 with nobody touching the power button - **confirmed with the user (2026-08-26): genuinely automatic**, no manual press. Means BIOS "Restore on AC Power Loss" is already enabled by default on this board.

Threshold updated from 90min to **200min**, giving ~88min of real margin below the confirmed 288min failure point - both numbers now grounded in an actual measurement instead of a guess.
**Confirmed armed (2026-08-20):** `~/.power-watchdog-armed` exists, the sudoers rule is installed at `/etc/sudoers.d/power-watchdog`, and the cron entry is live (`*/5 * * * *`) - the doc previously said "still unarmed" but that was stale. Log has been empty since arming (no outage since), consistent with no false triggers.
**Logging noise - fixed (2026-08-26).** Previously printed a near-duplicate line every 5-minute cron tick for the whole outage (48+ lines for the 2026-07-31 test), burying the two moments that actually matter.
- `cron/watchdog_power.sh` now logs immediately on carrier-lost/restored transitions and on first crossing the 200min threshold, and otherwise only at 30min milestones while waiting or while still past threshold in dry-run.
- Verified with an isolated test harness (fake `HOME`/carrier-sysfs-path/`logger`/`sudo`, never touching the real `~/.power-watchdog-*` flags, syslog, or invoking real `sudo shutdown`): a simulated 290min outage at 5min ticks now produces 11 log lines instead of 58, carrier-restore still clears state correctly, and the armed path still triggers exactly one real shutdown call.
- The ESP32 project above (now leaning toward an inline power sensor rather than reading the UPS's LEDs) would eventually replace the need for a fixed time threshold entirely - that part remains open, unrelated to this logging fix.

**New gap found (2026-07-31, during a live outage test):** a graceful shutdown doesn't actually solve "how does the server turn back on" the way it first seems to.
- The BIOS's "Restore on AC Power Loss" setting only fires on a genuine AC-loss-then-restore event at the server's own PSU - but since the UPS keeps supplying continuous power throughout (the server draws ~0W once off, so the remaining battery margin likely never depletes, and the UPS seamlessly switches back to mains once it returns), the PSU never actually sees an interruption at all.
- That BIOS setting only would've helped in the uncontrolled-crash scenario this watchdog exists to avoid - it does nothing for a deliberate pre-emptive shutdown.

Real options to close this gap:

1. **Wake-on-LAN** - confirmed this board's NIC supports magic-packet wake (`ethtool enp1s0` shows `Supports Wake-on: pumbg`, currently `Wake-on: g`), and structurally it's actually a better fit than BIOS AC-restore since the NIC's standby rail stays powered the whole time regardless of what the OS did, so it doesn't depend on detecting an interruption that never happens.
   - **Verified end-to-end (2026-08-20, ~23:17 IST) - confirmed working.** Shut `xero` down for real (`sudo shutdown -h now`), then rebooted the Pi so its boot-time `wol-xero.service` would fire the magic packet naturally (the real outage-recovery path, not a manual `wakeonlan`). `journalctl` confirms it cleanly: the prior boot ends at `Reached target poweroff.target - System Power Off` / `Shutting down` (a genuine full power-off, not a warm `reboot.target`), and the next boot starts fresh from BIOS/kernel init **83 seconds later** - conclusive evidence of a real S5 wake, not a manual button press or soft restart. This closes out the main open question on this whole watchdog project: a pre-emptive shutdown before UPS depletion is no longer a dead end, since WoL from the Pi reliably brings the server back.
   - **`Wake-on: g` persistence - done (2026-08-26).** It previously wasn't pinned by any config (no NetworkManager profile or systemd/udev rule) - just the driver's out-of-the-box default, so a future driver/kernel update could've silently disabled it with nothing to catch it. Fixed via `scripts/persist_wol_setting.sh`, which installs `wol-persist.service` (`ExecStart=/usr/sbin/ethtool -s enp1s0 wol g`, `Requires=`/`After=sys-subsystem-net-devices-enp1s0.device`, `WantedBy=multi-user.target`). Confirmed **enabled** (survives reboot) and its last run **exited 0** with no errors logged - since the unit runs as root via systemd, a clean oneshot exit confirms the setting was actually applied.
   - Also worth noting: sending the magic packet remotely (e.g. from outside the house) isn't trivial - it's normally an L2 broadcast on the local segment, so reaching it over Tailscale/WAN would need another always-on LAN device to relay it.
2. **A relay on the motherboard's power-switch header**, driven by a small mains-powered (not UPS-powered) microcontroller that naturally loses power during the outage and pulses the relay the instant mains returns - the structurally "correct" fix, and could plausibly be combined with the ESP32 UPS-monitor project above.
3. **Manual power button press** - the current real fallback until one of the above is built/verified.

**WoL sender - interim Raspberry Pi build in progress, paused mid-setup (2026-08-01).** Decided to build the mains-powered WoL-sender idea on a spare Pi now, rather than wait on the ESP32 to arrive (ESP32 firmware already written and committed at `esp32/wol_on_boot/`, just needs the actual board purchased and PlatformIO/VSCode set up on the Mac - separate, still-pending thread). Reflashed the spare Pi (previously running HAOS) with Raspberry Pi OS Lite - hostname `wol-sender`, `192.168.1.103`, SSH key access from both `xero` and the user's Mac, reachable directly from `xero` over the LAN.

Done so far:
- `wakeonlan` installed, a `wol-xero.service` systemd unit created to fire a magic packet at `xero` (`68:1D:EF:38:8C:72` via `192.168.1.255:9`) on every boot - confirmed working with a manual test run.
- Caught a real gap in the first version: it only did a fixed `sleep 3` before sending, which isn't safe for a real outage-recovery scenario since the home router/AP also lost power and can take 60-120s to fully boot - often longer than the Pi itself.
- Wrote an improved sender (`update_wol_sender.sh`) that waits for real connectivity (up to 2min, checking for an actual route rather than trusting `network-online.target` alone) and sends the packet 3x for reliability - **applied and verified (2026-08-05)**, ran interactively over SSH (`ssh -t` needed for the `sudo` password prompt).

Also built `scripts/wol_listener.py` (committed) - a standalone UDP:9 listener to run on `xero` that validates an incoming magic packet without needing to risk shutting the real server down. **Run and confirmed (2026-08-05):** rebooted the Pi, listener on `xero` logged 3 valid magic packets arriving from `192.168.1.103` - the full boot→wait-for-network→send chain works end-to-end over the real LAN.

**Read-only overlay filesystem attempted (2026-08-05) - caused a full boot hang, reverted (2026-08-20).**
- Enabled via `raspi-config` (`cmdline.txt` gained `overlayroot=tmpfs`, initramfs regenerated same day). Went unnoticed until 2026-08-20, when the Pi was found completely unresponsive - display showed normal kernel/USB boot logs then went blank, no reaction to keyboard input.
- Ruled out power first (red PWR LED was flickering, suggesting undervoltage - swapped to an 18W GaN charger + fresh cable, LED went solid, but the hang persisted unchanged).
- Ruled out SD corruption (pulled the card into a USB reader on `xero`, ran a read-only `fsck.ext4 -n -f` on the root partition - came back completely clean).
- Ruled out the Logitech USB wireless receiver (hang happened identically with it unplugged).
- That left `cmdline.txt`'s `overlayroot=tmpfs` as the one real change from the working baseline. Removed it (script below), booted the Pi again - **confirmed fixed, boots normally**.

Root cause not fully diagnosed (unclear whether it's the first-boot resize service, `wol-xero.service`/`update_wol_sender.sh` interacting badly with a read-only root, or something else in the boot chain) - just confirmed disabling the overlay resolves it. Fix/rollback automated at `scripts/fix_wol_sender_overlay_hang.sh` (mounts the SD card's boot partition from a USB reader on `xero`, backs up `cmdline.txt`, strips `overlayroot=tmpfs`).

**Post-fix reboot test (2026-08-20):** with the overlay reverted, rebooted the Pi for real (`sudo reboot` over SSH, not just a manual power-cycle) with `wol_listener.py` running on `xero` beforehand. Pi came back up cleanly (pings normally, no hang), and the listener logged a **valid magic packet for `68:1D:EF:38:8C:72` received from `192.168.1.103`** - confirms the overlay fix holds on a real reboot and the full boot→wait-for-network→send chain still works end-to-end.

**Full end-to-end recovery test: done (2026-08-20, ~23:17 IST) - see confirmation above.** `xero` shut down for real and the Pi's boot-time WoL sender brought it back on its own, 83s later.

**IP pinned to static (2026-08-21):** the Pi had been reachable at `192.168.1.103` (its DHCP-assigned address) throughout everything above, but a lease renewal silently reassigned it to `.105` - a real risk once Node-RED depends on this Pi being reachable at a known address (see "Move some load to the Raspberry Pi" below). Rather than reuse `.103` - low DHCP addresses are more likely to get leased to some other device later and collide - pinned it static at **`192.168.1.124`** (next to xero's own `.123`) via `scripts/set_wol_sender_static_ip.sh` (nmcli, run interactively for the sudo password). Confirmed holding at `.124` with no `dynamic` flag on the interface. All mentions of `192.168.1.103` above are historical (accurate as of when each test ran) - the Pi's current address is `192.168.1.124`.

**Note (not an action item, just a standing risk if this is ever revisited):** the overlay filesystem is back to **not enabled** (reverted) - re-enabling it would need the actual boot-hang cause root-caused first, not just re-applied blindly, given it matters more than usual here since this device's whole job is repeatedly losing power abruptly.

**Pi power instability - resolved (2026-08-26).** The wall-mount power cable (the culprit identified on 2026-08-21 - flickering PWR LED tied specifically to that cable, not the Pi or adapter) has been replaced. Verified over SSH: `vcgencmd get_throttled` reports `0x0` (clean, no under-voltage now or since boot) and a full `dmesg` scan shows zero voltage/brownout entries across the current ~7h uptime. Caveat: the Pi has no persistent journal across reboots, so this only covers the current boot, not a multi-day history - but combined with the physical cable swap and no further flickering observed, treating this as closed.

**False-positive trigger, no action item (2026-08-28).** `enp1s0` lost carrier at 17:26 when someone accidentally switched off the WiFi extender providing xero's ethernet uplink - not a real mains/UPS outage. The watchdog can't tell the difference (its only signal is carrier-loss on `enp1s0`), so it followed its normal logic: waited 200min, then ran a real clean shutdown at 20:50. Knock-on effect: `pihole` runs on xero, so LAN-wide DNS was down for the full ~2h10m xero was off. Neither auto-recovery path fired, because xero's own PSU never actually lost power: BIOS AC-restore has nothing to trigger on (no AC-loss-then-restore event at xero's PSU), and the Pi's WoL sender only fires on the Pi's own boot (the Pi never lost power either). Brought back by physically reinserting xero's power cable at 23:00. Since xero's outlet never lost power, `Wake-on: g` should have stayed live the whole time - a plain `wakeonlan 68:1D:EF:38:8C:72` from the Pi or any LAN box likely would have worked without touching the cable. Root cause was human error (extender switch), not a watchdog bug - no fix needed.

**Two action items opened from that incident (2026-08-28):**

1. **Carrier-loss/restore email notifications - trial, not yet confirmed as the right approach.** `cron/watchdog_power.sh` now emails on the exact two transition moments it already logs (`enp1s0 lost carrier` / `enp1s0 carrier restored`), via a new shared `scripts/send_email.sh` (extracted from `cron/healthcheck.sh`'s inline sender, now used by both). Wrapped in `|| true` so an email failure can never block the shutdown logic. Verified: syntax-checked, a real test email sent through the new shared script, and a live no-op run of the script (carrier currently up, no state files) exits clean. **Explicitly a trial** - running for a few days to see if it's actually useful signal or just noise before deciding to keep it.
2. **Power-watchdog HA sensor - shipped.** Confirmed no such sensor existed. Added `power_on_battery` (binary, reads `~/.cache/power-watchdog/down-since`) and `power_down_minutes` to `healthcheck.sh`'s existing MQTT publish (same discovery pattern as the `spotifyd` entity), surfacing as `binary_sensor.homelab_healthcheck_homelab_power_watchdog` and `sensor.homelab_healthcheck_power_watchdog_down_duration`. Deliberately dashboard-only, not added to `healthcheck.sh`'s `problems[]` array - action item 1 above already emails on the transition directly, so folding it into the problems list too would just double the alert. Added both as tiles to the "Homelab Health" section of the storage-mode Stats dashboard (`scripts/apply_power_watchdog_dashboard_tiles.sh`, same stop-HA/copy/restart pattern as the earlier Tailscale/HA dashboard edit) - confirmed live via the HA REST API and the dashboard's own card list.

### Clean dust with a blower
General preventive maintenance - dust buildup increases fan speed/noise and raises operating temperature over time, and this N5105 CPU already runs a tight thermal margin (idles ~65°C). Done (2026-08-21), during the same case-open as the RAM check above (see 🟢 Active) - fan didn't actually have much dust buildup, but cleaned out whatever was there anyway. Revisit opportunistically during a future case-open rather than as its own task.

### UI to visualize PROJECTS.md
**Why:** this file is a flat markdown doc with a growing wall of text per project - a visual/interactive view could make it easier to scan state at a glance than scrolling raw markdown. Ruled out publishing it publicly (GitHub Pages / `pjangam.github.io`) since the file contains private LAN IPs, a MAC address, and family members' names - kept LAN-only instead, same exposure pattern as Pi-hole/Node-RED.
**What shipped (2026-08-26):**
- A small React app (`projects-ui/`, Vite + Vitest + React Testing Library) that fetches `PROJECTS.md` client-side and renders it grouped by status section, with search, per-status filter chips, and expand-all/collapse-all for the per-project `<details>` cards.
- 20 tests (parsing logic, the fetch hook, component behavior, full-app integration), all passing.
- Built as a multi-stage Docker image (`projects-ui/Dockerfile`, `node:20-alpine` build → `nginx:alpine` serve) and added as a new `projects-ui` service in `docker-compose.yml`, port 8125, LAN-only.
- `PROJECTS.md` is volume-mounted read-only into the container so edits show up on refresh without rebuilding the image.
- Confirmed rendering correctly in a real browser at `http://192.168.1.123:8125`.

**Stale-content bug found and fixed (2026-08-26):** the original mount bind-mounted the single file directly (`./PROJECTS.md:/usr/share/nginx/html/PROJECTS.md:ro`). That pins the bind to the file's inode at container-start time - any editor that saves via atomic replace (write a temp file, rename over the original, which is what this session's own Edit tool does) swaps the inode, silently freezing the container's view of the file until it's restarted.
- Traced by comparing the container's served copy against the repo file directly (`docker exec projects-ui cat ... | diff`) and confirming matching/mismatched inodes with `stat`.
- Fixed by bind-mounting the whole repo root read-only (`.:/data:ro`) and adding `projects-ui/nginx.conf` with `location = /PROJECTS.md { alias /data/PROJECTS.md; }` - directory bind mounts resolve paths fresh on every request, so a rename inside them doesn't go stale.
- Verified the fix survives a simulated atomic-replace edit with no container restart, and confirmed no other repo file is servable over HTTP (unmatched paths fall through to the SPA's `index.html`, not the real file - `/data` itself is never used as an nginx `root`).
**Left for later, low priority:** edit support (currently read-only - would need a real backend with filesystem write access, unlike today's static-file setup; scope depends on whether "edit" means quick status moves or full text editing, still undecided) and a Tailscale hostname for remote access (same pattern as HA's `ha.${TAILNET_SUFFIX}` above) if LAN-only ever stops being enough. Neither needed right now.

### Expose Home Assistant via Tailscale with its own clean hostname
**Why:** Caddy only reverse-proxied Vaultwarden (`xero.{$TAILNET_SUFFIX}`); HA is the service most worth reaching remotely and already has its own login. Path-based routing (`/ha`) was rejected since HA's frontend/plugins assume a root-relative path.
**What shipped (2026-08-26):** a `tailscale/tailscale` sidecar (`ha-tailscale` in `docker-compose.yml`, userspace networking - xero's own native `tailscaled` rules out host-mode) joins the tailnet under its own hostname `ha`, and `tailscale serve` (via `TS_SERVE_CONFIG` → `ts-ha-config/serve-config.json`) terminates TLS and reverse-proxies to HA at `192.168.1.123:8123`. Caddy untouched. `https://ha.{$TAILNET_SUFFIX}` confirmed working from inside the home network; LAN access unaffected. **Not yet tested from outside the home network / off Wi-Fi** - should work automatically over the tailnet like any other Tailscale node, but hasn't been verified.
- `serve-config.json` gotcha: `AllowFunnel` is keyed per host:port, not a plain bool - a top-level `"AllowFunnel": false` crash-looped the container. Fix: omit it entirely (default off).
- Bigger gotcha: HA rejected the proxied requests with 400 (`X-Forwarded-For header from an untrusted proxy 172.18.0.7`). HA's proxy-trust list is **not** read from `configuration.yaml` once migrated - newer HA stores it in `.storage/http` (`yaml_migration_done: true`, this instance migrated 2026-08-09 with `trusted_proxies: ["100.64.0.0/10"]`, apparently pre-staged for this project). A YAML `http:` block post-migration does nothing useful and, if malformed, fails the entire `http` integration at boot - which cascades into recovery mode (frontend/auth/api/mqtt all depend on it) and is what happened mid-session. The real fix: edit `/config/.storage/http`'s `stable.trusted_proxies` list directly (JSON) - final value `["100.64.0.0/10", "172.18.0.0/16"]`, adding the docker-compose bridge subnet the sidecar's requests originate from.
- `configuration.yaml` and `.storage/http` are normally root-owned (privileged HA container); user chowned just those two files to themselves so edits don't need `sudo` each time - everything else in `HOMEASSISTANT_CONFIG` (secrets, tokens, DB) is still root-owned.
**Left for later, low priority:** remove the stale offline `homeassistant` device (100.112.159.113, leftover from the Pi's old HAOS days) from the Tailscale admin console.

### Network/security audit across all containers (Mosquitto auth, SSH, rpcbind)
**Why:** triggered by moving Node-RED's admin editor from localhost-only to reachable over Wi-Fi (see above) - prompted a full re-evaluation of network exposure and auth across every host/service, not just Node-RED.
**What shipped (2026-08-23):**
- **Mosquitto auth.** `allow_anonymous false` + `password_file`, user `homelab`. Rewired every client: Node-RED's `ha-miraie-ac` node (via its "credentials" sub-object, not flat fields - flat fields are silently accepted as ordinary config and never reach the credential store, a real gotcha hit live), Home Assistant's own MQTT integration (patched directly into `.storage/core.config_entries` via `docker exec -u root homeassistant` since that file is root-owned and no local sudo was available - backed up first), `white-noise-mqtt.py`, `volume-mqtt.py`, `publish_healthcheck_mqtt.py` (all via a new gitignored `.env.mqtt` + `EnvironmentFile=` in their systemd units / sourced in `cron/healthcheck.sh`). Verified end-to-end post-rollout: HA's MQTT client connects and stays connected (checked via `mosquitto`'s own log, since it logs to a file not stdout), both Python bridges show `available: online`, the cron healthcheck publisher's MQTT step confirmed with a live triggered run (not just reasoned-correct), and Node-RED's local-broker + MirAIe-cloud connections both confirmed ESTABLISHED at the socket level.
- **Node-RED `adminAuth`** enabled on the Pi's editor (username `pramod`, bcrypt hash) - it was previously unauthenticated, fine when only reachable from `xero` itself, not once exposed over the LAN post-migration.
- **Pi SSH password auth disabled** (`PasswordAuthentication no` in `/etc/ssh/sshd_config`, confirmed reloaded via `journalctl` showing `SIGHUP`/reread at the same timestamp as the edit) - key-only access from here on.
- **`rpcbind` disabled** on the Pi (`systemctl disable --now`) - unused attack surface.
- Credentials (Node-RED admin, Mosquitto MQTT) pushed into Vaultwarden via `bw` CLI (user ran `bw unlock` themselves, shared only the session token - master password never seen by Claude) and deleted from scratchpad.
**Not changed (accepted status quo, not asked for):** Caddy only reverse-proxies Vaultwarden - HA, Pi-hole admin, and Node-RED remain plain HTTP on the LAN.

### Git hooks: pre-commit PII/public-IP/PCI scan, reproducible hook install
**Why:** gitleaks (existing `pre-push` hook) only catches credential-shaped secrets - it wouldn't catch a public IP, a Tailscale hostname, a phone number, or a card number accidentally committed. Separately, that pre-push hook only ever lived in `.git/hooks/` (untracked, per-clone) with no install step anywhere - it would not have survived a fresh `git clone`.
**What shipped (2026-08-23):** moved both hooks into tracked `.githooks/` and set `git config core.hooksPath .githooks` (now done automatically by `new_machine_setup.sh`). Added `.githooks/pre-commit`: scans staged added lines for public IPv4s (private/loopback ranges and well-known DNS resolvers like `8.8.8.8`/`1.1.1.1` allowlisted), Tailscale `*.ts.net` hostnames (the doc placeholder `tailXXXXX.ts.net` allowlisted), emails outside a small allowlist, phone numbers, and card numbers (Luhn-checked to cut noise on generic digit strings) - blocks the commit with `git commit --no-verify` as the documented bypass for a confirmed false positive. Dry-run tested against all currently-tracked repo content first to calibrate the allowlist before enabling; live-tested against both a deliberately planted leak (all four categories correctly caught) and a legitimate change (correctly passed clean). Documented in `Readme.md` under "Git hooks (leak scanning)".

### White noise: HTTP polling → MQTT + systemd linger fix
Root cause of the unresponsive HA switch was `Linger=no` - `white-noise-api.service` (a `systemd --user` unit) died every time the SSH session that started it ended, and HA's `curl` polling failed silently. Replaced the HTTP API with an MQTT bridge (`scripts/white-noise-mqtt.py`, `uv run --script`) using HA discovery, and ran `loginctl enable-linger pramod` so `systemd --user` units survive logout/reboot. Confirmed fixed via a real logout test.

### getty@tty1 crash-loop
The console font setup baked a single hardcoded font choice into a static `getty@.service.d` drop-in from a one-time probe; a reboot that negotiated a different video mode broke it and crash-looped the console. Fixed by making the drop-in try fonts largest-to-smallest at every getty start instead - now installed automatically by `new_machine_setup.sh`'s N5105 block. (The standalone recovery script for this incident was removed once the preventive fix landed; recoverable from git history if it ever recurs.) (Initially, and wrongly, thought this was *why* the white-noise bug surfaced that day - it wasn't; see the correction in memory/git history.)

### Docker/Tailscale CVE patching + auto-update
Found real CVEs unpatched because `unattended-upgrades` only covers Ubuntu's own archive by default: Docker BuildKit command injection (fixed in 29.6.2) and a Tailscale SSH privilege-escalation bug, TS-2026-009 (fixed in 1.98.9). Patched via a one-off dated script (since removed - the patch is applied, nothing left to re-run); the ongoing fix extending the twice-daily `unattended-upgrades` run to also cover the Docker and Tailscale repos is now installed automatically by `new_machine_setup.sh`, instead of a separate cron job.

### Synthetic healthcheck + email/heartbeat notifications
`healthcheck.sh` (cron, every 15 min): checks Docker containers, `systemctl --user`/system failed units, ZFS pool health, disk space, and linger. Alerts via Gmail SMTP to the user's own email (HA mobile push doesn't work without a Nabu Casa subscription - confirmed by testing), with state-based dedup so an unresolved problem alerts once, not every run. Also pings a healthchecks.io dead-man's-switch every run, to catch a total machine freeze that a script running on the machine itself could never detect about itself. Caught a real bug in its own construction: `systemctl --user` fails silently under cron's stripped environment without `XDG_RUNTIME_DIR` set.

### ZFS `copies=2` on Immich datasets
Found real, previously-unnoticed data corruption in `datapool` (6 blocks, from a 2026-07-12 scrub that was never surfaced) while building the ZFS check above. Set `copies=2` on `datapool/immich-upload` and `datapool/immich-db` - free, uses existing hardware, gives real self-healing for isolated corruption (exactly what was found) going forward. Does not fix the already-corrupted blocks (still recoverable from the intact Takeout zips whenever needed) or protect against full-disk failure (needs the real mirror project above).

### ZFS `sync=always` on Immich datasets
Surfaced while brainstorming graceful-shutdown options for the power watchdog: a different strategic angle from detection entirely - instead of getting better at *detecting* power loss, reduce the *impact* when it happens anyway. Set `sync=always` on `datapool/immich-upload` and `datapool/immich-db` (same scope as `copies=2` above), forcing every write to commit synchronously instead of buffering, shrinking the window of in-flight data that could be corrupted by an abrupt loss. Explicitly complementary, not a replacement: still need real power-loss detection (the ESP32/power-watchdog projects above), and sudden power loss can still damage hardware itself regardless of filesystem-level mitigation. Only applies to `datapool` - the OS root disk isn't ZFS, so this doesn't cover it.

### ZFS corruption on `datapool` fully resolved
All 6 originally-corrupted blocks (2026-07-12 scrub) dealt with. 2 "library" originals were recovered earlier from intact Takeout zips. Of the remaining 4 (found via `zpool status -v`, surfaced on the new MQTT dashboard as "Homelab ZFS Pool" going red): 2 were cached Immich thumbnail previews (no real data loss - deleted, Immich regenerates them automatically) and 2 were video originals under Immich's managed `upload/` path with no corresponding database row at all (confirmed via a temporary read-only query against a one-off `database` container started against the real `datapool/immich-db` volume) - meaning Immich had already forgotten these assets regardless of corruption. Identified which two Takeout videos they were by matching `photoTakenTime` timestamps from Takeout JSON sidecars against the corrupted files' own embedded metadata (still fully readable despite the corruption) - duration matched to the microsecond, confirming identity beyond doubt. File sizes differed substantially (Takeout originals ~1.4-3x larger) because Immich had transcoded them on upload, so the recovered copies are actually higher quality than what was lost. Moved to a new, separate, hardened dataset (`datapool/recovered-media`, `copies=2`/`sync=always`) rather than restored into the orphaned Immich path, since Immich can't reference them either way until manually re-uploaded once it's back online. Corrupted files deleted, `zpool clear` + fresh scrub run - confirmed "0 errors", "No known data errors".

### Tinxy watchdog: two-tier recovery + entity-based down-detection
2026-07-27 ISP outage exposed two gaps in `watchdog_tinxy.sh`.
- **(1) Detection only grepped MQTT connect/disconnect log lines** - blind to a stalled integration setup that logged nothing distinctive after one of the watchdog's own restarts. Fixed by adding a second signal: querying actual Tinxy entity availability via the HA API, tripping at >=90% unavailable (had to be that high since ~60% of registered entities are *always* unavailable already, from old/decommissioned devices - see backlog item above).
- **(2) Recovery jumped straight to a full `docker restart homeassistant`** - now tries a lighter config-entry reload first (what actually fixed the outage) at 20min, only escalating to a full restart at 35min if that doesn't clear it.

All three tiers (start watch, reload, escalate to restart) tested live against the real script and real data, including one real end-to-end restart.

### Monitor for silent backup failures
`backup_vaultwarden.sh`/`backup_homeassistant.sh` run daily via cron and log to `backup.log`, but nothing checked whether they actually succeeded - an expired rclone token or full remote could fail them silently for weeks. Extended `healthcheck.sh` to check the age of the last success line for each (>=30h flags a problem - daily cadence plus slack, not tied to time-of-day). Tested against the real log (correctly clean), a simulated stale log, and a missing-log case.

### iPhone → ZFS video uploads via local SMB share
Immich (the normal ingestion path) is currently disabled, but videos still needed to get off the phone. Rejected a Dropbox-relay approach as an unnecessary cloud round-trip since phone and server share the same LAN. Set up a `dperson/samba` container serving a new, separate ZFS dataset (`datapool/phone-uploads`, deliberately isolated from Immich's managed datasets) over SMB. Credentials pushed into Vaultwarden (not relayed through chat) for retrieval via the Bitwarden mobile app. Confirmed the container is healthy and the share config (`valid users = phoneupload`, `read only = No`) is correct; connects from iOS via Files app → Connect to Server → `smb://192.168.1.123`.

Actual driving need: reclaiming phone storage, which was running low - this is a plain file dump, not photo management. Explicitly a stopgap: it loses the AI features (face/object search, memories, etc.) that Google Photos/Immich provide, so it's not a replacement for Immich re-enablement (parked above), just what's usable in the meantime. First real batch: 53 large video files uploaded and moved off the phone (2026-07-31), all verified non-corrupt via `ffprobe`.

### Consolidated status dashboard
Previously the only way to know something's wrong was a `healthcheck.sh` email after the fact. Extended `healthcheck.sh` to publish its check results (containers, systemd units, ZFS pool health, disk usage, backup freshness) to MQTT with HA discovery, grouped under a "Homelab Healthcheck" device - 9 entities total, published on every 15min cron run independent of the email-alert path so a publish failure can't suppress a real alert. Added a "Homelab Health" section to the existing "Stats" Lovelace dashboard with tile cards for all 9 entities (required stopping HA briefly to hand-edit the storage-mode dashboard file directly, since it's UI-managed rather than YAML). Verified end-to-end: entities confirmed live via the HA REST API, dashboard confirmed intact after restart with no lovelace-related errors in logs.

### Move some load to the Raspberry Pi
**Why:** the `wol-sender` Pi previously only sent a boot-time magic packet to `xero` - a trivially light job for a whole Pi, real spare capacity going unused.

**Node-RED migrated (2026-08-22)** - flows/credentials/Miraie AC config copied to the Pi, started via plain `docker run`, both required MQTT connections (local HA broker, MirAIe cloud broker) confirmed live at the socket level. Removed `node-red` from `xero`'s `docker-compose.yml`.

**Constraint identified along the way:** the Pi has no battery backup (unlike `xero`, on the UPS), but the LAN/router stays up during an outage - so anything actively network-depended-on during an outage can't move here without the Pi also getting battery backup. Ruled out Pi-hole, Mosquitto, Caddy, and Home Assistant on those grounds. Also ruled out: Watchtower (can only manage the Pi's own containers via its local Docker socket, not `xero`'s), Samba (storage lives on `xero`'s ZFS pool, moving just the container adds a network round-trip or needs real separate storage on the Pi).

**Watchdog fixed and redesigned (2026-08-23)** - the Mosquitto-auth security pass broke `watchdog_nodered.sh` (no credentials passed), which surfaced a deeper pre-existing bug: its `AC_TOPIC` never matched what the `ha-miraie-ac` node actually publishes, and that data isn't retained anyway (only sent once per reconnect). Rewrote to check the container's own `/proc/net/tcp` for ESTABLISHED connections instead - independent of the AC's power state. Documented in `Readme.md` under "Node-RED Watchdog (MQTT bridge health)".

**Closed out (2026-09-02):** the old `homelab_node-red-data` volume on `xero`, left as a rollback net, is confirmed gone (`docker volume ls` no longer lists it). Vaultwarden was the only other live candidate and stays deliberately deprioritized to last resort (2026-08-20 decision, see git history) rather than an open action item - re-open only if real headroom pressure shows up on the Pi.
