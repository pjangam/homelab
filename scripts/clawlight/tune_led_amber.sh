#!/usr/bin/env bash
# Run this ON XERO. Picks the physical clawlight LED's AMBER mix by eye: stops
# clawlight-led on the wol-sender Pi, holds amber at each green share from 0.1
# to 1.0 for 5s with the value printed, then starts the service again. Put the
# share that looks amber into AMBER in clawlight-led.py and redeploy.
#
# One ssh -t session, so the Pi's sudo password is asked once and cached for
# the start at the end. Copying the script needs no sudo; the running service
# only picks the new copy up when it restarts, which is fine - the change it
# carries is additive.
set -euo pipefail

PI="pramod@192.168.1.124"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

scp -q "$REPO/scripts/clawlight/clawlight-led.py" "$PI:~/clawlight-led.py"
ssh -t "$PI" '
sudo systemctl stop clawlight-led
trap "sudo systemctl start clawlight-led; echo \"== clawlight-led: \$(systemctl is-active clawlight-led) ==\"" EXIT
GPIOZERO_PIN_FACTORY=lgpio /home/pramod/.local/bin/uv run ~/clawlight-led.py --tune-amber
'
