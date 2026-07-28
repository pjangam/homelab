# Projects

Working list of homelab projects and their state, so context survives across sessions instead of living only in chat history. Update this whenever a project's status changes — new project, next step decided, or something completed.

Status: 🟢 active · 🟡 parked (revisit when it becomes a real problem, not proactively) · 💡 backlog idea (not started) · ✅ done

---

## 🟢 Active

### ESP32 UPS LED monitor
**Why:** `watchdog_power.sh` (below) currently guesses "90 minutes on battery is probably safe" before shutting down cleanly. The RouterUPS has 4 status LEDs (plug=mains, battery-full=on-battery-ok, lightning=charging, battery-low=critical) - reading the actual battery-low LED would replace the time guess with the UPS's own real signal.
**State:** LED behavior mapped. Physical blocker found: the 4 LEDs are only 5mm apart, too tight for discrete sensors + individual light shields. Two options on the table: (A) fiber-optic light pipes to relay light to normally-spaced sensors, or (B) a small camera (ESP32-CAM) reading pixel brightness at known coordinates in software - leaning toward B since it turns a hard mechanical problem into an easier software one. Has spare ESP32s already; no parts bought yet.
**Next step:** decide A vs B, confirm whether an ESP32-CAM is available or needs buying, then get a parts list.

### Power-outage watchdog - validated on a real outage, not yet armed
**Why:** this server runs on its own RouterUPS battery (~3-4hr real runtime), separate from the router's UPS. An uncontrolled crash when the battery dies is the likely cause of the ZFS corruption found in `datapool` (see below) - a clean shutdown before that happens avoids torn writes entirely.
**State:** `watchdog_power.sh` built and cron-wired (every 5 min), detects `enp1s0` losing carrier (proxy for "on battery," via the existing WiFi-failover extender). Defaults to dry-run (logs only, never shuts down) until armed via `touch ~/.power-watchdog-armed`. Confirmed working end-to-end on a real ~20min outage on 2026-07-27: correctly detected carrier loss within one 5-min cron tick, logged elapsed time correctly, and cleared the watch on restore - stayed well under the 90min threshold so nothing fired, as expected. Sudoers script (`setup_power_watchdog_sudoers.sh`) ready but not yet run.
**Next step:** decide when to arm it for real (`touch ~/.power-watchdog-armed` + run `setup_power_watchdog_sudoers.sh`) - probably once the ESP32 LED-based signal replaces the 90min time guess, or sooner if comfortable with the time-based approach alone.

### Local Qwen (Ollama) delegation experiment
**Why:** wanted to test routing trivial subagent tasks to a locally-hosted model (Qwen via Ollama) instead of Anthropic's cloud models, to see if cost/latency can be saved on simple work while keeping a cloud Claude model for anything nontrivial. Manual/semi-automatic invocation is an explicitly acceptable bar for a first pass, full auto-detection would be a bonus.
**State:** researched thoroughly, nothing built yet. Key finding: Claude Code (CLI or the Agent SDK library, which is Claude Code packaged as a library) validates model names against an Anthropic-only allowlist - there is no way, via `ANTHROPIC_BASE_URL`, agent-definition frontmatter, or any env var, to point the main session or a subagent at Ollama or any local model. That rules out the originally-envisioned approach entirely.

The viable path is different: a **standalone script** using the Anthropic SDK's Tool Runner (`client.beta.messages.tool_runner`, not Claude Code at all), where Ollama/Qwen is wrapped as a *custom tool* (e.g. `delegate_to_local_model`) that a cloud Claude model can choose to call based on the tool's description - this gives genuine LLM-driven auto-routing (Claude itself judges what's trivial), which is actually closer to the original ask than manual routing. Tradeoff: this is a bare API loop, not a Claude Code replacement - no chat REPL, no file/bash tools, no session persistence, none of Claude Code's actual UX - all of that would need to be hand-built. The other option considered (Claude Agent SDK, for a closer-to-Claude-Code chat experience) was ruled out because it's the same harness under the hood and almost certainly has the same Anthropic-only model restriction, so it wouldn't solve the actual goal even though it looks closer to "chat normally."
**Next step:** agreed direction is a minimal REPL wrapper around the Tool Runner (conversation loop + history list, not full Claude Code) as a proportionate first experiment. Not yet built - needs a separate `ANTHROPIC_API_KEY` (or `ant auth login`), Ollama running locally with a Qwen model pulled, and the actual script written.

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

### Offsite backup (photos / general)
**Why:** Vaultwarden and HA config are already backed up daily to Dropbox via rclone. Immich's photo data (`datapool/immich-upload`, `datapool/immich-db`) has no offsite copy - only the ZFS pool itself (single disk, see above) and the original Google Takeout zips on a separate local disk.
**State:** not started, lower priority than the ZFS corruption/replication work.
**Next step:** none for now.

### FTP replacement (Syncthing or rclone+Dropbox)
**Why:** wanted a serverless way to drop files onto the homelab, like KeePass doesn't need a server - avoids running/hardening an FTP daemon.
**State:** discussed two options (Syncthing: true peer-to-peer, no cloud dependency, new tool to install; reuse rclone+Dropbox: zero new infra, reuses the trusted backup pattern). Leaned toward extending the existing rclone+Dropbox pattern. Not started.
**Next step:** none, explicitly not highest priority.

### Immich re-enablement
**Why:** ~13k photos already migrated from Google Takeout, but Immich is disabled - 8GB RAM isn't enough with ML enabled.
**State:** parked for "at least a couple quarters" due to the current chip-price spike delaying any hardware upgrade. Fastest partial fix (disable just `immich-machine-learning`, keep the server running without face/object search) was suggested but not applied, since the user wants it parked entirely for now.
**Next step:** revisit once hardware budget/pricing allows. When resumed: recover the 2 corrupted "library" originals (`20170305_135159.jpg`, `GOPR0276.MP4`) from the intact Takeout zips in `/home/pramod/Downloads/` first.

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

### Tinxy watchdog: two-tier recovery + entity-based down-detection
2026-07-27 ISP outage exposed two gaps in `watchdog_tinxy.sh`. (1) Detection only grepped MQTT connect/disconnect log lines - blind to a stalled integration setup that logged nothing distinctive after one of the watchdog's own restarts. Fixed by adding a second signal: querying actual Tinxy entity availability via the HA API, tripping at >=90% unavailable (had to be that high since ~60% of registered entities are *always* unavailable already, from old/decommissioned devices - see backlog item above). (2) Recovery jumped straight to a full `docker restart homeassistant` - now tries a lighter config-entry reload first (what actually fixed the outage) at 20min, only escalating to a full restart at 35min if that doesn't clear it. All three tiers (start watch, reload, escalate to restart) tested live against the real script and real data, including one real end-to-end restart.
