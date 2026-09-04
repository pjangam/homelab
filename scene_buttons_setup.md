# Scene buttons setup (wol-sender Pi)

Two momentary push buttons for `scene.ojaswi_sleeping`/`scene.ojaswi_awake`
(see PROJECTS.md, "Easier HA control for household + house help"). Chosen
over a single two-position toggle: sleep/awake are one-shot scene triggers,
not a persisted state, so re-triggering one via a toggle would mean flipping
through the other position first, spuriously firing the wrong scene.

Software side (script, HA automations) is ready. **Physical wiring is on
hold** - this doc is for whenever that happens.

## Steps

1. **Wire the two buttons** to the Pi (no resistor needed - uses the Pi's
   internal pull-up):
   - Sleep button: **GPIO27 (physical pin 13)** <-> **GND (physical pin 14)**
   - Awake button: **GPIO22 (physical pin 15)** <-> **GND (physical pin 14)**
   - (GPIO17/pin 11, used by the toggle switch, is untouched - these are two
     new, separate pins.)
2. **Copy the script to the Pi**:
   ```
   scp scripts/scene-buttons-mqtt.py pramod@192.168.1.124:~/
   chmod +x ~/scene-buttons-mqtt.py
   ```
3. **Reuse the existing MQTT credentials** - `~/toggle-button-mqtt.env` on
   the Pi already has `MQTT_USERNAME`/`MQTT_PASSWORD` for the `homelab`
   Mosquitto user; this script needs the same two variables. Either point a
   second `EnvironmentFile` at the same file, or copy it:
   ```
   cp ~/toggle-button-mqtt.env ~/scene-buttons-mqtt.env
   ```
4. **Install the systemd unit** at `/etc/systemd/system/scene-buttons-mqtt.service`
   (same shape as `toggle-button-mqtt.service` - see `toggle_button_setup.md`
   for why each of these lines matters, particularly `WorkingDirectory` and
   `GPIOZERO_PIN_FACTORY`):
   ```ini
   [Unit]
   Description=Scene buttons MQTT bridge (oju sleep/awake)
   After=network-online.target
   Wants=network-online.target

   [Service]
   User=pramod
   WorkingDirectory=/home/pramod
   EnvironmentFile=/home/pramod/scene-buttons-mqtt.env
   Environment=GPIOZERO_PIN_FACTORY=lgpio
   ExecStart=/home/pramod/.local/bin/uv run /home/pramod/scene-buttons-mqtt.py
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```
   Then:
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable --now scene-buttons-mqtt
   ```
5. **Apply the HA automations**: `scripts/apply_scene_button_automations.sh`
   (already written - adds `scene_button_oju_sleep`/`scene_button_oju_awake`
   to `HOMEASSISTANT_CONFIG/automations.yaml`, root-owned so it uses `sudo
   tee`). Reload automations in HA afterward (Settings -> Automations &
   Scenes -> menu -> Reload Automations).
6. **Verify**: press each button, confirm the corresponding scene fires in
   HA (Developer Tools -> Logbook, or just watch the lights/whatever the
   scene controls). No entity/state to check first this time - these
   publish a plain non-retained MQTT message straight to an MQTT-trigger
   automation, not a `binary_sensor`.

## Why this is a different shape from the toggle switch

`toggle-button-mqtt.py` publishes a *retained* state (the switch's current
position) and had a real bug where its manual MQTT reconnect loop cycled
every ~5s, each cycle briefly republishing that retained state through an
"unavailable" transition - enough to refire an automation watching for a
state change, even with the physical switch untouched (see PROJECTS.md,
2026-08-25 "Reconnect-loop bug"). `scene-buttons-mqtt.py` sidesteps that
whole bug class by design: it publishes a plain, non-retained message only
on an actual button press, with no persisted state at all for a reconnect to
replay. It also already uses the fixed `connect_async()` + `loop_forever()`
pattern from the start, not the original racy manual loop.

## Troubleshooting

Same failure modes and tooling as the white-noise buttons - see the
"Troubleshooting" section of `white_noise_buttons_setup.md`. Both bridges run
on the same Pi and hit the same lgpio notify-FIFO collision on 2026-09-04
(`incidents/2026-09-04-lgpio-notify-fifo-collision.md`); redeploy either with
`scripts/deploy_button_bridges_pi.sh`.
