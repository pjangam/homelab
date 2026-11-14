#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""Let HA ask xero to reconnect its Bluetooth speaker before playing.

HA (in Docker) cannot run bluetoothctl on the host, so the voice "play <song>"
automation publishes to bt_speaker_xero/connect and waits for
bt_speaker_xero/state. This runs bt_speaker_reconnect.sh and answers
"connected" or "unavailable". Cron runs the same script every minute; this is
the fast path for when the speaker was just switched on.
"""
import os
import subprocess
import threading
import time

import paho.mqtt.client as mqtt

BROKER = os.environ.get("MQTT_HOST", "localhost")
SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bt_speaker_reconnect.sh")
MAC = os.environ.get("BT_SPEAKER_MAC", "0D:67:1F:80:92:22")
CONNECT_TOPIC = "bt_speaker_xero/connect"
STATE_TOPIC = "bt_speaker_xero/state"
lock = threading.Lock()


def connected():
    out = subprocess.run(["bluetoothctl", "info", MAC], capture_output=True, text=True).stdout
    return "Connected: yes" in out


def reconnect(client):
    with lock:  # two "play"s in a row share one attempt
        r = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=40)
        if r.stdout.strip():
            print(r.stdout.strip(), flush=True)
        # HA subscribes for the answer just after publishing the request; a
        # reply in the same instant (already connected) could beat it.
        time.sleep(0.5)
        client.publish(STATE_TOPIC, "connected" if connected() else "unavailable")


def on_connect(client, userdata, flags, reason_code, properties=None):
    client.subscribe(CONNECT_TOPIC)


def on_message(client, userdata, msg):
    threading.Thread(target=reconnect, args=(client,), daemon=True).start()


def main():
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="bt-speaker-xero")
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(BROKER, 1883)
    client.loop_forever()


if __name__ == "__main__":
    main()
