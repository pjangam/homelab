# Projects

Working list of homelab projects and their state, so context survives across sessions instead of living only in chat history. Update this whenever a project's status changes — new project, next step decided, or something completed.

Status: 🟢 active · 🟡 parked (revisit when it becomes a real problem, not proactively) · 💡 backlog idea (not started) · ✅ done

---

## 🟢 Active

### ESP32 UPS LED monitor
**Why:** `watchdog_power.sh` (below) currently guesses "90 minutes on battery is probably safe" before shutting down cleanly. The RouterUPS has 4 status LEDs (plug=mains, battery-full=on-battery-ok, lightning=charging, battery-low=critical) - reading the actual battery-low LED would replace the time guess with the UPS's own real signal.
**State:** LED behavior mapped. Physical blocker found: the 4 LEDs are only 5mm apart, too tight for discrete sensors + individual light shields (ruled out phototransistors/LDR modules + heat-shrink light shields - the sensor packages themselves don't fit at that pitch). Two options considered: (A) fiber-optic light pipes to relay light to normally-spaced sensors, or (B) a small camera reading pixel brightness at fixed, known coordinates in software (not image recognition/ML - just a threshold check on specific pixels, since the camera would be in a fixed mount). Leaning toward B - turns a hard mechanical problem into an easier, more debuggable software one.

Considered using an on-hand GoPro HERO4 Black for B instead of buying anything. Ruled out for the *permanent* build: it has no official USB webcam mode (that's HERO7+), only a WiFi AP-based UDP preview stream (community-documented, works, but the camera can't join the home WiFi as a client - only broadcasts its own isolated AP). A permanent monitor would need a second network path entirely (dual WiFi radios, or WiFi+Ethernet on something like a Pi) just to reach MQTT/HA while also being connected to the GoPro - real added complexity the ESP32-CAM avoids by just joining the home WiFi directly like any other IoT device. Also unverified whether a 2014-era action camera can even focus sharply on something a few cm away. Still useful as a one-time proof-of-concept (temporarily join its WiFi, confirm the 4 LEDs are resolvable and readable) before committing to real hardware.

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

User is leaning toward (D) despite the safety stakes, with real safety practices agreed if it goes ahead: unplug from mains before opening, work on a non-conductive fire-safe surface, keep loose metal away from the board, avoid doing this at 100% charge, and tap at the LED's own leg (after its current-limiting resistor) with a simple voltage divider - not anywhere in the main battery/charge power path.

**But (D)'s actual feasibility is unknown until the case is physically open** - three unknowns identified: (1) whether the enclosure is even openable (screws vs glued shut), (2) whether the LEDs are on flying wires already connected to the main board (trivial to tap) or mounted directly on the PCB (would need to solder at whatever pad pitch the board actually uses, not necessarily the same 5mm as the LEDs' visible spacing), and (3) if it's PCB-mounted, whether that pitch is something comfortable to hand-solder at all.
**Next step:** open the UPS case (if possible) and inspect: enclosure fastening (screws/glue), LED wiring style (flying leads vs PCB-mounted), and PCB pad spacing if applicable. This inspection determines whether (D) is actually viable before any parts are bought or other options are pursued further.

### Check if server RAM is expandable
**Why:** Immich re-enablement (parked below) is blocked specifically on 8GB RAM being insufficient with ML enabled, currently parked "at least a couple quarters" waiting for a full hardware upgrade due to the chip-price spike. If this Beelink Mini PC's RAM is actually expandable (a free/accessible SO-DIMM slot, not soldered), adding RAM alone could be a much cheaper and faster path back to Immich than waiting out the price spike for a whole new machine - but many ultra-compact fanless mini PCs in this class have soldered, non-expandable RAM, so this isn't guaranteed.
**State:** not checked yet.
**Next step:** check the machine's spec sheet or open the case to see if there's a user-accessible SO-DIMM slot. If expandable, re-evaluate the Immich parking decision against just buying RAM instead of a full machine.

### Clean dust with a blower
**Why:** general preventive maintenance - dust buildup increases fan speed/noise and raises operating temperature over time. Already a sensitive area for this machine specifically: the N5105 CPU idles at ~65°C and spikes under load (per Readme's machine-specific config notes), so dust accumulation compounds an already-tight thermal margin.
**State:** not done yet.
**Next step:** open the case and blow out accumulated dust from fans/heatsink whenever convenient - no blockers, just hasn't been done.

### Power-outage watchdog - detection logic confirmed, actual UPS runtime still unmeasured
**Why:** this server runs on its own RouterUPS battery, separate from the router's UPS. An uncontrolled crash when the battery dies is the likely cause of the ZFS corruption found in `datapool` (see below) - a clean shutdown before that happens avoids torn writes entirely.
**State:** `watchdog_power.sh` built and cron-wired (every 5 min), detects `enp1s0` losing carrier (proxy for "on battery," via the existing WiFi-failover extender). Defaults to dry-run (logs only, never shuts down) until armed via `touch ~/.power-watchdog-armed`. Confirmed working on a real ~20min outage on 2026-07-27, but that only validated the *detection/timing mechanism* (carrier-loss detected within one 5-min cron tick, elapsed time counted correctly, watch cleared on restore) - the outage never got remotely close to the 90min threshold, so **the threshold itself is still unvalidated**. "~3-4hr" was only the user's rough recollection, never measured. We don't know if 90min leaves generous margin or is uncomfortably close to the real limit, especially as the battery ages. Sudoers script (`setup_power_watchdog_sudoers.sh`) ready but not yet run.
**Next step:** deliberately test actual UPS runtime under this server's real load - unplug the RouterUPS from mains and either time how long until the battery-low LED (mapped earlier: red = critical) turns on, or let it run to see when the server actually loses power. While doing this, also listen for whether the UPS beeps on low battery (unconfirmed either way - would unlock an even simpler microphone-based option for the ESP32 project above if it does). Only once the real runtime number is known should the 90min threshold be set with real margin below it - then decide when to arm for real (`touch ~/.power-watchdog-armed` + run `setup_power_watchdog_sudoers.sh`). The ESP32 project above (now leaning toward an inline power sensor rather than reading the UPS's LEDs) would eventually replace the need for a fixed time threshold entirely.

### Local Qwen (Ollama) delegation experiment
**Why:** wanted to test routing trivial subagent tasks to a locally-hosted model (Qwen via Ollama) instead of Anthropic's cloud models, to see if cost/latency can be saved on simple work while keeping a cloud Claude model for anything nontrivial. Manual/semi-automatic invocation is an explicitly acceptable bar for a first pass, full auto-detection would be a bonus.
**State:** researched thoroughly, nothing built yet. Key finding: Claude Code (CLI or the Agent SDK library, which is Claude Code packaged as a library) validates model names against an Anthropic-only allowlist - there is no way, via `ANTHROPIC_BASE_URL`, agent-definition frontmatter, or any env var, to point the main session or a subagent at Ollama or any local model. That rules out the originally-envisioned approach entirely.

The viable path is different: a **standalone script** using the Anthropic SDK's Tool Runner (`client.beta.messages.tool_runner`, not Claude Code at all), where Ollama/Qwen is wrapped as a *custom tool* (e.g. `delegate_to_local_model`) that a cloud Claude model can choose to call based on the tool's description - this gives genuine LLM-driven auto-routing (Claude itself judges what's trivial), which is actually closer to the original ask than manual routing. Tradeoff: this is a bare API loop, not a Claude Code replacement - no built-in file/bash tools, no session persistence, none of Claude Code's actual UX beyond what we hand-built (a minimal REPL). The other option considered (Claude Agent SDK, for a closer-to-Claude-Code chat experience) was ruled out because it's the same harness under the hood and almost certainly has the same Anthropic-only model restriction, so it wouldn't solve the actual goal even though it looks closer to "chat normally."

**Target machine changed to a Mac M2, not the homelab server.** This box (Celeron N5105, no GPU, ~5GB actually free, already running 7+ production containers with a history of memory-pressure lockups) is a poor fit for local inference even at small model sizes - too weak to be useful and too risky to share resources with. The Mac M2 has real unified memory and Metal acceleration Ollama uses natively, and nothing production running on it. Chose `qwen2.5:1.5b` as the model size for that machine.

**State:** `scripts/qwen_delegate_repl.py` written and committed - a REPL loop (`while True: input() -> tool_runner turn -> print reply`) that persists conversation history across turns, defines `delegate_to_local_model` as a custom tool wrapping Ollama's local HTTP API, and prints `[-> delegating to qwen2.5:1.5b: ...]` / `[<- ... replied: ...]` markers so delegation is visible live. Orchestrator defaults to `claude-opus-5` (swappable to sonnet/haiku for cost). Syntax-checked only - **not yet run**, since it needs to execute on the Mac, which I (Claude, running via SSH on the homelab server) have no access to.
**Next step:** on the Mac - install Ollama, `ollama pull qwen2.5:1.5b`, set `ANTHROPIC_API_KEY`, then `uv run scripts/qwen_delegate_repl.py` (needs `uv`, or fall back to `pip install anthropic requests` and drop the `uv run --script` shebang). User will need to run and debug this themselves since it's on a different machine.

### Consolidated status dashboard
**Why:** right now the only way to know something's wrong is a `healthcheck.sh` email after the fact. An at-a-glance view (containers, Tinxy state, backup freshness, disk usage) would be a nicer day-to-day way to just check "is everything actually fine" without waiting for a failure alert.
**State:** just kicked off, not yet built.
**Next step:** decide on the shape - likely an HA Lovelace dashboard reusing data `healthcheck.sh` already collects, rather than a separate custom webpage.

---

## 🟡 Parked

### ZFS mirror (real redundancy for datapool)
**Why:** `datapool` is a single disk (`sda`, Kingston SA400 - budget SSD, no power-loss protection) with no mirror, despite the Readme claiming one exists. That false assumption is also why backup was skipped for this data. `copies=2` (done, see below) gives free self-healing for isolated corruption but not full-disk failure - only a real second disk fixes that.
**State:** not started. Needs a physical second disk (same/larger than 894GB) and `zpool attach`.
**Next step:** decide on and buy a second disk, whenever justified.

### Bhakti's Tailscale exit-node issue
**Why:** flagged as a known open item in the Readme - another household member can't connect to the exit node.
**State:** details not recalled, not investigated this round.
**Next step:** none until it becomes an active problem for her.

### Offsite backup for Immich photo data
**Why:** Vaultwarden and HA config are already backed up daily to Dropbox via rclone. Immich's photo data (`datapool/immich-upload`, `datapool/immich-db`) has no offsite copy - only the ZFS pool itself (single disk, see above) and the original Google Takeout zips on a separate local disk.
**State:** reconsidered, not started. A naive rclone-to-Dropbox push (same pattern as Vaultwarden/HA) doesn't actually make sense here: the whole point of self-hosting Immich is avoiding paying for cloud photo storage, so continuously syncing the full photo set to cloud storage undermines that. If pursued, needs a different shape - compress/archive first, and use a cold-storage tier (e.g. S3 Glacier / Glacier Deep Archive) priced for rarely-accessed disaster-recovery data rather than active-sync storage, not a Dropbox-style always-on sync.
**Next step:** none for now - needs the compress + cold-storage approach worked out before this is worth starting, not just "run rclone".

### Peer-to-peer sensitive document sync (Syncthing) - Dropbox replacement
**Why:** currently uses Dropbox to keep sensitive personal documents (ID cards, tax documents, etc.) available across devices. Problems with that: cloud storage is a leak risk for this class of document, has a storage limit, needs internet connectivity, and the work laptop specifically avoids Dropbox's offline-files feature out of concern the employer could flag/ban Dropbox on a work machine - meaning that device currently has no reliable access at all. This is a distinct need from the iPhone-upload SMB share (Done section) - continuous, automatic, always-available-everywhere sync, not a manual one-off drop zone.
**State:** not started. Syncthing identified as the right fit - true peer-to-peer, no cloud storage or third-party leak surface, no storage cap, works over LAN and (via Tailscale) when away from home. Homelab server would act as an always-on peer so devices stay in sync even when not simultaneously online.
**Open question:** how the work laptop fits in - same policy-visibility risk that ruled out Dropbox offline-files there could apply to installing any sync client. Not yet decided whether that machine gets a full Syncthing client, browser/web-GUI-only access, no access at all, or gets figured out later. Scope for phone + personal devices + homelab server first.
**Next step:** none yet, not started.

### Immich re-enablement
**Why:** ~13k photos already migrated from Google Takeout, but Immich is disabled - 8GB RAM isn't enough with ML enabled.
**State:** parked for "at least a couple quarters" due to the current chip-price spike delaying any hardware upgrade. Fastest partial fix (disable just `immich-machine-learning`, keep the server running without face/object search) was suggested but not applied, since the user wants it parked entirely for now.
**Next step:** revisit once hardware budget/pricing allows. The 2 corrupted "library" originals (`20170305_135159.jpg`, `GOPR0276.MP4`) have already been recovered from the intact Takeout zips and verified clean via a fresh scrub (2026-07-29) - no longer a blocker when this resumes.

---

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

---

## ✅ Done

### White noise: HTTP polling → MQTT + systemd linger fix
Root cause of the unresponsive HA switch was `Linger=no` - `white-noise-api.service` (a `systemd --user` unit) died every time the SSH session that started it ended, and HA's `curl` polling failed silently. Replaced the HTTP API with an MQTT bridge (`scripts/white-noise-mqtt.py`, `uv run --script`) using HA discovery, and ran `loginctl enable-linger pramod` so `systemd --user` units survive logout/reboot. Confirmed fixed via a real logout test.

### getty@tty1 crash-loop
`set_console_font.sh` baked a single hardcoded font choice into a static `getty@.service.d` drop-in from a one-time probe; a reboot that negotiated a different video mode broke it and crash-looped the console. Fixed by making the drop-in try fonts largest-to-smallest at every getty start instead. `fix_getty_crashloop.sh` is the recovery script if it happens again. (Initially, and wrongly, thought this was *why* the white-noise bug surfaced that day - it wasn't; see the correction in memory/git history.)

### Docker/Tailscale CVE patching + auto-update
Found real CVEs unpatched because `unattended-upgrades` only covers Ubuntu's own archive by default: Docker BuildKit command injection (fixed in 29.6.2) and a Tailscale SSH privilege-escalation bug, TS-2026-009 (fixed in 1.98.9). Patched via `apply_security_updates.sh`; `automate_security_updates.sh` extends the existing twice-daily `unattended-upgrades` run to also cover the Docker and Tailscale repos going forward, instead of a separate cron job.

### Synthetic healthcheck + email/heartbeat notifications
`healthcheck.sh` (cron, every 15 min): checks Docker containers, `systemctl --user`/system failed units, ZFS pool health, disk space, and linger. Alerts via Gmail SMTP to the user's own email (HA mobile push doesn't work without a Nabu Casa subscription - confirmed by testing), with state-based dedup so an unresolved problem alerts once, not every run. Also pings a healthchecks.io dead-man's-switch every run, to catch a total machine freeze that a script running on the machine itself could never detect about itself. Caught a real bug in its own construction: `systemctl --user` fails silently under cron's stripped environment without `XDG_RUNTIME_DIR` set.

### ZFS `copies=2` on Immich datasets
Found real, previously-unnoticed data corruption in `datapool` (6 blocks, from a 2026-07-12 scrub that was never surfaced) while building the ZFS check above. Set `copies=2` on `datapool/immich-upload` and `datapool/immich-db` - free, uses existing hardware, gives real self-healing for isolated corruption (exactly what was found) going forward. Does not fix the already-corrupted blocks (still recoverable from the intact Takeout zips whenever needed) or protect against full-disk failure (needs the real mirror project above).

### ZFS `sync=always` on Immich datasets
Surfaced while brainstorming graceful-shutdown options for the power watchdog: a different strategic angle from detection entirely - instead of getting better at *detecting* power loss, reduce the *impact* when it happens anyway. Set `sync=always` on `datapool/immich-upload` and `datapool/immich-db` (same scope as `copies=2` above), forcing every write to commit synchronously instead of buffering, shrinking the window of in-flight data that could be corrupted by an abrupt loss. Explicitly complementary, not a replacement: still need real power-loss detection (the ESP32/power-watchdog projects above), and sudden power loss can still damage hardware itself regardless of filesystem-level mitigation. Only applies to `datapool` - the OS root disk isn't ZFS, so this doesn't cover it.

### Tinxy watchdog: two-tier recovery + entity-based down-detection
2026-07-27 ISP outage exposed two gaps in `watchdog_tinxy.sh`. (1) Detection only grepped MQTT connect/disconnect log lines - blind to a stalled integration setup that logged nothing distinctive after one of the watchdog's own restarts. Fixed by adding a second signal: querying actual Tinxy entity availability via the HA API, tripping at >=90% unavailable (had to be that high since ~60% of registered entities are *always* unavailable already, from old/decommissioned devices - see backlog item above). (2) Recovery jumped straight to a full `docker restart homeassistant` - now tries a lighter config-entry reload first (what actually fixed the outage) at 20min, only escalating to a full restart at 35min if that doesn't clear it. All three tiers (start watch, reload, escalate to restart) tested live against the real script and real data, including one real end-to-end restart.

### Monitor for silent backup failures
`backup_vaultwarden.sh`/`backup_homeassistant.sh` run daily via cron and log to `backup.log`, but nothing checked whether they actually succeeded - an expired rclone token or full remote could fail them silently for weeks. Extended `healthcheck.sh` to check the age of the last success line for each (>=30h flags a problem - daily cadence plus slack, not tied to time-of-day). Tested against the real log (correctly clean), a simulated stale log, and a missing-log case.

### iPhone → ZFS video uploads via local SMB share
Immich (the normal ingestion path) is currently disabled, but videos still needed to get off the phone. Rejected a Dropbox-relay approach as an unnecessary cloud round-trip since phone and server share the same LAN. Set up a `dperson/samba` container serving a new, separate ZFS dataset (`datapool/phone-uploads`, deliberately isolated from Immich's managed datasets) over SMB. Credentials pushed into Vaultwarden (not relayed through chat) for retrieval via the Bitwarden mobile app. Confirmed the container is healthy and the share config (`valid users = phoneupload`, `read only = No`) is correct; connects from iOS via Files app → Connect to Server → `smb://192.168.1.123`.
