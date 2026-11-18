# Move white noise and spotifyd from xero to the wol Pi
**Status:** Done

**Why:** xero's only link to the Airtel router is the TP-Link extender, whose backhaul is 2.4GHz Wi-Fi. Moving xero onto a cable at the router would give it a real uplink, and would allow per-device data-usage monitoring later. The one thing tying xero to its current room is the USB speaker (ALSA card 1, `USB Audio Device`) that plays white noise and serves Spotify Connect. Move the audio to the Pi and xero is free to move. Decided 2026-09-23. **Keep everything installed on xero** (units disabled, not removed) until the Pi has run smoothly for a while.
**Outcome:** closed 2026-10-02. White noise, both bridges, spotifyd (`raspberrypi`) and Play Bedroom Track have run on the Pi since the 2026-09-24 cutover, confirmed by the user after a week of use. The speaker is on the Pi's 3.5mm jack, not USB.
- Left open: what the plan below still lists - monitoring (step 5), the xero cleanup (step 6) and the power-watchdog change before xero moves (tracked in "Pi audio move follow-ups").
- Left open: checking both GPIO buttons and the HA volume slider by hand after the cutover, and testing white-noise-pauses-Spotify.
- The Pi's under-voltage is its own entry, "wol Pi under-voltage: official 5.1V supply".

#### Pi as found (2026-09-23)
Pi 3B, arm64 trixie, ~400MB RAM available, ~95% idle, `get_throttled=0x0`. On `wlan0`, not `eth0`. PipeWire runs in the desktop session. `Linger=no`. No repo clone: files reach it through the `deploy_*_pi.sh` scp scripts. `sox` is in apt; spotifyd is not. xero runs spotifyd 0.4.2 from `~/.local/bin`.

#### Triggers
**Triggers need no rewiring, just a switch of which machine answers MQTT.** Everything goes through MQTT:
- **HA switch:** `switch.white_noise` publishes `whitenoise/set`.
- **GPIO buttons:** the start/stop buttons already publish `white_noise_buttons/*/pressed` to HA, and HA's automations flip that same switch.
- **Night auto-off:** flips the same switch too.

So HA and the buttons stay as they are. The cutover is simply which machine's bridge is subscribed to `whitenoise/set`. **Never run both bridges at once:** they share one discovery `unique_id` and would both play. The only HA edit is Spotify: `play_bedroom_track` in `scripts.yaml` targets xero's spotcast entity (`media_player.xero_..._spotcast`), and a new Connect device gets a new entity.

#### Speaker on the Pi: volume calibration
The speaker is on the Pi's **3.5mm jack** (card 1 `Headphones`, control `PCM`) through its AUX input, not on USB, so `deploy_audio_pi.sh headphones` is the mode to use. The same % is quieter there than on xero (`Speaker`), and the jack's control goes above 0 dB, so it clips past ~97%: the "breaking" was the Pi, not the speaker.
- Measured at the bed: xero at 59% is ~67 dB; the Pi at 95% matches it. The user capped the slider at **93%** and settled on **91%** for white noise (-5.58 dB, so ~63 dB).
- Level, fade-out steps and slider top are now per-host settings (`WHITE_NOISE_LEVEL`, `WHITE_NOISE_FADE`, `VOLUME_MAX`), set by `deploy_audio_pi.sh`. xero keeps 59% / 45 32 18 5 / 100 and its installed unit was updated with no change in behaviour.
- The Pi: level 91, slider max 93, fade out 80 68 57 46 (~12 dB apart, since the jack's % is linear in dB). Tested on the Pi: it starts at 91%, steps down through the four and resets to 91%. The fade in is sox's own 60s ramp and needed no change.
- `deploy_audio_pi.sh` writes the level and fade into the Pi's `white-noise.service` itself, so edit them there (the `headphones)` line), not on the Pi: a deploy overwrites the Pi's copy.

#### Plan
1. **Packages on the Pi.**
   - `sudo apt install sox playerctl`.
   - spotifyd: the 0.4.2 `aarch64` release binary into `~/.local/bin`, the same version as xero.
   - `sudo loginctl enable-linger pramod`, so user units survive with no one logged in. This is the xero white-noise lesson, see memory.
2. **Make the units portable** (repo change; xero's behaviour must not change):
   - bridges: broker from `MQTT_HOST` (default `localhost`)
   - white noise and volume: ALSA card and control from env, instead of the hardcoded `-c 1 Speaker` / `Master`
   - `wait_for_network.sh`: interface as a parameter (`wlan0` on the Pi)
   - new `projects/white-noise/deploy_audio_pi.sh`: copies the scripts, units and config (`device_name` `raspberrypi`, chosen by the user 2026-09-23 as the name they will recognise) to the Pi and installs the user units **disabled**
3. **Test on the Pi alongside the live xero setup.**
   - Use earphones in the Pi's 3.5mm jack, with the Pi's bridges not started.
   - `systemctl --user start white-noise`: check the fade in, fade out and volume ceiling.
   - Start spotifyd and play to `raspberrypi` from the phone.
   - `test_white_noise_pauses_spotify.sh`.
4. **Cutover (one sitting).**
   - On xero: `systemctl --user disable --now white-noise-mqtt volume-mqtt spotifyd`, and comment out the `watchdog_spotifyd.sh` cron line.
   - Move the USB speaker to the Pi.
   - On the Pi: enable the three units.
   - Pair `raspberrypi` once from the Spotify app, then point `play_bedroom_track` at the new spotcast entity (sudo, the file is root-owned).
   - Verify: HA switch on/off, both GPIO buttons, the volume slider, the Play Bedroom Track script, and `vcgencmd get_throttled` after an hour of playing, since the speaker now draws from the Pi's weak supply.
5. **Monitoring.**
   - Move `watchdog_spotifyd.sh` to the Pi's cron.
   - Point xero's `check_spotifyd_advertising.sh`/dashboard tile at `raspberrypi`. It is avahi over the LAN, so it can watch the Pi from xero.
   - Have `healthcheck.sh` alarm on the retained `whitenoise/available`/`volume/available` going `offline`, since its systemd --user check only sees xero.
6. **After a soak of about 2 weeks.**
   - Remove the units and packages from xero.
   - Update `docs/hardware.md` (both entries), `endpoints.toml` (the Connect device and bridge topics now live on the Pi) and `white_noise_buttons_setup.md`.
   - Then move xero to the router, after the power-watchdog ping change below.

**Rollback at any point:** disable the Pi units, re-enable xero's, move the speaker back and revert the `scripts.yaml` entity.

#### Known costs
- **Power cuts:** white noise and Spotify now stop during a power cut, because the Pi has no UPS. "Move WoL to an ESP32, put the Pi on the UPS" in the backlog would undo that, but it would also break the ping-based outage signal below.
- **The Pi's supply:** its known undervoltage problem gets a new load in the USB speaker. The 3.5mm jack avoids it if the speaker has an AUX input.

#### Before xero itself moves: the power watchdog needs a new signal
`watchdog_power.sh` infers a mains outage from `enp1s0` losing carrier, which works only because the extender is not on a UPS. Plugged into the Airtel router, which has its own UPS, the carrier never drops and xero would run its battery flat. Fix: keep the carrier check and add "the wol Pi **and** the extender both stop answering pings for N checks". Requiring both avoids false alarms from the Pi's flaky supply. The extender needs a pinned IP first.

#### Log
- 2026-09-23: decided to move the audio to the Pi. Progress the same day:
  - **Step 1:** done, except spotifyd. The upstream aarch64 binary needs OpenSSL 1.1, which trixie does not have. Cross-building it on xero crashed xero; see `docs/incidents/2026-09-23-xero-kernel-oops-during-rust-build.md`.
  - **Step 2:** done. `projects/white-noise/deploy_audio_pi.sh` installs the four units disabled under `~/homelab` on the Pi.
  - **White noise on the Pi:** tested through the 3.5mm jack. It starts, holds 59% and stops cleanly. The bridges were not started, since they would clash with xero's.
- 2026-09-24: **fallback if the build fails** decided: **don't retry, use raspotify.** `projects/spotifyd/install_raspotify_pi.sh` installs raspotify's librespot and disables the package's own system service; librespot then runs as a user unit named `raspberrypi`. librespot has no MPRIS, so pausing Spotify before white noise moves to an HA automation.
- 2026-09-24: spotifyd now built on the Pi itself with `projects/spotifyd/build_spotifyd_on_pi.sh`: one job at a time, LTO off. **Built in 93min** (swap peaked ~540MB, never throttled). The result is 0.4.2 linked to `libssl.so.3`, with MPRIS, so the raspotify fallback was not needed. Started by hand on the Pi (unit still disabled), it advertises `raspberrypi` over zeroconf, visible from xero's `avahi-browse`.
- 2026-09-24: plan step "plug the USB speaker into the Pi and run `deploy_audio_pi.sh usb`" done differently: the speaker is on the Pi's 3.5mm jack, deployed with `headphones` and volume recalibrated (see "Speaker on the Pi: volume calibration").
- 2026-09-24: test on the Pi alone, listed for this session: `systemctl --user start white-noise` (level and fade), play to `raspberrypi` from the phone, `playerctl -p spotifyd pause` from the Pi, `vcgencmd get_throttled` after a while.
- 2026-09-24: **cutover, white noise done:** xero's `white-noise`, `white-noise-mqtt` and `volume-mqtt` are disabled (installed, for rollback); the Pi's two bridges are enabled. No HA edit was needed. Checked: `whitenoise/set` ON/OFF (what the HA switch sends) starts and stops it on the Pi with the fade, both bridges `online`, the slider's discovery `max` is 93. White noise was left playing on the Pi, as it was on xero. **Still to check by hand:** both GPIO buttons and the HA volume slider.
- 2026-09-24: **spotifyd done:** xero's disabled and its `watchdog_spotifyd.sh` cron line commented out; the Pi's enabled, and `raspberrypi` is advertised (seen from xero's `avahi-browse`). xero's health check now reads spotifyd as "not applicable" (exit 2), so it stays green but watches nothing until step 5. spotifyd was left running on the Pi overnight as a soak test; it was started by hand, so a Pi reboot stops it.
- 2026-09-25: HA: `play_bedroom_track` pointed at the new spotcast entity for `raspberrypi` (`media_player.raspberrypi_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast`, scripts reloaded). Phone to `raspberrypi` plays audibly through the jack (after naming the card in `spotifyd.conf`; `default` was HDMI).
- 2026-09-25: **verified** with the jack muted (`PCM` 0%, restored to 91% after): Play Bedroom Track through HA's API had spotifyd `Playing` a track from the playlist and the jack `RUNNING` within 2s. An earlier run that found no session seconds later was not reproduced. Still listed: test white-noise-pauses-Spotify.
- 2026-09-25: **Spotify silent on the Pi.** It was playing to the jack, but the jack was still muted from a test the night before; the HA slider had since set 93% without unmuting. Fixed so it cannot recur: the slider (`volume-mqtt.py`) and white noise's start now also `unmute`. Tested the slider by muting and sending `volume/set 93`.
- 2026-10-02: closed, confirmed by the user after a week of use. Remaining steps moved to "Pi audio move follow-ups"; under-voltage to "wol Pi under-voltage: official 5.1V supply".
- 2026-11-03: **Spotify moved back to xero only** (user's call). xero's spotifyd had gone stale (websocket dead since 2026-11-01, not caught by the watchdog), restarted. `play_bedroom_track` now targets `media_player.xero_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast` (scripts reloaded). On the Pi, spotifyd is disabled (installed, for rollback) and its watchdog cron line is commented out. White noise and the HA volume slider stay on the Pi, so white noise no longer pauses Spotify, and the slider does not control Spotify's speaker. xero's speaker was silent until the AUX cable was reseated; set to 30%, then ~40% (-22 dB) at the user's ask.
- 2026-11-05: **correction (user): the Pi's spotifyd was never meant to be disabled** - the 2026-11-03 intent was to enable xero *alongside* it, not move it. Re-enabled on the Pi (`systemctl --user enable --now spotifyd`, authenticated) and its watchdog cron uncommented; both `raspberrypi` and `xero` advertise. `play_bedroom_track` pointed back at `media_player.raspberrypi_..._spotcast` (edited inside the HA container, backup `scripts.yaml.bak-2026-11-05`, scripts reloaded); run through HA's API it played on the Pi's jack at 91%. xero's spotifyd stays enabled too, for playing to from the phone.
- 2026-11-05: how this surfaced: the user's Play Bedroom Track press (18:49) "failed". HA's trace shows it finished cleanly, and it did play - on xero (spotifyd loaded the track at 18:49:07), while the bedroom Pi was off. So the script silently plays on the wrong speaker if its entity points at xero. `tools/ha-diag/script_traces.py` added to read script traces.
