# White noise (Home Assistant switch)

A `sox`-generated brown-noise track for the bedroom, exposed to HA as
`switch.white_noise` over MQTT. The switch, its MQTT bridge and the volume
bridge are `systemd --user` units; the physical buttons that also drive it are
in [`scripts/pi-buttons/`](../../scripts/pi-buttons/README.md).

> **Host note:** the service moved from xero to the wol-sender Pi on
> 2026-09-24 (`deploy_audio_pi.sh`). The walk-through below still describes
> xero's paths and card numbers - rewriting it for the Pi is step 2 of
> "Pi audio move follow-ups" in `PROJECTS.md`, together with removing xero's
> now-disabled copies. The mechanism is unchanged; only the host is.

| | |
|---|---|
| **HA entity** | `switch.white_noise` (MQTT discovery, no YAML) |
| **Topics** | `whitenoise/set`, `whitenoise/state`, `whitenoise/available` (retained) |
| **Bridge** | `white-noise-mqtt.py` + `.service` (`uv run --script`) |
| **Player** | `white-noise.service` - `sox` brown noise with a 60s software fade |
| **Volume** | `volume-mqtt.py` + `.service` |
| **Skip tonight's auto-off** | `skip_white_noise_auto_off_tonight.sh` |
| **Deploy to the Pi** | `deploy_audio_pi.sh`, `install_audio_packages_pi.sh` |


How the HA white noise switch works, end to end:

1. **HA MQTT switch** — `switch.white_noise` is created via MQTT discovery (no YAML entity config needed); toggling it publishes `ON`/`OFF` to `whitenoise/set` on the local Mosquitto broker (`localhost:1883`, container name `mosquitto`)
2. **MQTT bridge** (`projects/white-noise/white-noise-mqtt.py`) — a `uv run --script` (deps declared inline, no venv to manage) that subscribes to `whitenoise/set`, translates it into systemctl calls, and publishes retained state/availability back to `whitenoise/state` / `whitenoise/available` so HA reflects reality instantly instead of polling (`projects/white-noise/white-noise-mqtt.service`)
3. **systemctl** — starts/stops the `white-noise` user service (`projects/white-noise/white-noise.service`), which runs `sox` (`play -n -q synth brownnoise fade t 60`, `sudo apt install sox`) directly. SoX's own `fade` effect ramps volume in over ~60s in software — no wrapper script needed. The unit's `ExecStartPre`/`ExecStop` pin the ALSA `Speaker` control (card 1, the USB speaker pinned as default in `~/.asoundrc`) to a fixed 59% ceiling (about 67 dB at the bed, measured 2026-09-24; the wol Pi's 3.5mm jack uses 93%, set with the fade steps in `deploy_audio_pi.sh`) and do a quick ~1.2s ALSA ramp-down before killing the process on stop, so it doesn't cut out abruptly. This is the point to tune if you want a different fade timing or volume range. It also pauses Spotify first with `playerctl -p spotifyd pause` (`sudo apt install playerctl`) so white noise never starts over music; when spotifyd has no active Connect session it has no MPRIS player to pause, and the journal's "No players found" from that line is expected. `projects/white-noise/test_white_noise_pauses_spotify.sh` checks it end to end with a real playing track (it makes sound for ~20s).

Both `white-noise.service` and `white-noise-mqtt.service` are `systemd --user` units, so `loginctl enable-linger pramod` must be set — otherwise they die whenever the login session they started under ends, and the HA switch silently stops responding (this bit us once: see git history).

**Install / reinstall:**
```bash
cp projects/white-noise/white-noise.service      ~/.config/systemd/user/
cp projects/white-noise/white-noise-mqtt.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now white-noise-mqtt
sudo loginctl enable-linger pramod
```

**Starting/stopping directly (bypassing HA/MQTT):**
```bash
systemctl --user start white-noise   # fades in, pins volume to 59%
systemctl --user stop  white-noise   # fades out, kills sox, resets volume to 59%
```
Always go through `systemctl`, never run the `ExecStartPre`/`ExecStop` lines from `white-noise.service` by hand — `kill $MAINPID` in the `ExecStop` line only works because systemd injects `$MAINPID` when it runs that line as part of stopping the unit. Run standalone in a shell, `$MAINPID` is empty, so `kill ""` silently no-ops and `sox` keeps playing — it looks like the stop "didn't take" or "restarted" when really it just never stopped.

**Debugging the HA switch:**
```bash
systemctl --user status white-noise white-noise-mqtt   # both should be active (running)
journalctl --user -u white-noise-mqtt -n 50             # bridge logs
docker exec mosquitto mosquitto_sub -h localhost -p 1883 \
  -u homelab -P "$(grep MQTT_PASSWORD .env.mqtt | cut -d= -f2)" -t 'whitenoise/#' -v
```
The last command should show one retained `whitenoise/available online` and one `whitenoise/state ON`/`OFF` — if `available` keeps flapping `offline`/`online` every few seconds, HA will show the switch as unavailable on and off, and presses made during an "offline" blip get dropped. That flapping is exactly the same reconnect-loop bug documented for `toggle-button-mqtt.py` in [`scripts/pi-buttons/README.md`](../../scripts/pi-buttons/README.md) (found again in `white-noise-mqtt.py` on 2026-08-31 and fixed the same way).

