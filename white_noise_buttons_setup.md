# White noise push buttons setup (wol-sender Pi)

Two momentary push buttons for `switch.white_noise` (see `PROJECTS.md`,
"Easier HA control for household + house help"). Supersedes the original
latching toggle switch on GPIO17 - that hardware was physically swapped for
two independent push buttons (GPIO17 start, GPIO18 stop), so the bridge
script and HA automations changed shape to match (see
`scripts/white-noise-buttons-mqtt.py` for why - same reasoning as
`scene-buttons-mqtt.py` vs. the old `toggle-button-mqtt.py`: a momentary
press has no persisted state, so there's nothing for a reconnect to
replay/refire).

## Steps

1. **Wire the two buttons** to the Pi (no resistor needed - uses the Pi's
   internal pull-up):
   - Start button: **GPIO17 (physical pin 11)** <-> **GND (physical pin 9)**
   - Stop button: **GPIO18 (physical pin 12)** <-> **GND (physical pin 14)**
2. **Copy the script to the Pi**:
   ```
   scp scripts/white-noise-buttons-mqtt.py pramod@192.168.1.124:~/
   chmod +x ~/white-noise-buttons-mqtt.py
   ```
3. **Reuse the existing MQTT credentials** - `~/toggle-button-mqtt.env` on
   the Pi already has `MQTT_USERNAME`/`MQTT_PASSWORD` for the `homelab`
   Mosquitto user; this script needs the same two variables:
   ```
   cp ~/toggle-button-mqtt.env ~/white-noise-buttons-mqtt.env
   ```
4. **Retire the old toggle service** (same script/pins are being replaced,
   not run alongside):
   ```
   sudo systemctl disable --now toggle-button-mqtt
   sudo rm /etc/systemd/system/toggle-button-mqtt.service
   ```
5. **Install the systemd unit** at `/etc/systemd/system/white-noise-buttons-mqtt.service`
   (same shape as `scene-buttons-mqtt.service` - see the old `toggle_button_setup.md`
   in git history for why each of these lines matters, particularly
   `WorkingDirectory` and `GPIOZERO_PIN_FACTORY`):
   ```ini
   [Unit]
   Description=White noise push buttons MQTT bridge (start/stop)
   After=network-online.target
   Wants=network-online.target

   [Service]
   User=pramod
   WorkingDirectory=/home/pramod
   EnvironmentFile=/home/pramod/white-noise-buttons-mqtt.env
   Environment=GPIOZERO_PIN_FACTORY=lgpio
   ExecStart=/home/pramod/.local/bin/uv run /home/pramod/white-noise-buttons-mqtt.py
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```
   Then:
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable --now white-noise-buttons-mqtt
   ```
6. **Apply the HA automations**: `scripts/apply_white_noise_button_automations.sh`
   (run on xero, needs sudo since `automations.yaml` is root-owned) - removes
   the dead `toggle1_white_noise_on`/`_off` automations (they trigger on
   `binary_sensor.toggle_switch_1`, which no longer exists) and adds
   `white_noise_button_start`/`_stop`. Reload automations in HA afterward
   (Settings -> Automations & Scenes -> menu -> Reload Automations).
7. **Verify**: press the start button, confirm `switch.white_noise` turns on
   in HA within a couple seconds; press stop, confirm it turns off. No
   entity/state to check first - like the scene buttons, these publish a
   plain non-retained MQTT message straight to an MQTT-trigger automation.
