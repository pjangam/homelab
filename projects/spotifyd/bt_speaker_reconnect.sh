#!/bin/bash
# Keep xero connected to the Portronics Apollo One over Bluetooth and make it
# the default PipeWire output, so spotifyd (ALSA "default" -> PipeWire) plays
# there. The speaker boots into Bluetooth mode, and AUX only comes back with a
# button press or a cable reseat, so Bluetooth is the hands-free path.
#
# Run from xero's crontab every minute. Quiet when nothing changes; logs only
# when it (re)connects or fixes the default sink.
#   BT_SPEAKER_MAC  speaker address (default: the Apollo One)
#   --dry-run       report state, change nothing

set -u
MAC="${BT_SPEAKER_MAC:-0D:67:1F:80:92:22}"
NAME="Portronics Apollo One"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
# cron has no session env; wpctl needs it to find the user's PipeWire
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

log() { echo "$(date '+%F %T') $*"; }

connected() { bluetoothctl info "$MAC" 2>/dev/null | grep -q "Connected: yes"; }

if ! connected; then
  [ $DRY = 1 ] && { log "not connected (dry run, not connecting)"; exit 0; }
  # Fails fast when the speaker is off, out of range, or held by the phone.
  # `bluetoothctl --timeout N` always sits out all N seconds, which delayed a
  # voice "play" by ~15s; poll instead and stop as soon as it is up.
  timeout 15 bluetoothctl --timeout 15 connect "$MAC" >/dev/null 2>&1 &
  bt=$!
  for _ in $(seq 30); do connected && break; sleep 0.5; done
  kill $bt 2>/dev/null; wait $bt 2>/dev/null
  if connected; then
    log "reconnected $NAME"
    sleep 3   # let PipeWire create the sink
  else
    exit 0    # speaker unavailable; try again next minute, no log spam
  fi
fi

# Sink id of the speaker in `wpctl status` (" │  *   51. Portronics Apollo One ...")
sink_line=$(wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -m1 "$NAME")
[ -z "$sink_line" ] && { log "connected but no PipeWire sink for $NAME"; exit 1; }
if ! grep -q '\*' <<<"$sink_line"; then
  id=$(grep -oE '[0-9]+\.' <<<"$sink_line" | head -1 | tr -d .)
  if [ $DRY = 1 ]; then log "connected; sink $id is not default (dry run)"; exit 0; fi
  wpctl set-default "$id" && log "set default sink to $NAME ($id)"
fi
