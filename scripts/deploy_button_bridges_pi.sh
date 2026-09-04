#!/usr/bin/env bash
# Run this ON XERO. Pushes the current copies of the two GPIO button bridges
# to the wol-sender Pi and restarts both services.
#
# No sudo needed: the units are already installed and run as `pramod`, and
# both have Restart=always, so killing the main process is enough to make
# systemd restart the service with the new script.
set -euo pipefail

PI="pramod@192.168.1.124"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

scp "$REPO/scripts/white-noise-buttons-mqtt.py" "$REPO/scripts/scene-buttons-mqtt.py" "$PI:~/"

ssh "$PI" bash -s <<'REMOTE'
set -euo pipefail
chmod +x ~/white-noise-buttons-mqtt.py ~/scene-buttons-mqtt.py

# Stale FIFO from the shared-CWD collision - the bridges now each create their
# own under ~/.lgpio/<script>/ (see isolate_lgpio_notify_dir in the scripts).
rm -f ~/.lgd-nfy*

for svc in white-noise-buttons-mqtt scene-buttons-mqtt; do
  pid=$(systemctl show -p MainPID --value "$svc")
  echo "== restarting $svc (main pid $pid) =="
  [ "$pid" != "0" ] && kill "$pid"
done

sleep 12
for svc in white-noise-buttons-mqtt scene-buttons-mqtt; do
  echo "== $svc: $(systemctl is-active $svc) =="
  journalctl -u "$svc" --no-pager -n 6 -o cat
done
REMOTE
