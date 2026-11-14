# spotifyd (headless Spotify Connect)

Spotify Connect with no GUI, so HA scripts and the phone can play to the
bedroom speaker. It runs on **both** hosts: the wol-sender Pi (`raspberrypi`,
the bedroom speaker, since the 2026-09-24 audio move; Play Bedroom Track
targets it) and xero (`xero`, enabled again since 2026-10-27). Keep both
enabled. The setup below is xero's, which is where it was first built.

| | |
|---|---|
| **Unit** | `spotifyd.service` (`systemd --user`, needs `loginctl enable-linger`) |
| **Boot race guard** | `wait_for_network.sh` (`-` prefixed in the unit, so a missed copy is silent) |
| **Watchdog** | `watchdog_spotifyd.sh`, */5 on the Pi via `deploy_watchdog_pi.sh` |
| **Is it advertising?** | `check_spotifyd_advertising.sh` (avahi over the LAN; `8 raspberrypi --remote` watches the Pi from xero) |
| **Does Spotify still list it?** | `check_spotify_listed.sh <name>` (HA's spotcast devices sensor - catches the dead-websocket state where it advertises but the app can't see it) |
| **Listed watchdog (xero cron, */5)** | `watchdog_spotify_listed.sh`: restarts xero's or the Pi's (over ssh) spotifyd when Spotify has lost it for 15min, once an hour at most; tested by `test_watchdog_spotify_listed.sh` |
| **Pi in the healthcheck** | `check_pi_spotifyd.sh`, called by `healthcheck.sh` for the "Homelab Spotifyd (wol Pi)" tile |
| **Dashboard tile** | `apply_spotifyd_advertising_dashboard_tile.sh` |
| **xero's speaker: Bluetooth reconnect (cron, every minute)** | `bt_speaker_reconnect.sh`: connects the Portronics Apollo One if it is not, and makes it PipeWire's default output; `--dry-run` reports only. Log: `~/code/homelab/bt-speaker-reconnect.log` |
| **xero's speaker: reconnect on voice play** | `bt_speaker_mqtt.py` as `bt-speaker-mqtt.service` (`systemd --user`): HA publishes `bt_speaker_xero/connect`, it reconnects and answers on `bt_speaker_xero/state` |
| **Build for the Pi** | `build_spotifyd_arm64.sh`, `build_spotifyd_on_pi.sh`, `install_raspotify_pi.sh` |


Running spotifyd as a Spotify Connect daemon — no GUI needed.

### xero's speaker is Bluetooth (since 2026-11-14)

| | |
|---|---|
| **Speaker** | Portronics Apollo One, `0D:67:1F:80:92:22`, paired and trusted on xero's Intel Bluetooth (`hci0`) |
| **Why not AUX** | It boots into Bluetooth mode. AUX comes back only with its M button or a cable reseat; audio on the line does not switch it (tested 2026-11-14), so "plays but silent" needed a hand every time |
| **Path** | spotifyd -> ALSA `default` -> PipeWire (pipewire-alsa) -> default sink = the Apollo One |
| **Volume** | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.18`, or HA's "xero Speaker Volume" slider (`volume-mqtt` with `VOLUME_DEVICE=pipewire`) |
| **Fallback** | When the speaker is away, PipeWire falls back to the USB adapter (card 1); the reconnect script sets the speaker back as default |

Install on xero (already done 2026-11-14):
1. `bluetoothctl pair 0D:67:1F:80:92:22 && bluetoothctl trust 0D:67:1F:80:92:22` (speaker on, in Bluetooth mode)
2. `crontab -e`: `* * * * * /home/pramod/code/homelab/projects/spotifyd/bt_speaker_reconnect.sh >> /home/pramod/code/homelab/bt-speaker-reconnect.log 2>&1`
3. `cp projects/spotifyd/bt-speaker-mqtt.service ~/.config/systemd/user/ && systemctl --user daemon-reload && systemctl --user enable --now bt-speaker-mqtt`

Traps:
- **`bluetoothctl --timeout N connect` always takes N seconds**, even after connecting. The script polls `bluetoothctl info` instead; with the timeout a voice "play" took 20s, now ~5s.
- **cron has no session env**: `wpctl` needs `XDG_RUNTIME_DIR`, which the script sets.
- **One source at a time**: while xero holds the speaker, the phone cannot pair to it directly. Play to `xero` from the Spotify app instead.

### Original AUX setup (2026-08, superseded on xero)

The speaker used to be on the USB adapter's headphone jack (USB Audio Device / C-Media chip, card 1).

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

**Volume:** see the Bluetooth table above (`wpctl`, or the HA slider).

**Troubleshooting:**
- **Stuck "active" but throwing 429/websocket errors** - just restart it: `systemctl --user restart spotifyd`.
- **"xero" doesn't show up as a Connect device in the Spotify app** - check for a zeroconf/mDNS failure: `journalctl --user -u spotifyd -b | grep libmdns`. An `Setting up dns-sd failed: No such device (os error 19)` line means spotifyd's mDNS advertisement is silently failing on every startup (it logs this and keeps running normally otherwise, so nothing else looks wrong). Root cause found 2026-09-02: an orphaned Docker network interface (`docker network ls`, look for a bridge with 0 containers) broke libmdns's interface enumeration entirely. Remove the orphaned network (`docker network rm <name>`) and `systemctl --user restart spotifyd` - see `docs/incidents/2026-09-02-spotifyd-zeroconf-broken-by-orphaned-docker-network.md`.

