#!/bin/bash
# Wraps `play -n synth brownnoise` with an ALSA volume ramp: slow fade-in on
# start (soothing for baby), quick fade-out on stop (systemd SIGTERM).
set -u

CARD=1
CTRL=Speaker
MIN_VOL=5
MAX_VOL=100
FADE_IN_STEPS=20
FADE_IN_STEP_SECONDS=1.5
FADE_OUT_STEPS=4
FADE_OUT_STEP_SECONDS=0.3

set_vol() {
    amixer -c "$CARD" sset "$CTRL" "$1%" >/dev/null
}

PLAY_PID=""

fade_out_and_exit() {
    for ((i = FADE_OUT_STEPS; i >= 1; i--)); do
        vol=$(( MIN_VOL + (MAX_VOL - MIN_VOL) * i / FADE_OUT_STEPS ))
        set_vol "$vol"
        sleep "$FADE_OUT_STEP_SECONDS"
    done
    set_vol "$MIN_VOL"
    [ -n "$PLAY_PID" ] && kill "$PLAY_PID" 2>/dev/null
    set_vol "$MAX_VOL"
    exit 0
}

trap fade_out_and_exit TERM INT

set_vol "$MIN_VOL"
play -n -q synth brownnoise &
PLAY_PID=$!

for ((i = 1; i <= FADE_IN_STEPS; i++)); do
    vol=$(( MIN_VOL + (MAX_VOL - MIN_VOL) * i / FADE_IN_STEPS ))
    set_vol "$vol"
    sleep "$FADE_IN_STEP_SECONDS"
done

wait "$PLAY_PID"
