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
   EnvironmentFile=/home/pramod/toggle-button-mqtt.env
   ExecStart=/home/pramod/toggle-button-mqtt.py
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```
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

## Known risk

`RPi.GPIO` (a script dependency) needs to compile against the Pi's GPIO
headers when `uv` builds its isolated venv. Should work out of the box on Pi
OS, but if `uv run` fails on that dependency, switch the pin factory to
`lgpio` instead.

## After this works

- Decide whether to build a second GPIO button the same way (if also near
  the Pi), or move to ESP32/ESPHome for locations elsewhere in the house.
- Still open: whether a wall-mounted tablet (approach 2 in PROJECTS.md) is
  worth pursuing alongside this.
