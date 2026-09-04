#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt", "gpiozero", "rpi-lgpio"]
# ///
"""MQTT bridge for two momentary push buttons wired to Pi GPIO pins, firing
the "oju sleeping" / "oju awake" scenes directly.

Runs on the wol-sender Pi (not xero) - GPIO needs real pins, which xero
doesn't have. Wiring (no resistor needed, uses the Pi's internal pull-up):
  - Sleep button: GPIO27 (physical pin 13) <-> GND (physical pin 14)
  - Awake button: GPIO22 (physical pin 15) <-> GND (physical pin 14)

Deliberately different shape from toggle-button-mqtt.py: these are momentary
triggers, not a persisted state, so there's no retained binary_sensor and no
availability topic here. toggle-button-mqtt.py originally reconnected every
~5s due to a race in its manual MQTT loop, and each reconnect republished its
retained state through a brief "unavailable" transition - enough to refire
an HA automation watching that state, overriding manual scene/dashboard
control every few seconds. Publishing a plain, non-retained message only on
an actual button press - with nothing retained to replay on reconnect -
sidesteps that whole bug class rather than just fixing this instance of it.

HA side: a plain MQTT trigger automation per topic (payload "PRESS") calling
scene.turn_on - no entity/discovery needed for a momentary trigger.
"""
import os
from datetime import datetime
from pathlib import Path

import paho.mqtt.client as mqtt
from gpiozero import Button

BROKER = "192.168.1.123"  # xero, where Mosquitto runs
PORT = 1883

BUTTONS = {
    "scene_buttons/oju_sleep/pressed": 27,  # BCM27 = physical pin 13
    "scene_buttons/oju_awake/pressed": 22,  # BCM22 = physical pin 15
}


def log(msg):
    # systemd captures stdout into the journal; flush so `journalctl -f` is live.
    print(f"{datetime.now().isoformat(timespec='seconds')} {msg}", flush=True)


def isolate_lgpio_notify_dir():
    """Give this process its own directory for lgpio's notification FIFO.

    lgpio creates its edge-notification FIFO (`.lgd-nfy<N>`) in the process's
    current working directory, picking the first free slot number at startup.
    Both button bridges ran with `WorkingDirectory=/home/pramod`, so when
    systemd started them in the same second at boot they raced and *both*
    claimed `.lgd-nfy0` - one shared FIFO, two readers. From then on each
    process read (and discarded) roughly half of the other's edge reports, so
    button presses silently vanished while both services still looked healthy.
    A per-script directory makes that collision impossible regardless of what
    `WorkingDirectory` the unit sets.
    """
    run_dir = Path.home() / ".lgpio" / Path(__file__).stem
    run_dir.mkdir(parents=True, exist_ok=True)
    os.chdir(run_dir)
    log(f"lgpio notify dir: {run_dir}")


def on_connect(client, userdata, flags, reason_code, properties):
    log(f"mqtt connected: {reason_code}")


def on_disconnect(client, userdata, flags, reason_code, properties):
    log(f"mqtt disconnected: {reason_code}")


def publisher(client, topic):
    def publish():
        info = client.publish(topic, "PRESS", retain=False)
        log(f"press -> {topic} (rc={info.rc})")

    return publish


def main():
    isolate_lgpio_notify_dir()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="scene-buttons-bridge")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect

    buttons = []  # keep references alive - gpiozero closes a pin when its Button is garbage collected
    for topic, pin in BUTTONS.items():
        button = Button(pin, pull_up=True, bounce_time=0.05)
        button.when_pressed = publisher(client, topic)
        buttons.append(button)
        log(f"watching GPIO{pin} -> {topic}")

    client.connect_async(BROKER, PORT, keepalive=30)
    client.loop_forever()


if __name__ == "__main__":
    main()
