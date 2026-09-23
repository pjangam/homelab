#!/usr/bin/env bash
# Run this ON XERO. Builds spotifyd natively on the wol Pi and installs it to
# the Pi's ~/.local/bin/spotifyd, replacing the upstream binary that cannot
# start there (it wants OpenSSL 1.1; trixie ships 3).
#
# Why on the Pi: the cross-build on xero (build_spotifyd_arm64.sh) crashed
# xero - see docs/incidents/2026-09-23-xero-kernel-oops-during-rust-build.md.
# The Pi is slow but has no other claim on it overnight.
#
# Tuned for 1GB of RAM:
#   - one compile job at a time (CARGO_BUILD_JOBS=1)
#   - LTO off. spotifyd's release profile sets `lto = true`, and a fat-LTO final
#     link of this size wants well over 1GB. Without it the binary is somewhat
#     larger and no less correct.
#   - nice'd, so the buttons, Node-RED and the clock stay responsive.
# Expect 2-3 hours. rustup, not Debian's rustc: trixie has 1.85 and spotifyd
# 0.4.2 needs 1.88.
#
# The build runs as a transient systemd --user unit (linger is on), so it
# carries on after this script's ssh session ends. Asks for the Pi's sudo
# password once, for the apt install only.
#
# Follow it:  ssh pramod@192.168.1.124 journalctl --user-unit spotifyd-build -f
# (--user-unit, not --user -u: the Pi's journal is volatile with no per-user
# files, so a user unit's output lands in the system journal.)
set -euo pipefail

PI="pramod@192.168.1.124"
VERSION="${1:-0.4.2}"

# The remote script goes in as the command, not on stdin, so ssh -t gets a
# real terminal and sudo can prompt for the password.
ssh -t "$PI" "VERSION='$VERSION'
$(cat <<'REMOTE'
set -euo pipefail

echo "== build dependencies (apt) =="
sudo apt-get update -q
sudo apt-get install -y -q --no-install-recommends \
  git pkg-config libasound2-dev libssl-dev libdbus-1-dev libpulse-dev

echo "== rust toolchain (rustup, minimal profile) =="
if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --no-modify-path
fi
"$HOME/.cargo/bin/rustup" update stable
"$HOME/.cargo/bin/rustc" --version

echo "== source v$VERSION =="
SRC="$HOME/build/spotifyd"
rm -rf "$SRC"
git clone -q --depth 1 --branch "v$VERSION" https://github.com/Spotifyd/spotifyd "$SRC"

echo "== starting the build in the background =="
systemctl --user reset-failed spotifyd-build 2>/dev/null || true
systemd-run --user --unit=spotifyd-build --nice=10 \
  -p WorkingDirectory="$SRC" \
  -E PATH="$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin" \
  -E CARGO_BUILD_JOBS=1 -E CARGO_PROFILE_RELEASE_LTO=false \
  /bin/bash -c '
    set -euo pipefail
    ~/.cargo/bin/cargo build --release --locked
    install -m 755 target/release/spotifyd ~/.local/bin/spotifyd
    echo "installed: $(~/.local/bin/spotifyd --version)"
    grep -aq org.mpris.MediaPlayer2 ~/.local/bin/spotifyd && echo "MPRIS: present"
  '
echo
echo "Build running as spotifyd-build. You can close this session."
echo "Follow:  journalctl --user-unit spotifyd-build -f"
REMOTE
)"
