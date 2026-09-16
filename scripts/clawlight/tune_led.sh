#!/usr/bin/env bash
# Run this ON XERO. Picks a physical clawlight LED setting by eye: stops
# clawlight-led on the wol-sender Pi, steps through candidate values with each
# one printed as a ready-made line for clawlight-led.py, then starts the
# service again. Put the line that looks right into the script and redeploy.
#
#   scripts/clawlight/tune_led.sh amber   # AMBER, the red/green mix
#   scripts/clawlight/tune_led.sh idle    # IDLE_BRIGHTNESS, using the current AMBER
#
# One ssh -t session, so the Pi's sudo password is asked once and cached for
# the start at the end. Copying the script needs no sudo; the running service
# only picks the new copy up when it restarts, which is fine - the change it
# carries is additive.
set -euo pipefail

case "${1:-}" in
  amber|idle) what="$1" ;;
  *) echo "usage: $0 amber|idle" >&2; exit 2 ;;
esac

PI="pramod@192.168.1.124"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

scp -q "$REPO/scripts/clawlight/clawlight-led.py" "$PI:~/clawlight-led.py"
ssh -t "$PI" '
sudo systemctl stop clawlight-led
trap "sudo systemctl start clawlight-led; echo \"== clawlight-led: \$(systemctl is-active clawlight-led) ==\"" EXIT
GPIOZERO_PIN_FACTORY=lgpio /home/pramod/.local/bin/uv run ~/clawlight-led.py --tune-'"$what"'
'
