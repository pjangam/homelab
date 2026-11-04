# spotifyd (headless Spotify Connect)

Spotify Connect with no GUI, so HA scripts and the phone can play to the
bedroom speaker. It runs **on the wol-sender Pi** since the 2026-09-24 audio
move; the setup below is xero's, which is where it was first built and where
the disabled units still sit.

| | |
|---|---|
| **Unit** | `spotifyd.service` (`systemd --user`, needs `loginctl enable-linger`) |
| **Boot race guard** | `wait_for_network.sh` (`-` prefixed in the unit, so a missed copy is silent) |
| **Watchdog** | `watchdog_spotifyd.sh`, */5 on the Pi via `deploy_watchdog_pi.sh` |
| **Is it advertising?** | `check_spotifyd_advertising.sh` (avahi over the LAN, so xero can watch the Pi) |
| **Dashboard tile** | `apply_spotifyd_advertising_dashboard_tile.sh` |
| **Build for the Pi** | `build_spotifyd_arm64.sh`, `build_spotifyd_on_pi.sh`, `install_raspotify_pi.sh` |


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

**Troubleshooting:**
- **Stuck "active" but throwing 429/websocket errors** - just restart it: `systemctl --user restart spotifyd`.
- **"xero" doesn't show up as a Connect device in the Spotify app** - check for a zeroconf/mDNS failure: `journalctl --user -u spotifyd -b | grep libmdns`. An `Setting up dns-sd failed: No such device (os error 19)` line means spotifyd's mDNS advertisement is silently failing on every startup (it logs this and keeps running normally otherwise, so nothing else looks wrong). Root cause found 2026-09-02: an orphaned Docker network interface (`docker network ls`, look for a bridge with 0 containers) broke libmdns's interface enumeration entirely. Remove the orphaned network (`docker network rm <name>`) and `systemctl --user restart spotifyd` - see `docs/incidents/2026-09-02-spotifyd-zeroconf-broken-by-orphaned-docker-network.md`.

