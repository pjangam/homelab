#!/bin/bash
# Fix HDMI hot-plug detection on i915 Jasper Lake (N5105)
# The display doesn't show up when HDMI is connected after boot.
# This sets up a udev rule + helper script to auto-enable the display.

set -e

UDEV_RULE="/etc/udev/rules.d/95-hdmi-hotplug.rules"
HOTPLUG_SCRIPT="/usr/local/bin/hdmi-hotplug.sh"

echo "Installing HDMI hot-plug helper script..."
sudo tee "$HOTPLUG_SCRIPT" > /dev/null << 'SCRIPT'
#!/bin/bash
# Triggered by udev when HDMI state changes.
# Runs xrandr as the logged-in user to enable the newly connected display.

sleep 2

USER_SESSION=$(loginctl list-sessions --no-legend | awk '{print $1}' | head -1)
if [ -z "$USER_SESSION" ]; then
    exit 0
fi

SESSION_USER=$(loginctl show-session "$USER_SESSION" -p Name --value)
DISPLAY_VAL=$(loginctl show-session "$USER_SESSION" -p Display --value)
XAUTHORITY_VAL="/home/$SESSION_USER/.Xauthority"

if [ -z "$DISPLAY_VAL" ]; then
    DISPLAY_VAL=":0"
fi

export DISPLAY="$DISPLAY_VAL"
export XAUTHORITY="$XAUTHORITY_VAL"

for connector in /sys/class/drm/card*-HDMI-A-*/status; do
    if [ "$(cat "$connector")" = "connected" ]; then
        output=$(basename "$(dirname "$connector")" | sed 's/card[0-9]*-//' | sed 's/-A-/-/')
        su - "$SESSION_USER" -c "DISPLAY=$DISPLAY_VAL XAUTHORITY=$XAUTHORITY_VAL xrandr --output $output --auto" 2>/dev/null
    fi
done
SCRIPT

sudo chmod +x "$HOTPLUG_SCRIPT"

echo "Installing udev rule..."
sudo tee "$UDEV_RULE" > /dev/null << 'RULE'
ACTION=="change", SUBSYSTEM=="drm", RUN+="/usr/local/bin/hdmi-hotplug.sh"
RULE

echo "Reloading udev rules..."
sudo udevadm control --reload-rules

echo "Done. HDMI hot-plug should now auto-detect when you plug in the cable."
echo "You can test by unplugging and re-plugging the HDMI cable."
