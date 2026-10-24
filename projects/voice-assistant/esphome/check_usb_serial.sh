#!/usr/bin/env bash
# Is the ESP32 visible to this Mac? Run after each cable/dongle change while
# flashing a voice satellite (build_on_mac.sh needs a /dev/cu.* node).
#
# Reading it:
#   no Hub, no device      -> the dongle is not enumerating (or is not plugged in)
#   Hub but no device      -> the cable is charge-only, or the board has no power
#   device but no /dev/cu. -> USB-serial driver missing (CH340/CH9102 -> WCH driver)
#   device + /dev/cu.*     -> good, flash with: ./build_on_mac.sh living
set -uo pipefail

echo "== USB serial nodes (want a cu.usbserial-* / cu.wchusbserial* / cu.SLAB_USBtoUART*)"
ls -l /dev/cu.* 2>/dev/null | grep -v -E 'BLTH|Bluetooth' || echo "   none - only Bluetooth ports present"

echo
echo "== External USB devices (hubs, serial bridges; Apple internals filtered out)"
system_profiler SPUSBDataType 2>/dev/null | awk '
  /^ {8}[A-Za-z].*:$/ { name=$0; keep = name !~ /Apple|Touch Bar|Ambient Light|FaceTime|Keyboard|Trackpad|Headset|Bluetooth|iBridge/ }
  keep && /^ {8}[A-Za-z].*:$/ { print }
  keep && /Product ID|Vendor ID|Manufacturer|Serial Number/ { print }
' || true
echo "   (nothing listed above = the Mac sees no external USB device)"
