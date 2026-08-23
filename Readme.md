> See `PROJECTS.md` for the working list of active/parked/backlog projects and their current state.

## New Machine Setup

Run `new_machine_setup.sh` then complete these manual steps:

1. **Rclone / Dropbox** — `rclone config` (name the remote `backup`), then create `.env.backup`:
   ```
   BACKUP_PASSPHRASE='your-passphrase'
   ```
2. **Secrets** — create `.env` (gitignored) with service passwords:
   ```
   PIHOLE_PASSWORD=<your-password>
   ```
   Pi-hole password is stored in `.env` on the server (not in git). Check Bitwarden for the current value.
3. **Tailscale** — `sudo tailscale up` and follow the auth URL, then re-run the script so `tailscale cert` can generate the SSL cert for Caddy. The script will prompt for your tailnet's domain suffix (e.g. `tailXXXXX.ts.net`, shown in the Tailscale admin console) on first run and save it to `.env` as `TAILNET_SUFFIX`.
4. **Reboot** — required for the C-state GRUB fix to take effect (N5105 machines only)

---

## Home Assistant config

`HOMEASSISTANT_CONFIG/` is gitignored, not part of this repo. It's covered end-to-end by Home Assistant's own automatic backup, synced to Dropbox by `cron/backup_homeassistant.sh` — tracking it in git would just duplicate that and drift out of sync (especially for `custom_components/`, which [HACS](https://hacs.xyz/) installs and updates at runtime: currently spotcast (Apache-2.0), ssh (MIT), tinxy (AGPL-3.0) — install these through HACS, not by copying files).

---

## Miraie AC (Node-RED + MQTT)

Mosquitto runs on `xero`; Node-RED itself runs on the Pi (`wol-sender`, `192.168.1.124`) - moved there 2026-08-22, see `PROJECTS.md` "Move some load to the Raspberry Pi". The `node-red-contrib-ha-miraie-ac` node is set up automatically. Manual steps after first run:

1. Open Node-RED at `http://192.168.1.124:1880` - the editor now requires login (`adminAuth` in `settings.js`, enabled 2026-08-22 since it's reachable over Wi-Fi rather than only from xero itself; previously had no auth at all). Username `pramod`; the password should be saved in Vaultwarden as "Node-RED admin" (check there first - if missing, it was generated during the 2026-08-22 migration and needs resetting via `node-red admin hash-pw` + editing `settings.js`'s `adminAuth` block on the Pi).
2. Find the `ha-miraie-ac` node in the palette (left sidebar), drag it into a flow
3. Double-click the node and configure:
   - **Mobile number** — Miraie registered phone number
   - **Password** — Miraie app password
   - **MQTT broker** — host `192.168.1.123` (xero's LAN IP - Node-RED isn't on the same Docker network as Mosquitto anymore, so the `mosquitto` container hostname won't resolve), port `1883`, username `homelab` + password (Mosquitto requires auth as of the 2026-08-23 security pass — see Vaultwarden "Mosquitto MQTT")
4. Click Deploy (top right) — node status should show "HA broker connected" and "MirAIe broker connected". If credentials were entered via the node's config panel, they must land nested under the node's "credentials" store, not as flat fields - if the broker doesn't connect after Deploy, a full container restart (`docker restart node-red`), not just a redeploy, may be needed to pick them up.
5. In Home Assistant: Settings → Integrations → Add Integration → MQTT → host `192.168.1.123`, port `1883`, username `homelab` + password
6. AC appears under Settings → Devices & Services → MQTT as "PANASONIC AC"
7. If entity shows "Unavailable", turn the AC on/off physically to trigger a state update

> **TODO (deferred): Full automation approach**
> 1. Store Miraie credentials in Bitwarden
> 2. On setup, pull them via Bitwarden CLI (`bw get item "Miraie AC"`)
> 3. Export working Node-RED flow as `nodered-flows.json` in repo, inject credentials and POST to Node-RED API
> 4. Set up HA MQTT integration via HA REST API using a long-lived token (no Selenium needed)
> 5. Only manual step: generate the HA long-lived token once

### Node-RED Watchdog (MQTT bridge health)

**Why:** the `ha-miraie-ac` node can end up in a stale connection loop - confirmed once (2026-08-23), where credentials were correctly stored but the live MQTT connection to Mosquitto kept silently failing until a full container restart, not just a flow redeploy. `watchdog_nodered.sh` (on the Pi) checks the container's actual TCP state and restarts it if the bridge isn't connected.

**How it works:**
1. Every 10 minutes (cron, on the Pi), the script checks `/proc/net/tcp` inside the `node-red` container for two ESTABLISHED connections: one to MirAIe's cloud MQTT broker (port 8883) and one to Mosquitto on xero (port 1883).
2. If either is missing, it runs `docker restart node-red`.
3. Deliberately does **not** wait for AC state/availability MQTT messages (the original design) - Node-RED only publishes those once per reconnect (not retained by the node's own code), so nothing arrives while the AC is powered off, which is most of the year outside summer. That caused a false restart on every single run regardless of actual bridge health.
4. All actions logged via `logger -t nodered-watchdog` (`journalctl -t nodered-watchdog`) and to `nodered-watchdog.log` on the Pi.

**Currently disabled** (2026-08-23) - the AC is off for the season, so there's nothing for this watchdog to protect against; it's fully skipped rather than left running against a bridge nobody needs connected right now.

**Disable / re-enable** (no need to touch cron; edit on the Pi): the toggle lives in `WATCHDOG_ENABLED` inside `/home/pramod/nodered-watchdog.env`, next to the script itself - a plain env file rather than a hidden dotfile, so it's easier to stumble on again next summer.
```bash
# on the Pi: edit /home/pramod/nodered-watchdog.env
WATCHDOG_ENABLED=false   # disable (e.g. AC off for the season)
WATCHDOG_ENABLED=true    # re-enable (e.g. before summer AC season)
```

**Cron entry** (`crontab -e` on the Pi):
```
*/10 * * * * /home/pramod/watchdog_nodered.sh >> /home/pramod/nodered-watchdog.log 2>&1
```

---

## Baby Monitor (Alfred Camera → Home Assistant)

Currently using **Alfred Camera** on iPhone. No native HA integration exists yet.

**Features in use:** low light mode, motion detection alerts, sound alerts.

**Approach under consideration — bridge Alfred alerts to HA via iOS Shortcuts:**
- Alfred detects motion/sound → sends push notification to iPhone
- iOS Shortcuts automation fires on Alfred notification → sends HTTP POST to HA webhook
- HA webhook triggers automations (lights, alerts on other devices, etc.)
- Low light mode stays Alfred's job — no HA integration needed for that

**HA side (webhook automation skeleton):**
```yaml
automation:
  - alias: "Alfred Motion Alert"
    trigger:
      - platform: webhook
        webhook_id: alfred_motion
    action:
      - ... # e.g. notify, turn on light
```
Webhook URL: `http://<ha-ip>:8123/api/webhook/alfred_motion`

**iOS Shortcuts side:**
1. Shortcuts → Automation → New Automation
2. Trigger: App → Alfred → "Notification received"
3. Action: Get Contents of URL → POST to HA webhook URL
4. Create separate automations for motion and sound (filter by notification text)

**Other options ruled out:**
- RTSP server apps on iPhone — iOS restricts background network servers, unreliable
- New hardware — not preferred
- Alfred web viewer — laggy and buggy

---

## White Noise (Home Assistant Switch)

How the HA white noise switch works, end to end:

1. **HA MQTT switch** — `switch.white_noise` is created via MQTT discovery (no YAML entity config needed); toggling it publishes `ON`/`OFF` to `whitenoise/set` on the local Mosquitto broker (`localhost:1883`, container name `mosquitto`)
2. **MQTT bridge** (`scripts/white-noise-mqtt.py`) — a `uv run --script` (deps declared inline, no venv to manage) that subscribes to `whitenoise/set`, translates it into systemctl calls, and publishes retained state/availability back to `whitenoise/state` / `whitenoise/available` so HA reflects reality instantly instead of polling (`systemd/user/white-noise-mqtt.service`)
3. **systemctl** — starts/stops the `white-noise` user service (`systemd/user/white-noise.service`), which runs `sox` (`play -n -q synth brownnoise fade t 60`, `sudo apt install sox`) directly. SoX's own `fade` effect ramps volume in over ~60s in software — no wrapper script needed. The unit's `ExecStartPre`/`ExecStop` pin the ALSA `Speaker` control (card 1, the USB speaker pinned as default in `~/.asoundrc`) to a fixed 59% ceiling and do a quick ~1.2s ALSA ramp-down before killing the process on stop, so it doesn't cut out abruptly. This is the point to tune if you want a different fade timing or volume range.

Both `white-noise.service` and `white-noise-mqtt.service` are `systemd --user` units, so `loginctl enable-linger pramod` must be set — otherwise they die whenever the login session they started under ends, and the HA switch silently stops responding (this bit us once: see git history).

**Install / reinstall:**
```bash
cp systemd/user/white-noise.service      ~/.config/systemd/user/
cp systemd/user/white-noise-mqtt.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now white-noise-mqtt
sudo loginctl enable-linger pramod
```

---

## Tinxy Watchdog (ISP-outage auto-restart)

**Why:** a flood damaged nearby ISP infra, causing frequent connectivity drops. Tinxy is cloud-push (MQTT to `mqtt.tinxy.in`), so every ISP blip makes all Tinxy devices show "unavailable" in HA until the MQTT client reconnects on its own. `watchdog_tinxy.sh` restarts the `homeassistant` container only if that reconnect doesn't happen — it's a bandage for the ISP issue, meant to be disabled once it's resolved.

**How it works:**
1. Every 5 minutes (cron), the script tails `HOMEASSISTANT_CONFIG/home-assistant.log` for the Tinxy coordinator's own signal lines: `Tinxy: MQTT disconnected – marking all N relays offline` (down) vs `Tinxy MQTT: connected to ...` (up).
2. If the most recent of those two lines is a "disconnected", it starts a clock in `~/.cache/tinxy-watchdog/down-since`.
3. Only after **20 continuous minutes** of disconnection does it run `docker restart homeassistant` — short blips (the common case with a flaky ISP) resolve on their own and never trigger a restart. After restarting, it resets the clock so it won't restart again for another 20 minutes if the ISP is still down.
4. All actions are logged via `logger -t tinxy-watchdog` (`journalctl -t tinxy-watchdog`) and to `tinxy-watchdog.log` in the repo root.

**Disable / re-enable** (no need to touch cron):
```bash
touch ~/.tinxy-watchdog-disabled   # disable
rm ~/.tinxy-watchdog-disabled      # re-enable
```

**Cron entry** (`crontab -e`):
```
*/5 * * * * /home/pramod/code/homelab/cron/watchdog_tinxy.sh >> /home/pramod/code/homelab/tinxy-watchdog.log 2>&1
```

---

## Power Watchdog (clean shutdown on extended outage)

**Why:** this server runs on its own UPS battery (separate from the router's). If the battery fully drains before mains returns, the server crashes uncontrolled - the likely cause of ZFS corruption found in `datapool` on 2026-07-12. `watchdog_power.sh` shuts the server down cleanly well before that happens instead.

**How it works:**
1. Every 5 minutes (cron), checks `/sys/class/net/enp1s0/carrier` - `enp1s0` connects through a WiFi extender with no battery backup of its own, so losing carrier is a reliable proxy for "mains is out, running on UPS battery."
2. On carrier loss, starts a clock in `~/.cache/power-watchdog/down-since`.
3. Once down for **200 minutes** (`DOWN_THRESHOLD_MIN` in the script), runs `sudo /usr/sbin/shutdown -h now`. This threshold is grounded in a real measurement: a live outage test on 2026-07-31 found actual UPS runtime under this server's load is ~288 minutes (4h49m), so 200min leaves ~88min of real margin.
4. All actions logged via `logger -t power-watchdog` (`journalctl -t power-watchdog`) and to `power-watchdog.log` in the repo root.

**Currently armed** - this will actually shut the server down on a real extended outage, not just log.

**Arm / disarm** (no need to touch cron):
```bash
touch ~/.power-watchdog-armed        # arm (enables the real shutdown)
rm ~/.power-watchdog-armed           # disarm (back to dry-run/logging only)
touch ~/.power-watchdog-disabled     # fully disable (skips the check entirely)
rm ~/.power-watchdog-disabled        # re-enable
```

Arming for the first time also requires a one-time sudoers setup (installed by `new_machine_setup.sh`) granting passwordless sudo for `/usr/sbin/shutdown -h now` only, since the watchdog runs unattended from cron.

**Known gap:** a graceful shutdown here doesn't automatically solve "how does the server turn back on" once mains returns - since the UPS keeps the server's PSU continuously powered throughout (before, during, and after the shutdown), the BIOS's "Restore on AC Power Loss" setting never actually triggers (it only fires on a genuine AC-loss-then-restore event at the PSU, which doesn't happen here). See the "Power-outage watchdog" entry in `PROJECTS.md` for the current plan (Wake-on-LAN via a mains-powered ESP32, in progress under `esp32/wol_on_boot/`).

**Cron entry** (`crontab -e`):
```
*/5 * * * * /home/pramod/code/homelab/cron/watchdog_power.sh >> /home/pramod/code/homelab/power-watchdog.log 2>&1
```

---

## Vaultwarden

Signups are currently **disabled** (`SIGNUPS_ALLOWED: "false"` in `docker-compose.yml`). To allow a new account, temporarily set it to `"true"`, run `sudo docker compose up -d vaultwarden`, create the account, then set it back to `"false"`.

---

## Services to run

- [x] Pi-hole: ad blocker
- [x] Node-RED: workflow engine for IoT
- [x] MQTT broker (Mosquitto)
- [x] Vaultwarden (Bitwarden-compatible password manager)
- [~] Immich: photos — **disabled, 8 GB RAM insufficient** (see below)
- [x] Home Assistant
- [x] Tailscale
- [x] Caddy: reverse proxy with TLS
- [x] Watchtower: auto-update containers
- [x] Tinxy watchdog: auto-restarts HA after sustained ISP-outage disconnects (temporary, see below)
- [ ] ftp server to dump files
- [ ] ftp backups — compress and encrypt
- [x] Immich data redundancy: ZFS mirror for the photo volume — backup is skipped due to size, so disk redundancy is the safety net
- [x] Immich: Google Photos imported via immich-go — 12,913 photos/videos uploaded (22/23 takeout parts). 21 files from part 019 missing, listed in `google_takeout_missing.md`, to be uploaded manually.
  - [ ] Bhakti user not able to connect to exit node

## Immich hardware requirements

Immich + its ML container + Postgres + Redis + the rest of the stack causes kernel panics on 8 GB RAM due to memory exhaustion. **Immich is disabled in docker-compose.yml until hardware is upgraded.**

Data is safe on the ZFS pool: `datapool/immich-upload` (15 GB), `datapool/immich-db` (133 MB).

To re-enable, uncomment the `immich-server`, `immich-machine-learning`, `redis`, `database` services and the `model-cache` volume in `docker-compose.yml`.

Options to bring Immich back:
- **Add RAM to this machine** — 16 GB minimum recommended
- **Dedicated machine** — run Immich on a separate device (Raspberry Pi 5 with 8 GB works)
- **Disable ML only** — comment out just `immich-machine-learning`; server runs with much less RAM but no face/object recognition

## Spotify (headless)

Running spotifyd as a Spotify Connect daemon — no GUI needed. Speakers connected to headphone jack (USB Audio Device / C-Media chip, card 1).

**Install:**
```bash
# download spotifyd binary from https://github.com/Spotifyd/spotifyd/releases
mkdir -p ~/.local/bin
mv spotifyd ~/.local/bin/spotifyd
chmod +x ~/.local/bin/spotifyd
```

**Config:** `~/.config/spotifyd/spotifyd.conf`
```toml
[global]
username = "your-spotify-email"
password = "your-spotify-password"
device_name = "xero"
device_type = "computer"
backend = "alsa"
device = "default"
volume_controller = "softvol"
bitrate = 320
cache_path = "/home/pramod/.cache/spotifyd"
no_audio_cache = false
```

**ALSA routing** (`~/.asoundrc`) — points `default` to card 1 (headphone jack):
```
defaults.pcm.card 1
defaults.ctl.card 1
```

**Systemd user service:** `~/.config/systemd/user/spotifyd.service`
```ini
[Unit]
Description=Spotifyd - Spotify Connect daemon
After=network-online.target sound.target

[Service]
ExecStart=/home/pramod/.local/bin/spotifyd --no-daemon
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
```

**Enable:**
```bash
sudo usermod -aG audio pramod   # required — without this ALSA sees no devices
# log out and back in (or reboot) for group to take effect
systemctl --user enable --now spotifyd
```

**Usage:** "xero" appears as a Spotify Connect device in the Spotify app. Select it to play through the speakers.

**Volume:**
```bash
amixer sset Master 50%
```

---

## Memory management

System has 7.6 GB RAM running Docker services + occasional desktop use. Without these mitigations, the system hard-freezes (even SSH unresponsive) under memory pressure.

**Increase swap to 4 GB** (default 512 MB is too small):
```bash
sudo swapoff /swapfile
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# verify:
swapon --show
```
No fstab change needed — the existing entry is size-agnostic.

**Install earlyoom** (kills the biggest memory hog before the kernel freezes):
```bash
sudo apt install -y earlyoom
sudo systemctl enable --now earlyoom
# config: /etc/default/earlyoom
```

**Switch to CLI-only boot** (frees ~4.5 GB — Chrome, VS Code, Spotify):
```bash
# set CLI as default boot target
sudo systemctl set-default multi-user.target

# start desktop on demand when needed
sudo systemctl start graphical.target
```

## TTY console font (powerline)

The TTY uses a Terminus powerline PSF font so that oh-my-zsh agnoster theme renders correctly (git branch icon, arrow separators).

**Setup** (run after a fresh install or if font resets): the N5105-specific block in `new_machine_setup.sh` installs this automatically; re-run that script to reapply it.

**How it works:**
- GRUB sets framebuffer to 1024×768 (`GRUB_GFXMODE=1024x768x32`, `GRUB_GFXPAYLOAD_LINUX=keep`) — makes the font readable
- Script downloads Terminus powerline PSF from `powerline/fonts` GitHub repo, tries v24b→v16b, picks largest size KDFONTOP accepts
- Font persisted in `/etc/default/console-setup` via `FONT=` variable

**Constraint:** The Linux VGA text console's `KDFONTOP` ioctl only accepts 8px-wide fonts. Terminus powerline fonts ≥v18b are 10–14px wide and fail. Only v16b (8×16px) is guaranteed to load; larger sizes may work at 1024×768.

---

## Past incidents

### 2026-06-29: System freeze — SSH + display dead, Docker still accessible

**Symptom:** SSH unreachable, display blank, but Docker containers accessible on the network. Required hard power cycle to recover.

**Root cause:** `immich_postgres` was an orphaned container — Immich was commented out in `docker-compose.yml` but its containers were still running from a previous enable. Postgres got stuck in a ZFS I/O deadlock for ~55 hours (kernel soft lockup on CPU#3), eventually making SSH and display unresponsive. The kernel network stack stayed alive, so containers remained reachable.

**Diagnosis:**
```bash
journalctl -b -1 | grep "soft lockup"
# watchdog: BUG: soft lockup - CPU#3 stuck for 200169s! [postgres:24853]
```

**Fixes applied:**
- Removed orphaned containers: `docker compose down --remove-orphans && docker compose up -d`
- Added soft lockup panic so future lockups auto-reboot instead of hanging:
  ```bash
  echo "kernel.softlockup_panic=1" | sudo tee /etc/sysctl.d/99-softlockup.conf
  sudo sysctl -p /etc/sysctl.d/99-softlockup.conf
  ```

**Prevention:** After commenting out services in `docker-compose.yml`, always run `docker compose down --remove-orphans` — `docker compose up -d` alone does not stop containers removed from the file.

---

## Known issues

- **SSH login warning** — `Failed to connect to https://changelogs.ubuntu.com/meta-release-lts` appears on every SSH login. Ubuntu's MOTD update checker hits this URL; Pi-hole is not blocking it (verified). Likely a transient timeout or the server being slow — cosmetic and harmless.

- **thefuck** — disabled in `~/.zshrc`. Version 3.32 (latest PyPI release) uses `distutils` and `imp`, both removed in Python 3.12. Fix: `pipx uninstall thefuck && pipx install git+https://github.com/nvbn/thefuck.git && pipx inject thefuck setuptools`, then uncomment in `~/.zshrc`.

## Machine-specific config (Beelink Mini PC, Intel N5105, Lubuntu)
These fixes are gated behind a CPU model check (`N5105` in `/proc/cpuinfo`) in `new_machine_setup.sh` and won't run on other machines.

- [x] Disable deep CPU C-states — N5105 Jasper Lake has a known Linux kernel bug causing hard freezes (`intel_idle.max_cstate=1` in GRUB)
- [x] Increase swap to 4GB — 512MB default is too low for Docker workloads
- [x] Cap ZFS ARC to 1GB — default max is 6.6GB (87% of RAM), causes kernel panics under load (`echo "options zfs zfs_arc_max=1073741824" | sudo tee /etc/modprobe.d/zfs.conf`)
- [x] Disable USB auto-suspend — Logitech USB receiver disconnects due to Linux USB power management
- [x] Temperature monitoring via Home Assistant — CPU idles at ~65°C, monitor spikes under load







