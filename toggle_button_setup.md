# Toggle button → HA setup (wol-sender Pi)

First physical button for "Easier HA control for household + house help" (see PROJECTS.md).
Salvaged latching/toggle switch, wired into the wol-sender Pi's GPIO (chosen over
ESP32/xero since the button sits right next to an existing host).

## Steps

1. **Wire the switch** to the Pi:
   - One leg → **GPIO17 (physical pin 11)**
   - Other leg → **GND (physical pin 9)**
   - No resistor needed - uses the Pi's internal pull-up.
2. **Copy the script to the Pi**:
   ```
   scp scripts/toggle-button-mqtt.py pramod@192.168.1.124:~/
   ```
3. **Check/install `uv` on the Pi**:
   ```
   uv --version || curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
4. **Create the credentials file** on the Pi at `~/toggle-button-mqtt.env`
   (not committed - pull the password from Vaultwarden, same Mosquitto creds
   used by Node-RED/white-noise/etc.):
   ```
   MQTT_USERNAME=homelab
   MQTT_PASSWORD=<from Vaultwarden>
   ```
5. **Install the systemd unit** on the Pi at `/etc/systemd/system/toggle-button-mqtt.service`:
   ```ini
   [Unit]
   Description=Toggle switch MQTT bridge
   After=network-online.target
   Wants=network-online.target

   [Service]
   User=pramod
   WorkingDirectory=/home/pramod
   EnvironmentFile=/home/pramod/toggle-button-mqtt.env
   Environment=GPIOZERO_PIN_FACTORY=lgpio
   ExecStart=/home/pramod/.local/bin/uv run /home/pramod/toggle-button-mqtt.py
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```
   Notes:
   - `ExecStart` calls `uv` by its full path rather than relying on the
     script's `#!/usr/bin/env -S uv run --script` shebang - systemd's default
     `PATH` doesn't include `~/.local/bin`, so a bare `ExecStart=/home/pramod/toggle-button-mqtt.py`
     fails with "No such file or directory" even though the same script runs
     fine over an interactive SSH session.
   - `WorkingDirectory=/home/pramod` is required. The `lgpio` Python library
     creates a notification file (`.lgd-nfy-N`) in the process's *current
     working directory* at import time. systemd's default cwd (when
     unset) is `/`, which `pramod` can't write to - this makes gpiozero's
     `lgpio` pin factory fail to import, and it silently falls back to the
     broken legacy `native`/sysfs backend instead of raising a clear error
     (looks like the original `RPi.GPIO` edge-detection failure again, but
     isn't). Setting `Environment=GPIOZERO_PIN_FACTORY=lgpio` is what makes
     the real error surface instead of a silent fallback - worth keeping in
     the unit even now, so any future failure is loud rather than silent.
   - `~/toggle-button-mqtt.env` is created via `scripts/setup_toggle_button_env.sh`
     (prompts for the MQTT password interactively, avoids pasting a heredoc
     with a secret over SSH).

   Then:
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable --now toggle-button-mqtt
   ```
6. **Verify in HA**: confirm a "Toggle Switch 1" `binary_sensor` entity appears
   and flips ON/OFF as the switch is flipped.
7. **Wire an HA automation**: once state is confirmed good, decide what ON and
   OFF should each trigger (e.g. white noise on/off, or a scene) and build it
   as a normal HA automation.

## Known risk (resolved)

`RPi.GPIO` doesn't work on newer Pi OS kernels (`gpiochip` character-device
interface instead of legacy sysfs) - fails with `RuntimeError: Failed to add
edge detection`. Fixed by switching the script's dependency to `rpi-lgpio`
(drop-in replacement, same `RPi.GPIO` import namespace). Building it from
source on first `uv run` needs two system packages not present by default:
```
sudo apt-get install -y swig python3-dev build-essential liblgpio-dev
```

## After this works

- Decide whether to build a second GPIO button the same way (if also near
  the Pi), or move to ESP32/ESPHome for locations elsewhere in the house.
- Still open: whether a wall-mounted tablet (approach 2 in PROJECTS.md) is
  worth pursuing alongside this.
