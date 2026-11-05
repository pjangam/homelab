#!/bin/bash
# Screen blanking for the wol-sender Pi's labwc (Wayland) desktop: after
# IDLE_SECONDS without input, switch every output off (DPMS, via wlopm), and
# back on at the next key, click or mouse move. With no HDMI signal the LG
# 27UK650 drops to standby instead of drawing ~45W for an empty desktop.
#
# Replaces clock_screensaver.sh (retired 2026-11-05): that swayidle was the
# only idle handler on the Pi, and labwc/Raspberry Pi OS blank nothing
# themselves, so without this the monitor stayed on forever.
# Started at login by ~/.config/autostart/screen-blank.desktop; installed by
# deploy_screen_blank.sh.
IDLE_SECONDS=${IDLE_SECONDS:-600}
exec swayidle timeout "$IDLE_SECONDS" "wlopm --off '*'" resume "wlopm --on '*'"
