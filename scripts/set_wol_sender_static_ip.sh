#!/bin/bash
# Run on wol-sender (the Pi) via SSH. Pins its WiFi connection to a static
# IP instead of relying on the DHCP lease - it silently jumped from .103
# to .105 on a lease renewal (2026-08-21), which would silently break
# Node-RED once it's migrated here (HA's Miraie AC entity would just go
# stale with no obvious error). Picked .124 rather than reusing .103:
# DHCP servers typically hand out addresses from the bottom of the pool
# up, so a lower address is more likely to get leased to some other
# device later and collide with this static assignment - .124 (next to
# xero's own .123, easy to remember) sits further from that churn.
# Nothing in this repo hardcodes .103 functionally (checked 2026-08-21:
# only prose mentions in PROJECTS.md, and wol_listener.py logs whatever
# source IP sends it rather than filtering by one) so no other files need
# updating.
#
# Needs a sudo password (not covered by the scoped NOPASSWD sudoers rule
# in setup_wol_sender_nopasswd_sudo.sh), so run this interactively:
#   ssh -t pramod@<pi-current-ip> 'bash -s' < scripts/set_wol_sender_static_ip.sh
set -euo pipefail

CONN_NAME="dlink_pramod_bed_room"   # nmcli connection name for wlan0
STATIC_IP="192.168.1.124/24"
GATEWAY="192.168.1.1"
DNS="192.168.1.123"                 # xero / Pi-hole

sudo nmcli con mod "$CONN_NAME" \
  ipv4.method manual \
  ipv4.addresses "$STATIC_IP" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "$DNS"

echo "Applying - this SSH session will drop once the IP changes to ${STATIC_IP%/*}."
sudo nmcli con up "$CONN_NAME"
