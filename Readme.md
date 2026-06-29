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
3. **Tailscale** — `sudo tailscale up` and follow the auth URL, then re-run the script so `tailscale cert` can generate the SSL cert for Caddy
4. **Reboot** — required for the C-state GRUB fix to take effect (N5105 machines only)

---

## Miraie AC (Node-RED + MQTT)

Mosquitto and the `node-red-contrib-ha-miraie-ac` node are set up automatically. Manual steps after first run:

1. Open Node-RED at `http://192.168.1.123:1880`
2. Find the `ha-miraie-ac` node in the palette (left sidebar), drag it into a flow
3. Double-click the node and configure:
   - **Mobile number** — Miraie registered phone number
   - **Password** — Miraie app password
   - **MQTT broker** — host `mosquitto`, port `1883` (no username/password)
4. Click Deploy (top right) — node status should show "HA broker connected" and "MirAIe broker connected"
5. In Home Assistant: Settings → Integrations → Add Integration → MQTT → host `192.168.1.123`, port `1883`, no credentials
6. AC appears under Settings → Devices & Services → MQTT as "PANASONIC AC"
7. If entity shows "Unavailable", turn the AC on/off physically to trigger a state update

> Mosquitto has no authentication (`allow_anonymous true`). Fine for homelab, can add credentials later.

> **TODO (deferred): Full automation approach**
> 1. Store Miraie credentials in Bitwarden
> 2. On setup, pull them via Bitwarden CLI (`bw get item "Miraie AC"`)
> 3. Export working Node-RED flow as `nodered-flows.json` in repo, inject credentials and POST to Node-RED API
> 4. Set up HA MQTT integration via HA REST API using a long-lived token (no Selenium needed)
> 5. Only manual step: generate the HA long-lived token once

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

**Setup** (run after a fresh install or if font resets):
```bash
~/code/homelab/set_console_font.sh
```

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







