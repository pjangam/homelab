#!/usr/bin/env bash
# Run this ON XERO. Step 1 of "Move white noise and spotifyd from xero to the
# wol Pi" (PROJECTS.md): installs what the Pi needs to play white noise and act
# as a Spotify Connect speaker. Installs only - no services, no config, nothing
# started, and xero is not touched.
#
#   - sox + playerctl from apt (sox's `play` synthesises the brown noise;
#     playerctl lets white-noise.service pause Spotify first)
#   - spotifyd 0.4.2, the same version xero runs. Not in Debian, so it is the
#     upstream aarch64 release binary, checksum-verified, into ~/.local/bin -
#     the same place xero keeps its copy.
#   - linger for pramod, so the systemd --user units still to come keep running
#     with nobody logged in. Without it they die on logout: that is the bug
#     that silently broke white noise on xero in 2026-07.
#
# Asks for the Pi's sudo password once. Safe to re-run: every step checks
# before it acts.
set -euo pipefail

PI="pramod@192.168.1.124"

# The remote script goes in as the command, not on stdin, so ssh -t gets a
# real terminal and sudo can prompt for the password.
ssh -t "$PI" "$(cat <<'REMOTE'
set -euo pipefail

SPOTIFYD_VERSION="0.4.2"
# "default" rather than "slim": it keeps the MPRIS (D-Bus) interface, which
# `playerctl -p spotifyd pause` needs. Checked below.
ASSET="spotifyd-linux-aarch64-default"
BASE="https://github.com/Spotifyd/spotifyd/releases/download/v${SPOTIFYD_VERSION}"
BIN="$HOME/.local/bin/spotifyd"

echo "== apt: sox, playerctl =="
if dpkg -s sox playerctl >/dev/null 2>&1; then
  echo "already installed"
else
  sudo apt-get update -q
  sudo apt-get install -y sox playerctl
fi

echo "== spotifyd ${SPOTIFYD_VERSION} =="
if [ -x "$BIN" ] && "$BIN" --version 2>/dev/null | grep -q " ${SPOTIFYD_VERSION}\$"; then
  echo "already installed: $("$BIN" --version)"
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL -o "$tmp/$ASSET.tar.gz" "$BASE/$ASSET.tar.gz"
  curl -fsSL -o "$tmp/$ASSET.sha512" "$BASE/$ASSET.sha512"
  (cd "$tmp" && sha512sum -c "$ASSET.sha512")
  tar -xzf "$tmp/$ASSET.tar.gz" -C "$tmp"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$tmp/spotifyd" "$BIN"
  echo "installed: $("$BIN" --version)"
fi
if grep -aq "org.mpris.MediaPlayer2" "$BIN"; then
  echo "MPRIS: present"
else
  echo "WARNING: this spotifyd build has no MPRIS - playerctl cannot pause it" >&2
fi

echo "== linger for $USER =="
if [ "$(loginctl show-user "$USER" -p Linger --value)" = "yes" ]; then
  echo "already on"
else
  sudo loginctl enable-linger "$USER"
  echo "Linger=$(loginctl show-user "$USER" -p Linger --value)"
fi

echo
echo "== check =="
command -v play playerctl
"$BIN" --version
loginctl show-user "$USER" -p Linger
REMOTE
)"
