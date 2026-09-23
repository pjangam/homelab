#!/usr/bin/env bash
# Run this ON XERO. Step 2 of "Move white noise and spotifyd from xero to the
# wol Pi" (PROJECTS.md): copies the white-noise, volume and spotifyd services
# to the Pi and installs them as systemd --user units, **disabled and
# stopped**. Nothing starts, HA is untouched, and xero keeps serving
# everything. Cutover (step 4) is a separate, deliberate act.
#
#   deploy_audio_pi.sh [headphones|usb]
#
#   headphones (default) - the Pi's 3.5mm jack, for testing alongside xero
#   usb                  - the USB speaker moved over from xero (C-Media
#                          "USB Audio Device", ALSA id "Device")
#
# The Pi has no repo clone, so the files are laid out under ~/homelab with
# the same relative paths as the repo, and the units' /home/pramod/code/homelab
# is rewritten to /home/pramod/homelab. Re-run after changing any of them.
# No sudo needed: these are user units, and linger is already on (step 1).
set -euo pipefail

MODE="${1:-headphones}"
case "$MODE" in
  headphones) CARD=Headphones; CONTROL=PCM ;;
  usb)        CARD=Device;     CONTROL=Speaker ;;
  *) echo "usage: $0 [headphones|usb]" >&2; exit 2 ;;
esac

PI="pramod@192.168.1.124"
BROKER_IP="192.168.1.123"   # xero, where Mosquitto runs
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PI_ROOT="/home/pramod/homelab"
UNITS=(white-noise.service white-noise-mqtt.service volume-mqtt.service)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# --- stage everything locally, then ship it in one scp --------------------
mkdir -p "$stage/homelab/projects/white-noise" "$stage/homelab/projects/spotifyd" \
         "$stage/units" "$stage/spotifyd"
cp "$REPO/projects/white-noise/white-noise-mqtt.py" \
   "$REPO/projects/white-noise/volume-mqtt.py" "$stage/homelab/projects/white-noise/"
cp "$REPO/projects/spotifyd/wait_for_network.sh" "$stage/homelab/projects/spotifyd/"

for u in "${UNITS[@]}"; do
  sed "s|/home/pramod/code/homelab|$PI_ROOT|g" "$REPO/projects/white-noise/$u" > "$stage/units/$u"
done
sed "s|/home/pramod/code/homelab|$PI_ROOT|g" "$REPO/projects/spotifyd/spotifyd.service" \
  > "$stage/units/spotifyd.service"

# Which mixer the fade, the 59% ceiling and the HA volume slider act on.
printf '[Service]\nEnvironment=ALSA_CARD=%s ALSA_CONTROL=%s\n' "$CARD" "$CONTROL" \
  > "$stage/units/white-noise-host.conf"
printf '[Service]\nEnvironment=VOLUME_CARD=%s VOLUME_CONTROL=%s\n' "$CARD" "$CONTROL" \
  > "$stage/units/volume-mqtt-host.conf"

# xero's spotifyd.conf with the Pi's own Connect name. Credential lines are
# dropped: 0.4 authenticates through zeroconf from the phone and caches it.
grep -v -i -E '^\s*(password|password_cmd|use_keyring)\s*=' "$HOME/.config/spotifyd/spotifyd.conf" \
  | sed -E 's/^(\s*device_name\s*=).*/\1 "raspberrypi"/' > "$stage/spotifyd/spotifyd.conf"
grep -q '^device_name = "raspberrypi"' "$stage/spotifyd/spotifyd.conf" \
  || { echo "device_name did not get rewritten - check spotifyd.conf" >&2; exit 1; }

ssh "$PI" 'rm -rf ~/.deploy-audio && mkdir -p ~/.deploy-audio'
scp -q -r "$stage"/. "$PI:.deploy-audio/"

# --- install on the Pi ------------------------------------------------------
ssh "$PI" BROKER_IP="$BROKER_IP" PI_ROOT="$PI_ROOT" bash -s <<'REMOTE'
set -euo pipefail
d=~/.deploy-audio
ud=~/.config/systemd/user

mkdir -p "$PI_ROOT"
cp -r "$d/homelab/." "$PI_ROOT/"
chmod +x "$PI_ROOT/projects/spotifyd/wait_for_network.sh"

# MQTT credentials: reuse the ones the button bridge already has on this Pi,
# so they never cross the network again. MQTT_HOST points the bridges at xero.
env_file="$PI_ROOT/.env.mqtt"
install -m 600 /dev/null "$env_file.new"
{ grep -E '^MQTT_(USERNAME|PASSWORD)=' ~/white-noise-buttons-mqtt.env
  echo "MQTT_HOST=$BROKER_IP"; } >> "$env_file.new"
mv "$env_file.new" "$env_file"

mkdir -p "$ud/white-noise.service.d" "$ud/volume-mqtt.service.d" ~/.config/spotifyd
cp "$d/units/"*.service "$ud/"
cp "$d/units/white-noise-host.conf" "$ud/white-noise.service.d/host.conf"
cp "$d/units/volume-mqtt-host.conf" "$ud/volume-mqtt.service.d/host.conf"
cp "$d/spotifyd/spotifyd.conf" ~/.config/spotifyd/spotifyd.conf
rm -rf "$d"

systemctl --user daemon-reload
echo "== installed (should all be disabled / inactive) =="
for u in white-noise white-noise-mqtt volume-mqtt spotifyd; do
  printf '%-18s %-9s %s\n' "$u" "$(systemctl --user is-enabled $u 2>/dev/null || true)" \
    "$(systemctl --user is-active $u 2>/dev/null || true)"
done
echo "== white-noise mixer =="
systemctl --user show white-noise -p Environment
REMOTE
