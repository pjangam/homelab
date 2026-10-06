#!/usr/bin/env bash
# Build a voice satellite's firmware on the Mac instead of xero (xero's RAM is
# suspect, see PROJECTS.md), then get it onto the board the best way available:
#   1. the ESP32 is plugged into this Mac by USB -> flash it here
#   2. the board already runs ESPHome on the LAN  -> flash it over Wi-Fi (OTA)
#   3. otherwise -> copy the .bin files to xero, flash there with
#      `esphome.sh flash-bin` (the board plugged into xero)
#
#   ./build_on_mac.sh                     # living room board (voice-satellite.yaml)
#   ./build_on_mac.sh bedroom             # bedroom board (voice-bedroom.yaml)
#   ./build_on_mac.sh [bedroom] --no-flash  # build only
#
# Flashing over USB writes the chosen board's firmware to whatever ESP32 is
# plugged in, so plug in the board that matches the argument.
#
# ESPHome goes in a venv under ~/.cache, pinned to the version xero's docker
# image runs (no Docker Desktop needed, and a venv can reach the USB port).
# secrets.yaml is gitignored, so it is refreshed from xero over ssh each run
# (new boards add keys there); the local copy is used if xero is unreachable.
# XERO_SSH overrides the ssh target (default pramod@xero).
set -euo pipefail
cd "$(dirname "$0")"

ESPHOME_VERSION=2026.9.1
XERO="${XERO_SSH:-pramod@xero}"
XERO_DIR=code/homelab/projects/voice-assistant/esphome
VENV="$HOME/.cache/esphome-venv-$ESPHOME_VERSION"
config=voice-satellite.yaml; flash=1
for a in "$@"; do
  case "$a" in
    --no-flash) flash=0 ;;
    living|living-room) config=voice-satellite.yaml ;;
    bedroom) config=voice-bedroom.yaml ;;
    *) echo "Unknown argument: $a (use bedroom, living, --no-flash)" >&2; exit 1 ;;
  esac
done
# Each board file names itself and its address in substitutions.
name=$(sed -n 's/^  name: *//p' "$config" | head -1)
DEVICE_IP=$(sed -n 's/^  static_ip: *//p' "$config" | head -1)
echo "== Board: $name ($config, $DEVICE_IP)"

if scp -q -o ConnectTimeout=5 "$XERO:$XERO_DIR/secrets.yaml" secrets.yaml.new 2>/dev/null; then
  mv secrets.yaml.new secrets.yaml; chmod 600 secrets.yaml
elif [ -f secrets.yaml ]; then
  rm -f secrets.yaml.new
  echo "== Could not reach $XERO for secrets.yaml; using the local copy"
else
  echo "secrets.yaml missing and $XERO unreachable" >&2; exit 1
fi

if [ ! -x "$VENV/bin/esphome" ]; then
  echo "== Installing ESPHome $ESPHOME_VERSION into $VENV"
  py=
  for c in python3.13 python3.12 python3.11 python3; do
    if command -v "$c" >/dev/null &&
       "$c" -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then
      py=$c; break
    fi
  done
  if [ -z "$py" ]; then
    command -v brew >/dev/null || { echo "Need Python 3.11+ or Homebrew (https://brew.sh)" >&2; exit 1; }
    brew install python@3.12
    py="$(brew --prefix python@3.12)/bin/python3.12"
  fi
  "$py" -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet "esphome==$ESPHOME_VERSION"
fi
esphome="$VENV/bin/esphome"

# First build downloads the ESP-IDF toolchain (~1 GB) and takes 10+ minutes;
# later builds reuse .esphome/ and are quick.
echo "== Compiling"
"$esphome" compile "$config"

# esp-idf builds land in build/; older PlatformIO builds used .pioenvs/<name>/
out=$(dirname "$(ls -t ".esphome/build/$name/build/firmware.factory.bin" \
  ".esphome/build/$name/.pioenvs/$name/firmware.factory.bin" 2>/dev/null | head -1)")
[ -f "$out/firmware.factory.bin" ] || { echo "Built, but firmware.factory.bin not found" >&2; exit 1; }
ls -l "$out"/firmware*.bin
[ "$flash" = 1 ] || { echo "== Built, not flashed (--no-flash)"; exit 0; }

port=$(ls /dev/cu.usbserial-* /dev/cu.SLAB_USBtoUART* /dev/cu.wchusbserial* 2>/dev/null | head -1 || true)
if [ -n "$port" ]; then
  echo "== Flashing over USB on $port"
  "$esphome" upload "$config" --device "$port"
  echo "== Done. Watch it boot: $esphome logs $config --device $port"
elif nc -z -G 3 "$DEVICE_IP" 6053 2>/dev/null; then
  # 6053 is ESPHome's native API, so this is not the old WLED firmware.
  echo "== Flashing over Wi-Fi (OTA) to $DEVICE_IP"
  "$esphome" upload "$config" --device "$DEVICE_IP"
  echo "== Done. Watch it: $esphome logs $config --device $DEVICE_IP"
else
  echo "== No board on USB here and no ESPHome at $DEVICE_IP; copying the build to xero"
  ssh "$XERO" "mkdir -p $XERO_DIR/build-out/$name"
  scp "$out"/firmware*.bin "$XERO:$XERO_DIR/build-out/$name/"
  cat <<EOF
== Copied. With the ESP32 plugged into xero by USB, run there:
     projects/voice-assistant/esphome/esphome.sh flash-bin build-out/$name/firmware.factory.bin
   Or plug the ESP32 into this Mac and re-run this script.
EOF
fi
