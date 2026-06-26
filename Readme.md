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

## Known issues

- **thefuck** — disabled in `~/.zshrc`. Version 3.32 (latest PyPI release) uses `distutils` and `imp`, both removed in Python 3.12. Fix: `pipx uninstall thefuck && pipx install git+https://github.com/nvbn/thefuck.git && pipx inject thefuck setuptools`, then uncomment in `~/.zshrc`.

## Machine-specific config (Beelink Mini PC, Intel N5105, Lubuntu)
These fixes are gated behind a CPU model check (`N5105` in `/proc/cpuinfo`) in `new_machine_setup.sh` and won't run on other machines.

- [x] Disable deep CPU C-states — N5105 Jasper Lake has a known Linux kernel bug causing hard freezes (`intel_idle.max_cstate=1` in GRUB)
- [x] Increase swap to 4GB — 512MB default is too low for Docker workloads
- [x] Cap ZFS ARC to 1GB — default max is 6.6GB (87% of RAM), causes kernel panics under load (`echo "options zfs zfs_arc_max=1073741824" | sudo tee /etc/modprobe.d/zfs.conf`)
- [x] Disable USB auto-suspend — Logitech USB receiver disconnects due to Linux USB power management
- [x] Temperature monitoring via Home Assistant — CPU idles at ~65°C, monitor spikes under load







