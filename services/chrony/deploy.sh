#!/usr/bin/env bash
# Run this ON XERO, in a terminal (both halves ask for a sudo password).
#
#   1. xero: install chrony (it replaces systemd-timesyncd) and make it an NTP
#      server for the LAN that keeps serving from the RTC through an ISP outage.
#   2. the wol-sender Pi: point systemd-timesyncd at xero first.
#
# Why: the Pi has no RTC. On 2026-09-28 a power cut plus an ISP outage left it
# booting on its last saved time, 15 minutes behind, until the internet came
# back 10 hours later. With xero answering on the LAN it is right within a
# minute of xero booting.
#
#   services/chrony/deploy.sh          # both
#   services/chrony/deploy.sh xero     # just xero
#   services/chrony/deploy.sh pi       # just the Pi
set -euo pipefail

PI="pramod@192.168.1.124"
HERE="$(cd "$(dirname "$0")" && pwd)"
what=${1:-both}

deploy_xero() {
  echo "== xero: chrony =="
  sudo apt-get install -y chrony
  sudo install -m 644 "$HERE/lan-server.conf" /etc/chrony/conf.d/lan-server.conf
  sudo systemctl restart chrony
  if systemctl is-active -q ufw; then
    sudo ufw allow from 192.168.1.0/24 to any port 123 proto udp comment 'NTP for the LAN (chrony)'
  fi
  sleep 3
  chronyc tracking
  chronyc sources
  ss -ulpn | grep ':123 ' || { echo "chrony is not listening on udp/123" >&2; exit 1; }
}

deploy_pi() {
  echo "== Pi: timesyncd -> xero =="
  scp -q "$HERE/timesyncd-xero.conf" "$PI:~/timesyncd-xero.conf"
  # ssh -t with the commands as an argument: sudo on the Pi needs a terminal.
  ssh -t "$PI" '
set -euo pipefail
sudo install -d /etc/systemd/timesyncd.conf.d
sudo install -m 644 ~/timesyncd-xero.conf /etc/systemd/timesyncd.conf.d/xero.conf
rm -f ~/timesyncd-xero.conf
sudo systemctl restart systemd-timesyncd
sleep 5
timedatectl show-timesync -p ServerName -p ServerAddress
timedatectl | grep synchronized
'
}

case $what in
  both) deploy_xero; deploy_pi ;;
  xero) deploy_xero ;;
  pi)   deploy_pi ;;
  *) echo "usage: $0 [both|xero|pi]" >&2; exit 1 ;;
esac
