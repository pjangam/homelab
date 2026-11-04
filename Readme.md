> See `PROJECTS.md` for the working list of active/parked/backlog projects and their current state.

This file is about **the machine**: bringing xero up, keeping its OS healthy,
and the quirks of this particular hardware. Everything that belongs to one
project or service is documented in that project's own folder - the index
below is the way in.

---

## Where things live

Four homes, by purpose rather than file type (the rules are in `CLAUDE.md`):

| | |
|---|---|
| [`projects/`](projects/) | code this repo builds - with its scripts, tests, units and setup doc |
| [`services/`](services/) | config for off-the-shelf software we only run |
| [`tools/`](tools/) | helpers used by more than one project |
| [`docs/`](docs/) | reference and incident write-ups not owned by one project |

Docker's live data directories (`vw-data/`, `HOMEASSISTANT_CONFIG/`,
`etc-pihole/`, `postgres/`, `library/`, `certs/`, `backups/`) stay at the root
on purpose, and are gitignored. `clawlight/`, `scripts/`, `systemd/`, `esp32/`
and the `*_buttons_setup.md` files are the projects that deploy to the
wol-sender Pi or the Mac; they move into the layout above in a later session.

### projects/

| | |
|---|---|
| [`aarti-lights`](projects/aarti-lights/README.md) | sound-reactive WS2812B strip behind the makhar (ESP32 + WLED) |
| [`certs-backup`](projects/certs-backup/README.md) | TLS cert renewal, and the encrypted offsite backups |
| [`curtains`](projects/curtains/README.md) | cord-loop curtain drive - design only, not built |
| [`diwali-lights`](projects/diwali-lights/README.md) | WLED door outline |
| [`endpoints`](projects/endpoints/README.md) | the one page listing every endpoint we serve |
| [`ha-dashboard`](projects/ha-dashboard/README.md) | the Home dashboard, tracked and synced over HA's websocket API |
| [`healthcheck`](projects/healthcheck/README.md) | the synthetic healthcheck - silent when healthy, alerts when not |
| [`immich-backup`](projects/immich-backup/README.md) | offsite copy of Immich originals (S3 Glacier Deep Archive) |
| [`lan-gateway`](projects/lan-gateway/README.md) | xero as the LAN gateway, counting bytes per device |
| [`miraie-ac`](projects/miraie-ac/README.md) | the Panasonic AC in HA, via Node-RED on the Pi |
| [`pi-health`](projects/pi-health/README.md) | the wol Pi reporting its own health over MQTT |
| [`power-watchdog`](projects/power-watchdog/README.md) | clean shutdown on an extended power cut (armed) |
| [`projects-ui`](projects/projects-ui/README.md) | the dashboard that renders `PROJECTS.md` at `/projects` |
| [`spotifyd`](projects/spotifyd/README.md) | headless Spotify Connect on the Pi |
| [`tinxy-watchdog`](projects/tinxy-watchdog/README.md) | restarts HA after a sustained ISP-outage disconnect (temporary) |
| [`voice-assistant`](projects/voice-assistant/README.md) | local voice control through HA Assist |
| [`white-noise`](projects/white-noise/README.md) | the bedroom white-noise switch |
| [`wishlist`](projects/wishlist/README.md) | priority-ordered list of expensive things to buy |
| [`xero-stats`](projects/xero-stats/README.md) | xero's stats as p95/max, never averages |

### services/

| | |
|---|---|
| [`albums`](services/albums/README.md) | public photo albums over Tailscale Funnel |
| [`caddy`](services/caddy/README.md) | the HTTPS front door for `xero.<tailnet>` |
| [`chrony`](services/chrony/README.md) | xero as the LAN time server (the Pi has no RTC) |
| [`grafana`](services/grafana/README.md) | graphs of everything xero and the Pi do |
| [`immich`](services/immich/README.md) | self-hosted photos |
| [`mosquitto`](services/mosquitto/README.md) | the MQTT broker every local integration uses |
| [`node-exporter`](services/node-exporter/README.md) | host metrics on both machines, plus the ZFS textfile |
| [`nodered`](services/nodered/README.md) | the flow engine (runs on the Pi) |
| [`ntfy`](services/ntfy/README.md) | self-hosted push notifications, and the alert routing |
| [`pihole-secondary`](services/pihole-secondary/README.md) | the second Pi-hole on the wol Pi |
| [`prometheus`](services/prometheus/README.md) | metrics store behind Grafana |
| [`samba`](services/samba/README.md) | the `phone-uploads` and `documents` SMB shares |
| [`tailscale`](services/tailscale/README.md) | the sidecars that give a service its own tailnet name |
| [`vaultwarden`](services/vaultwarden/README.md) | the password manager every secret here points at |

### tools/

| | |
|---|---|
| [`chromium-update`](tools/chromium-update/README.md) | the Mac's Chromium snapshot updater |
| [`dev-shell`](tools/dev-shell/README.md) | the Mac shell setup (iTerm + tmux + Claude Code) |
| [`diagrams`](tools/diagrams/README.md) | screenshot a wiring diagram to check it before publishing |
| [`esp32-tools`](tools/esp32-tools/README.md) | flashing and bring-up for the WLED boards |
| [`ha-diag`](tools/ha-diag/README.md) | two awkward Home Assistant questions |
| [`heic-convert`](tools/heic-convert/README.md) | HEIC to JPEG, for what lands on the shares |
| [`host-stats`](tools/host-stats/README.md) | the per-second sampler, and the cooling benchmark |
| [`memtest`](tools/memtest/README.md) | RAM testing on xero without a USB stick |
| [`network`](tools/network/README.md) | throughput and DNS diagnosis, including the Mac's recurring break |
| [`notify`](tools/notify/README.md) | the shared email and ntfy senders |
| [`repo-tools`](tools/repo-tools/README.md) | scripts about this repo itself |
| [`zfs`](tools/zfs/README.md) | the ARC cap |

---

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

## Git hooks (leak scanning)

`new_machine_setup.sh` sets `git config core.hooksPath .githooks` so both hooks below are active on every clone - `.git/hooks/` itself is per-clone and untracked, so hooks placed there wouldn't survive a fresh `git clone`.

- **`.githooks/pre-commit`** — scans staged changes for public IPs (private/loopback ranges and well-known DNS resolvers like `8.8.8.8` allowlisted), Tailscale `*.ts.net` hostnames, PII (phone numbers, emails outside a small allowlist), and PCI data (card numbers, Luhn-checked to cut noise). Runs at commit time so a leak never even lands in local history. Added 2026-08-23 - gitleaks (below) only catches credential-shaped secrets, not this class of leak.
- **`.githooks/pre-push`** — runs [gitleaks](https://github.com/gitleaks/gitleaks) against the whole repo history to catch committed credentials/secrets before they reach the remote. Requires `gitleaks` on `PATH`; skips with a warning if it's not installed.

Both print what they found and how to bypass a confirmed false positive: `git commit --no-verify` / `git push --no-verify`.

---

## Home Assistant config

`HOMEASSISTANT_CONFIG/` is gitignored, not part of this repo. It's covered end-to-end by Home Assistant's own automatic backup, synced to Dropbox by `projects/certs-backup/backup_homeassistant.sh` — tracking it in git would just duplicate that and drift out of sync (especially for `custom_components/`, which [HACS](https://hacs.xyz/) installs and updates at runtime: currently spotcast (Apache-2.0), ssh (MIT), tinxy (AGPL-3.0) — install these through HACS, not by copying files).

---

## What runs here

Everything below is on xero unless it says otherwise. Ports and URLs are
indexed in [`projects/endpoints/endpoints.toml`](projects/endpoints/README.md);
the compose file is the root `docker-compose.yml`.

- [x] [Pi-hole](services/pihole-secondary/README.md): ad blocker (a second one runs on the wol Pi)
- [x] [Node-RED](services/nodered/README.md): workflow engine for IoT - **on the wol Pi**
- [x] [MQTT broker (Mosquitto)](services/mosquitto/README.md)
- [x] [Vaultwarden](services/vaultwarden/README.md) (Bitwarden-compatible password manager)
- [~] [Immich](services/immich/README.md): photos - **was disabled on 8 GB RAM**; see its README for the requirement
- [x] Home Assistant
- [x] [Tailscale](services/tailscale/README.md)
- [x] [Caddy](services/caddy/README.md): reverse proxy with TLS
- [x] [Grafana + Prometheus](services/grafana/README.md): graphs
- [x] [ntfy](services/ntfy/README.md): push notifications to the phone
- [x] [Samba](services/samba/README.md): SMB shares for dropping files onto xero, over LAN or tailnet
- [x] [chrony](services/chrony/README.md): LAN time server
- [x] Watchtower: auto-update containers (weekly, Sundays 04:00 UTC). Notes:
  `WATCHTOWER_NO_STARTUP_MESSAGE=true` because its boot banner fires while HA
  is still starting and always failed; and `projects-ui` carries
  `com.centurylinklabs.watchtower.enable=false` because it is built locally,
  so checking it against Docker Hub only ever produced a 401 it could never
  succeed at.
- [x] [Tinxy watchdog](projects/tinxy-watchdog/README.md): auto-restarts HA after sustained ISP-outage disconnects (temporary)
- [x] Immich data redundancy: ZFS mirror for the photo volume - backup is skipped due to size, so disk redundancy is the safety net
- [x] Immich: Google Photos imported via immich-go - 12,913 photos/videos uploaded (22/23 takeout parts). 21 files from part 019 missing, listed in `docs/google_takeout_missing.md`, to be uploaded manually
- [ ] ftp server to dump files
- [ ] ftp backups - compress and encrypt

---

## Automatic OS updates

Regular point-release package updates (`noble-updates`) install automatically via `unattended-upgrades`, which was already handling security updates but not this origin - 53 packages had piled up unapplied (2026-09-01) because `Allowed-Origins` in `/etc/apt/apt.conf.d/50unattended-upgrades` only covered `-security` and GA by default.

**Enable it** (uncomments the `-updates` origin, one-time):
```bash
sudo sed -i '15s|^//\t|\t|' /etc/apt/apt.conf.d/50unattended-upgrades
grep -A1 'codename}-updates' /etc/apt/apt.conf.d/50unattended-upgrades   # confirm uncommented
```

**Reboots stay manual** — `Unattended-Upgrade::Automatic-Reboot` is left `false` (the default). A kernel/library update that needs a reboot just sets `/var/run/reboot-required`; nothing reboots the box on its own. Check it and reboot when convenient:
```bash
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs
```

**Release upgrades (24.04 → 26.04) are never automatic, structurally** — `unattended-upgrades` only ever installs package-level updates within the current release. Moving to a new LTS is a separate, manually-run tool (`do-release-upgrade`), untouched by any of the above.

**26.04 isn't available yet regardless.** Canonical's meta-release feed lists Resolute Raccoon (26.04, released 2026-04-23) but flags it `Supported: 0` - the LTS-to-LTS path only opens once that flips to `1`, independent of any point-release announced elsewhere. Check before attempting:
```bash
do-release-upgrade -c
# or, for the raw flag: curl -fsS http://changelogs.ubuntu.com/meta-release-lts | grep -A1 resolute
```

Timers `apt-daily.timer` / `apt-daily-upgrade.timer` (installed by the `unattended-upgrades` package) drive this daily — `systemctl list-timers apt-daily*` to check next run.

**One-off manual full-upgrade + backup** (`projects/certs-backup/backup_and_apt_update.sh`) — separate from the above, for catching up a large backlog rather than day-to-day patching. Backs up `/etc`, package selections, crontabs, systemd unit state, Docker state, and the `/dev/sdb` partition table to `/datapool/system-backups/pre-update-<timestamp>.tar.gz`, then runs `apt full-upgrade` + `autoremove`. Must run as root (invoke directly, not via `sudo`, in a cron/systemd-run context — see script header for why). Written and tested standalone for the initial 53-package backlog (2026-09-01), but a one-shot `systemd-run --on-calendar` job scheduled to run it never actually fired (no journal entry, no backup produced) - that backlog ended up clearing on its own via `unattended-upgrades` instead once the `-updates` origin was enabled below. Script is real and untested-in-anger since; next large backlog is the actual first live run.

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

Full write-ups live in [`docs/incidents/`](docs/incidents/), one file per incident (symptom/root cause/diagnosis/fix/prevention):

- [`2026-06-29-zfs-postgres-freeze.md`](docs/incidents/2026-06-29-zfs-postgres-freeze.md) — SSH + display dead, Docker still accessible; orphaned `immich_postgres` container deadlocked on ZFS I/O
- [`2026-08-31-white-noise-mqtt-reconnect-loop.md`](docs/incidents/2026-08-31-white-noise-mqtt-reconnect-loop.md) — racy manual MQTT reconnect loop flapping HA switches "unavailable" every ~5s; found in `toggle-button-mqtt.py` (2026-08-25), recurred in `white-noise-mqtt.py` (2026-08-31)
- [`2026-07-23-getty-tty1-crash-loop.md`](docs/incidents/2026-07-23-getty-tty1-crash-loop.md) — `getty@tty1` crash-looped after a reboot changed the console video mode; a hardcoded TTY font choice stopped fitting. Includes a corrected theory ruling this out as the cause of the same-day white-noise bug
- [`2026-09-04-tls-cert-renewal-silently-broken.md`](docs/incidents/2026-09-04-tls-cert-renewal-silently-broken.md) — the monthly `tailscale cert` cron produced no effect for 3 months and was found 5 days from expiry; `sudo` cannot run from this crontab, the `&&`-chain sent the error to unread cron mail, and `tailscale cert` without `--min-validity` returns the cached cert rather than renewing

---

## Known issues

- **SSH login warning** — `Failed to connect to https://changelogs.ubuntu.com/meta-release-lts` appears on every SSH login. Ubuntu's MOTD update checker hits this URL; Pi-hole is not blocking it (verified). Likely a transient timeout or the server being slow — cosmetic and harmless.

- **thefuck** — disabled in `~/.zshrc`. Version 3.32 (latest PyPI release) uses `distutils` and `imp`, both removed in Python 3.12. Fix: `pipx uninstall thefuck && pipx install git+https://github.com/nvbn/thefuck.git && pipx inject thefuck setuptools`, then uncomment in `~/.zshrc`.

## Machine-specific config (Beelink Mini PC, Intel N5105, Lubuntu)
Photos of the inside (the single SO-DIMM slot, the 8GB stick, both SSDs) are in [`docs/images/xero/`](docs/images/xero/).

These fixes are gated behind a CPU model check (`N5105` in `/proc/cpuinfo`) in `new_machine_setup.sh` and won't run on other machines.

- [x] Disable deep CPU C-states — N5105 Jasper Lake has a known Linux kernel bug causing hard freezes (`intel_idle.max_cstate=1` in GRUB)
- [x] Increase swap to 4GB — 512MB default is too low for Docker workloads
- [x] Cap ZFS ARC to 1GB — default max is 6.6GB (87% of RAM), causes kernel panics under load (`echo "options zfs zfs_arc_max=1073741824" | sudo tee /etc/modprobe.d/zfs.conf`)
- [x] Disable USB auto-suspend — Logitech USB receiver disconnects due to Linux USB power management
- [x] Temperature monitoring via Home Assistant — CPU idles at ~65°C, monitor spikes under load







- [x] CPU temperature alert — `healthcheck.sh` emails and pushes to ntfy when the 15-minute peak reaches 90°C (warn) or 98°C (urgent). Alert only; see below for an automatic shutdown.

### Overheating: what protects xero, and a shutdown not yet built

Checked 2026-10-08, after memtest86+ hit 103°C on the pegboard and a RAM bit flipped there.

**What already exists:**
- **The CPU protects itself.** Near TjMax (105°C) it throttles; far past it (a dead fan) it cuts its own power (THERMTRIP). Hardware, always on, so the chip will not cook - but that cut is as abrupt as a power cut.
- **thermald** is running. It manages power limits; it never shuts anything down.
- **The kernel's orderly shutdown does not work here.** Its `critical` trip point (119°C) sits on the `acpitz` zone, which reads a fixed 27.8°C regardless of load. The real CPU sensor is `x86_pkg_temp`, whose zone number changes between boots (find it by type, not number).
- **The alert above.** Nothing acts on it.

**Why not shut down on heat by default:** the damage seen at 100°C+ was RAM errors (silent corruption while xero keeps running), and since the CPU throttles instead of crashing, an overheating xero usually stays up long enough to act on the alert. A shutdown also keeps xero off until someone presses the button: with no power cut there is no Wake-on-LAN trigger, so HA goes dark and DNS falls back to the wol Pi.

**If one is added, the suggestion:** a last-resort rule, a cron job every minute (or a check in `watchdog_power.sh`'s 5-minute run) that runs a clean `shutdown` when `x86_pkg_temp` stays at **100°C or more for 5 minutes**. Heavy but normal loads (a build, memtester) stay under it; a stopped fan or a blocked vent does not. It can reuse the power watchdog's passwordless sudo rule for `/usr/sbin/shutdown`, and its arm/disable flag pattern (dry run until armed). Alert on the way down (email + ntfy), and log to `journalctl` like the power watchdog. Before arming, dry-run it through a real load test to check normal work never trips it.
