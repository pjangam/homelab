#!/usr/bin/env bash
# Run this ON XERO - **only if the spotifyd build on the Pi failed**
# (build_spotifyd_on_pi.sh). Decided 2026-09-24: if the native build fails,
# fall back to raspotify rather than retrying it.
#
# raspotify is librespot (the library spotifyd is built on), packaged for Pis
# with its own apt repo. We only want its librespot binary, run as a systemd
# --user unit like spotifyd, so it plays through PipeWire alongside white noise.
# The package's own system service would grab the audio device directly and
# advertise a second Connect device, so it is disabled the moment it lands.
#
# The cost of the fallback: no MPRIS, so white-noise.service's
# `playerctl -p spotifyd pause` stops doing anything. Pausing Spotify before
# white noise has to move to HA (an automation on switch.white_noise turning
# on). That is done at cutover, not here.
#
# Asks for the Pi's sudo password once.
set -euo pipefail

PI="pramod@192.168.1.124"

# The remote script goes in as the command, not on stdin, so ssh -t gets a
# real terminal and sudo can prompt for the password.
ssh -t "$PI" "$(cat <<'REMOTE'
set -euo pipefail

echo "== raspotify apt repo =="
if [ ! -f /etc/apt/sources.list.d/raspotify.list ]; then
  sudo curl -sSfL https://dtcooper.github.io/raspotify/key.asc -o /usr/share/keyrings/raspotify_key.asc
  sudo chmod 644 /usr/share/keyrings/raspotify_key.asc
  echo "deb [signed-by=/usr/share/keyrings/raspotify_key.asc] https://dtcooper.github.io/raspotify raspotify main" \
    | sudo tee /etc/apt/sources.list.d/raspotify.list >/dev/null
fi
sudo apt-get update -q
sudo apt-get install -y -q raspotify

echo "== disabling the package's own system service =="
sudo systemctl disable --now raspotify

echo "== check =="
/usr/bin/librespot --version
systemctl is-enabled raspotify || true
systemctl is-active raspotify || true
REMOTE
)"
