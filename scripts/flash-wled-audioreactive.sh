#!/usr/bin/env bash
# Flash WLED with the AudioReactive usermod onto an ESP32, for the aarti
# lights build (see aarti_lights_setup.md, Phase 0).
#
# Works on both Linux (xero) and macOS (the MacBook), because the board can
# plausibly be plugged into either.
#
# Default is a READ-ONLY verify: it finds the port, reads the chip back and
# tells you whether it is a flashable ESP32. Pass --flash to actually write.
#
#   ./scripts/flash-wled-audioreactive.sh            # verify only
#   ./scripts/flash-wled-audioreactive.sh --flash     # erase + write
#   ./scripts/flash-wled-audioreactive.sh --port /dev/ttyUSB0 --flash
#
# WHY 0.14.4 AND NOT THE LATEST: WLED stopped shipping a prebuilt
# `_ESP32_audioreactive.bin` after 0.14.4 - checked against the GitHub release
# assets on 2026-09-12, and every release from 0.15.0 through 16.0.1 has no
# audioreactive asset at all. Since install.wled.me builds its variant list
# from those assets, the "audio" option simply does not appear for current
# versions. 0.14.4 is the newest release where AudioReactive is a download
# rather than a PlatformIO build, which is the difference between ten minutes
# and a toolchain afternoon. Override with --version if that ever changes.
set -euo pipefail

VERSION="${WLED_VERSION:-0.14.4}"
PORT=""
DO_FLASH=0
BAUD="${BAUD:-460800}"

while [ $# -gt 0 ]; do
  case "$1" in
    --flash) DO_FLASH=1; shift ;;
    --port) PORT="${2:?--port needs a device}"; shift 2 ;;
    --version) VERSION="${2:?--version needs a version}"; shift 2 ;;
    --baud) BAUD="${2:?--baud needs a rate}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n=== %s ===\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- find the port
# macOS exposes both /dev/tty.* and /dev/cu.* for one adapter; flashing must use
# cu.* (the tty.* side blocks waiting for carrier detect and just hangs).
if [ -z "$PORT" ]; then
  case "$(uname -s)" in
    Darwin) candidates=(/dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART*) ;;
    *)      candidates=(/dev/ttyUSB* /dev/ttyACM*) ;;
  esac
  found=()
  for c in "${candidates[@]}"; do [ -e "$c" ] && found+=("$c"); done
  case "${#found[@]}" in
    0) die "no USB serial device found.
  Plug the ESP32 in, then re-run. If it is plugged in and still not showing:
    - try a different cable; a charge-only micro-USB cable is the classic one,
      it powers the board's LED so it looks alive while carrying no data
    - on macOS a CH340 board may need the driver (modern macOS has it built in)
    - on Linux check 'dmesg | tail' for a ch341/cp210x line on plug-in" ;;
    1) PORT="${found[0]}" ;;
    *) die "several serial devices found: ${found[*]}
  Pick one with --port to avoid flashing the wrong board." ;;
  esac
fi
say "port: $PORT"
[ -r "$PORT" ] && [ -w "$PORT" ] || {
  if [ "$(uname -s)" = "Linux" ]; then
    die "no read/write access to $PORT.
  On Linux that device is root:dialout, and this user is not in dialout:
    sudo usermod -aG dialout $USER
  Then log out and back in (or run 'newgrp dialout' in this shell) - group
  membership is only picked up at login, so the fix looks like it did not work
  if you skip that."
  fi
  die "no read/write access to $PORT"
}

# ------------------------------------------------------------------- get esptool
# Kept in its own venv rather than installed globally: this is a once-a-project
# tool, and on macOS a pip install into the system python is a fight.
ESPTOOL=""
for c in esptool esptool.py; do
  if command -v "$c" >/dev/null 2>&1; then ESPTOOL="$c"; break; fi
done
if [ -z "$ESPTOOL" ]; then
  VENV="${XDG_CACHE_HOME:-$HOME/.cache}/wled-esptool-venv"
  if [ ! -x "$VENV/bin/python" ]; then
    say "installing esptool into $VENV"
    python3 -m venv "$VENV" || die "could not create a venv; is python3 installed?"
    "$VENV/bin/pip" install -q --upgrade pip
    "$VENV/bin/pip" install -q esptool || die "esptool install failed"
  fi
  for c in "$VENV/bin/esptool" "$VENV/bin/esptool.py"; do
    [ -x "$c" ] && ESPTOOL="$c" && break
  done
  [ -n "$ESPTOOL" ] || die "esptool installed but no runnable entry point found in $VENV/bin"
fi
say "esptool: $ESPTOOL"

# esptool 5 renamed every subcommand from snake_case to kebab-case and warns
# loudly on the old spellings; pick by major version so this works on both.
ESPTOOL_MAJOR="$("$ESPTOOL" version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
ESPTOOL_MAJOR="${ESPTOOL_MAJOR:-4}"
if [ "$ESPTOOL_MAJOR" -ge 5 ]; then
  CMD_FLASH_ID="flash-id"; CMD_ERASE="erase-flash"; CMD_WRITE="write-flash"
else
  CMD_FLASH_ID="flash_id"; CMD_ERASE="erase_flash"; CMD_WRITE="write_flash"
fi
say "esptool major $ESPTOOL_MAJOR, using subcommand '$CMD_FLASH_ID'"

# ----------------------------------------------------------------- read the chip
# flash_id reports chip type, revision, MAC and flash size in one go - which
# covers both "is it an ESP32 and not an ESP8266" and "is there room for WLED".
say "reading chip (read-only)"
chip_info="$("$ESPTOOL" --port "$PORT" --baud 115200 "$CMD_FLASH_ID" 2>&1)" || {
  printf '%s\n' "$chip_info"
  die "could not talk to the board.
  Most common cause is that it did not enter bootloader mode. Hold the BOOT
  (sometimes IO0) button down, re-run this, and release it once you see
  'Connecting...'. A charge-only USB cable gives this exact error too."
}
printf '%s\n' "$chip_info"

chip_line="$(printf '%s' "$chip_info" | grep -i -m1 -E '^(Chip is|Chip type:)' || true)"
[ -n "$chip_line" ] || chip_line="$(printf '%s' "$chip_info" | grep -i -m1 'Detecting chip type' || true)"
[ -n "$chip_line" ] || die "esptool did not report a chip type; see output above"
case "$chip_line" in
  *ESP8266*) die "this is an ESP8266, not an ESP32.
  AudioReactive needs the ESP32's I2S peripheral and cannot run here. The
  project notes call this out as the thing to confirm first - so this is a
  clean stop, not a failure: find the ESP32 board." ;;
  *ESP32-C3*|*ESP32-S2*)
    die "$chip_line
  WLED's audioreactive build is for the original ESP32 only. This variant has
  no prebuilt audioreactive binary." ;;
esac
say "chip check passed: $chip_line"

flash_line="$(printf '%s' "$chip_info" | grep -i -m1 'Detected flash size' || true)"
[ -n "$flash_line" ] && say "$flash_line"
case "$flash_line" in
  *1MB*|*2MB*) printf 'WARNING: WLED ESP32 needs 4MB; %s may be too small.\n' "$flash_line" ;;
esac

if [ "$DO_FLASH" -eq 0 ]; then
  cat <<MSG

--------------------------------------------------------------------
VERIFY ONLY - nothing was written to the board.

The board is an ESP32 and esptool can talk to it, which is everything
Phase 0 needed to know before committing a flash.

To actually flash WLED $VERSION with AudioReactive:
    $0 --port $PORT --flash

That erases the flash (wiping any existing WiFi credentials) and writes
a fresh image, which is the standard path for a first install.
--------------------------------------------------------------------
MSG
  exit 0
fi

# --------------------------------------------------------------------- download
# WLED's ESP32 release .bin is the APPLICATION image only - it belongs at
# 0x10000, NOT at 0x0. A full flash needs three parts:
#
#   0x1000   2nd-stage bootloader
#   0x8000   partition table
#   0x10000  WLED application
#
# Getting this wrong is silent: esptool happily writes the app to 0x0 and
# reports "hash verified", then the ROM finds no bootloader and the board
# bootloops with "invalid header: 0x...". That is exactly what happened on
# 2026-09-12 before this was fixed.
#
# The boot parts are not in the GitHub release - they come from the installer
# site, which is where install.wled.me itself fetches them. WLED ships ONE
# canonical bootloader per chip (flagged 8MB) and re-flags it for other flash
# sizes; esptool does that re-flagging for us (header nibble + SHA-256 digest)
# whenever --flash-size is passed, so no client-side patching is needed here.
#
# The 4MB partition table really is called partitions_c3_4m.bin even for a
# plain ESP32 - that 4MB layout is byte-identical across chip families, so
# WLED shares one file. partitions_esp32_4m.bin does not exist (404).
BOOT_BASE="https://install.wled.me/bin/boot"
BIN="WLED_${VERSION}_ESP32_audioreactive.bin"
URL="https://github.com/wled/WLED/releases/download/v${VERSION}/${BIN}"
WORK="${TMPDIR:-/tmp}/wled-flash-$VERSION"
mkdir -p "$WORK"

# Flash size drives which partition table to use, so read it from the chip
# rather than assuming.
case "$flash_line" in
  *16MB*) FLASH_SIZE="16MB"; PARTS="partitions/partitions_esp32_16m.bin" ;;
  *8MB*)  FLASH_SIZE="8MB";  PARTS="partitions/partitions_esp32_8m.bin" ;;
  *4MB*)  FLASH_SIZE="4MB";  PARTS="partitions/partitions_c3_4m.bin" ;;
  *) die "could not determine flash size from: $flash_line
  WLED needs a known size to pick a partition table. Re-run the verify and
  check what the chip reports." ;;
esac
BOOTLOADER="bootloaders/esp32/bootloader_esp32_8m.bin"
say "flash size $FLASH_SIZE -> partition table $(basename "$PARTS")"

fetch() { # fetch <url> <dest> <min-bytes> <what>
  local url="$1" dest="$2" min="$3" what="$4"
  if [ ! -s "$dest" ]; then
    curl -fL --progress-bar -o "$dest.part" "$url" || die "download failed ($what): $url"
    mv "$dest.part" "$dest"
  fi
  local sz; sz="$(wc -c <"$dest" | tr -d ' ')"
  # A truncated or error-page download flashes "successfully" and then
  # bootloops, so refuse anything implausibly small rather than write it.
  [ "$sz" -ge "$min" ] || die "$what is only $sz bytes (expected >= $min). Delete $dest and retry."
  printf '  %-28s %8s bytes\n' "$(basename "$dest")" "$sz"
}

say "downloading firmware + boot parts"
fetch "$URL"                    "$WORK/$BIN"            1000000 "WLED application"
fetch "$BOOT_BASE/$BOOTLOADER"  "$WORK/bootloader.bin"  4096    "bootloader"
fetch "$BOOT_BASE/$PARTS"       "$WORK/partitions.bin"  1024    "partition table"

# An ESP32 application/bootloader image must begin with magic byte 0xE9. This
# catches an HTML error page saved under a .bin name, which is otherwise
# indistinguishable until the board refuses to boot.
for f in "$WORK/$BIN" "$WORK/bootloader.bin"; do
  magic="$(head -c1 "$f" | od -An -tx1 | tr -d ' \n')"
  [ "$magic" = "e9" ] || die "$(basename "$f") does not start with ESP32 magic 0xE9 (got 0x$magic) - not a firmware image."
done
say "all three parts present, magic bytes OK"

# ------------------------------------------------------------------------ flash
if [ "$ESPTOOL_MAJOR" -ge 5 ]; then FS_FLAG="--flash-size"; else FS_FLAG="--flash_size"; fi

say "erasing flash"
"$ESPTOOL" --port "$PORT" --baud "$BAUD" "$CMD_ERASE"

say "writing bootloader 0x1000, partitions 0x8000, WLED 0x10000"
"$ESPTOOL" --port "$PORT" --baud "$BAUD" "$CMD_WRITE" "$FS_FLAG" "$FLASH_SIZE" \
  0x1000  "$WORK/bootloader.bin" \
  0x8000  "$WORK/partitions.bin" \
  0x10000 "$WORK/$BIN"

cat <<MSG

--------------------------------------------------------------------
FLASHED. Next, still Phase 0 - no strip, no mic attached yet:

1. Power-cycle the board (unplug/replug the USB), then give it ~20s.
2. Join the WiFi network 'WLED-AP' (password: wled1234) and open the
   setup page it offers.
3. Enter the house WiFi credentials, then let it reboot onto the LAN.
4. Set an mDNS name and add a DHCP reservation, so the Home Assistant
   integration in Phase 5 does not lose it on a lease change.

THE GATE - what proves this worked:
   In WLED's effect list, look for effects marked with a music symbol
   (a single note for volume-reactive, a double note for frequency-
   reactive). Those markers only exist when the AudioReactive usermod
   is actually in the firmware. No markers means the wrong image got
   flashed - fix that now rather than three phases later.
--------------------------------------------------------------------
MSG
