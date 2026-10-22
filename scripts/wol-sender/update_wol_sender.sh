#!/bin/bash
# Run on wol-sender (the Pi) via SSH:
#   ssh wol-sender bash -s < scripts/wol-sender/update_wol_sender.sh
# Installs the boot-time Wake-on-LAN sender for xero. History: a fixed
# `sleep 3`, then (2026-08-05) wait for a route + 3 packets, then
# (2026-10-22) wait for the router to answer + resend until xero is up,
# after the 3-packet version fired before the router had booted.
# Needs no password: the tee/chmod/systemctl calls are in the Pi's NOPASSWD
# sudoers (setup_wol_sender_nopasswd_sudo.sh).
set -euo pipefail

sudo tee /usr/local/bin/wol-xero-sender.sh > /dev/null <<'EOF'
#!/bin/bash
# After a power cut, wake xero once the LAN path to it is back. See
# wol-xero.service and PROJECTS.md "Power-outage watchdog" for context.
#
# Waits for the router (192.168.1.1) to answer, not just for a route: the Pi
# is on WiFi through the TP-Link extender, which is up well before the Airtel
# router finishes booting, and since 2026-10-17 xero is cabled to the router,
# so a packet sent before then goes nowhere. That is how the 2026-10-22
# outage left xero off: packets 4s after WiFi associated, router not up yet.
# Then keeps sending every 20s until xero has answered pings for 2 minutes,
# which also covers xero still being mid-shutdown when the Pi comes up.
set -uo pipefail
ROUTER=192.168.1.1
XERO=192.168.1.123
MAC=68:1D:EF:38:8C:72

up() { ping -c1 -W2 "$1" &>/dev/null; }

elapsed=0
until up "$ROUTER"; do
  if [ "$elapsed" -ge 600 ]; then
    logger -t wol-xero "router not answering after ${elapsed}s - sending anyway"
    break
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done
logger -t wol-xero "router up after ${elapsed}s"

sent=0
xero_up_since=
for _ in $(seq 1 60); do   # 60 x 20s = 20 minutes at most
  if up "$XERO"; then
    xero_up_since=${xero_up_since:-$SECONDS}
    if [ $((SECONDS - xero_up_since)) -ge 120 ]; then
      logger -t wol-xero "xero up for 2min - done ($sent magic packets sent)"
      exit 0
    fi
  else
    xero_up_since=
    wakeonlan -i 192.168.1.255 "$MAC" >/dev/null
    sent=$((sent + 1))
    [ "$sent" -eq 1 ] && logger -t wol-xero "xero not answering - sending magic packets every 20s"
  fi
  sleep 20
done
logger -t wol-xero "gave up after 20 minutes ($sent magic packets sent); xero still not answering"
exit 1
EOF

sudo chmod +x /usr/local/bin/wol-xero-sender.sh

sudo tee /etc/systemd/system/wol-xero.service > /dev/null <<'EOF'
[Unit]
Description=Send Wake-on-LAN magic packet to xero on boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wol-xero-sender.sh

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wol-xero.service

# No test run here: with xero up it only pings for 2 minutes and exits.
# `sudo systemctl start --no-block wol-xero.service` then
# `journalctl -t wol-xero -f` does that dry check.
echo "Updated."
