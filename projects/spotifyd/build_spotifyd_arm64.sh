#!/usr/bin/env bash
# Run this ON XERO. Cross-compiles spotifyd for the wol Pi (Pi 3B, arm64,
# Debian trixie) in Docker and leaves the binary in projects/spotifyd/build/.
#
# Why not the upstream release: every aarch64 build of spotifyd 0.4.2 (slim,
# default and full alike) is linked against OpenSSL 1.1 (libssl.so.1.1), and
# trixie ships only OpenSSL 3, so the binary will not even start. Installing
# bullseye's libssl1.1 would make it run, but that OpenSSL is end-of-life with
# no security fixes. Building against trixie's own libraries avoids both.
#
# Cross-compiled rather than built on the Pi: a Rust build of this size on a
# 1GB Pi 3B takes hours and risks the OOM killer. xero has no arm64 emulation
# (no qemu binfmt), so this is a true cross-build: x86 trixie container, arm64
# libraries via Debian multiarch, aarch64 gcc as the linker.
#
# Features are upstream's "default" set - ALSA, PulseAudio and MPRIS. MPRIS is
# the one that matters: white-noise.service pauses Spotify through it with
# `playerctl -p spotifyd pause`.
#
# WARNING: the first run of this on 2026-09-23 crashed xero with a kernel oops
# mid-compile - suspect RAM, see
# docs/incidents/2026-09-23-xero-kernel-oops-during-rust-build.md. Do not run it
# on xero again until memtest has cleared the RAM.
#
# Deploy with install_spotifyd_pi.sh. The build/ folder is gitignored.
set -euo pipefail

VERSION="${1:-0.4.2}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/build"
mkdir -p "$OUT"

docker run --rm \
  -v "$OUT:/out" \
  -v spotifyd-cargo-registry:/usr/local/cargo/registry \
  -e VERSION="$VERSION" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  rust:1-trixie bash -euo pipefail -c '
    dpkg --add-architecture arm64
    apt-get update -q
    apt-get install -y -q --no-install-recommends \
      gcc-aarch64-linux-gnu libc6-dev-arm64-cross pkg-config \
      libasound2-dev:arm64 libssl-dev:arm64 libdbus-1-dev:arm64 libpulse-dev:arm64
    rustup target add aarch64-unknown-linux-gnu

    git clone -q --depth 1 --branch "v$VERSION" https://github.com/Spotifyd/spotifyd /src
    cd /src
    export PKG_CONFIG_ALLOW_CROSS=1
    export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
    export PKG_CONFIG_SYSROOT_DIR=/
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
    cargo build --release --locked --target aarch64-unknown-linux-gnu

    install -m 755 target/aarch64-unknown-linux-gnu/release/spotifyd /out/spotifyd-aarch64
    chown "$HOST_UID:$HOST_GID" /out/spotifyd-aarch64
  '

echo
file "$OUT/spotifyd-aarch64"
echo "libraries it needs:"
readelf -d "$OUT/spotifyd-aarch64" | grep NEEDED
