#!/usr/bin/env bash
# Capture, side by side, what the physical white-noise buttons do:
#   - GPIO17/18 level changes on the wol-sender Pi (pinctrl poll, read-only,
#     safe to run alongside the bridge service which owns the pins)
#   - the MQTT messages the bridge publishes as a result
# Run it, press each button, then read the two logs it names.
#   ./scripts/capture_white_noise_button_presses.sh [seconds]
set -u
SECS=${1:-90}
PI=192.168.1.124
OUT=/home/pramod/code/homelab/scripts/.button-capture
mkdir -p "$OUT"
set -a; . /home/pramod/code/homelab/.env.mqtt; set +a

ssh -o ConnectTimeout=5 pramod@$PI "timeout $SECS pinctrl poll 17,18" > "$OUT/gpio.log" 2>&1 &
timeout $((SECS + 2)) docker exec mosquitto mosquitto_sub -h localhost \
  -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t 'white_noise_buttons/#' -v -F '%I %t %p' \
  > "$OUT/mqtt.log" 2>&1 &
wait
echo "gpio: $OUT/gpio.log"; cat "$OUT/gpio.log"
echo "mqtt: $OUT/mqtt.log"; cat "$OUT/mqtt.log"
