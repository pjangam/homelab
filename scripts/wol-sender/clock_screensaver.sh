#!/bin/bash
# Screensaver for the wol-sender Pi's labwc (Wayland) desktop: after
# IDLE_SECONDS without input, show analog_clock.py fullscreen. The clock
# closes itself on any key, click or mouse movement.
# Started at login by ~/.config/autostart/clock-screensaver.desktop.
# Installed by deploy_clock_screensaver.sh.
IDLE_SECONDS=300
CLOCK="$HOME/analog_clock.py"

exec swayidle timeout "$IDLE_SECONDS" \
    "pgrep -f '$CLOCK' >/dev/null || python3 '$CLOCK' &"
