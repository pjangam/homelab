#!/usr/bin/env bash
# Diagnose the white-noise GPIO push buttons (wol-sender Pi -> MQTT -> HA -> switch.white_noise).
# Walks the chain end to end and prints where it breaks.
#   ./scripts/diagnose_white_noise_buttons.sh          # status only
#   ./scripts/diagnose_white_noise_buttons.sh --inject # also publish a synthetic PRESS and watch the switch
set -u
PI=192.168.1.124
set -a; . /home/pramod/code/homelab/.env.mqtt; set +a
mq() { docker exec mosquitto "$@" -h localhost -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD"; }

echo "== Pi bridge service =="
ssh -o ConnectTimeout=5 pramod@$PI 'systemctl is-active white-noise-buttons-mqtt; pinctrl get 17,18'

echo; echo "== whitenoise bridge (xero) =="
systemctl --user is-active white-noise-mqtt
timeout 6 mq mosquitto_sub -t 'whitenoise/#' -v -W 3 2>&1 | grep -v '^Timed out'

echo; echo "== watching button topics for 20s (press the buttons now) =="
timeout 22 mq mosquitto_sub -t 'white_noise_buttons/#' -v -W 20 2>&1 | grep -v '^Timed out'

if [ "${1:-}" = "--inject" ]; then
  echo; echo "== injecting synthetic start PRESS =="
  mq mosquitto_pub -t white_noise_buttons/start/pressed -m PRESS
  sleep 3
  timeout 5 mq mosquitto_sub -t 'whitenoise/state' -v -W 2 2>&1 | grep -v '^Timed out'
fi
