#!/usr/bin/env bash
# Watch the USB bus for a serial adapter appearing, for as long as given
# (default 45s). Written for the aarti lights ESP32 flash (see
# aarti_lights_setup.md Phase 0), but it is the right tool any time a board
# "is plugged in" and /dev has nothing new in it.
#
# The point is to separate three cases that look identical from `ls /dev`:
#   1. kernel sees nothing at all      -> cable, port, or board power
#   2. kernel sees it, enumeration fails -> flaky cable/port, or dying bridge
#   3. it enumerates fine              -> then it was only ever permissions
#
#   ./scripts/watch-usb-serial.sh          # watch 45s
#   ./scripts/watch-usb-serial.sh 90       # watch 90s
set -u
secs="${1:-45}"

before_usb="$(lsusb | sort)"
before_tty="$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | sort)"

echo "Watching the USB bus for ${secs}s."
echo "UNPLUG the board and PLUG IT BACK IN now - the replug is what this sees."
echo

# udevadm monitor works unprivileged and reports kernel-level events, so a
# device that appears and fails still shows up here even though it never
# becomes a /dev node.
timeout "$secs" udevadm monitor --udev --kernel --subsystem-match=usb --subsystem-match=tty 2>/dev/null \
  | grep --line-buffered -E "add|remove|bind|unbind" \
  | grep --line-buffered -v -E "usb_device|/devices/virtual" \
  || true

echo
echo "=== what changed ==="
after_usb="$(lsusb | sort)"
after_tty="$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | sort)"

if [ "$before_usb" = "$after_usb" ]; then
  echo "lsusb: NO CHANGE - the kernel never saw a device attach."
  echo
  echo "In order of how often it is the cause:"
  echo "  1. A charge-only USB cable. By far the most common. It powers the"
  echo "     board so its LED lights and it looks alive, while carrying no"
  echo "     data lines at all. Swap the cable before suspecting anything"
  echo "     else - preferably with one known to have synced a phone."
  echo "  2. A dead or unpowered port. Try a different one, directly on the"
  echo "     machine rather than through a hub."
  echo "  3. The board is not powered: no LED lit at all when plugged in."
  echo "  4. The USB-serial bridge on the board has failed (rare, but it is"
  echo "     the diagnosis left once the cable and port are ruled out)."
else
  echo "lsusb: CHANGED"
  diff <(printf '%s\n' "$before_usb") <(printf '%s\n' "$after_usb") | sed 's/^/  /'
fi

if [ "$before_tty" != "$after_tty" ]; then
  echo
  echo "serial devices: CHANGED - this is what you want"
  diff <(printf '%s\n' "$before_tty") <(printf '%s\n' "$after_tty") | sed 's/^/  /'
fi

echo
echo "=== drivers loaded now ==="
lsmod | grep -i -E "ch341|cp210|ftdi_sio|usbserial|cdc_acm" || echo "  (still none)"
