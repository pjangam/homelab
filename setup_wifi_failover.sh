#!/bin/bash
# WiFi failover for Pi-hole.
#
# Context: Pi-hole runs on this box with a static IP (192.168.1.123) on the
# wired interface, and the router's LAN DNS setting points at that IP. The
# server reaches the LAN via an ethernet cable into a WiFi range extender
# that is NOT on the UPS. On a power outage the extender drops, enp1s0 loses
# carrier, and 192.168.1.123 disappears from the network entirely - the
# whole LAN loses DNS even though the router and this server are both still
# up on UPS power.
#
# Fix: fail over to a direct WiFi connection to the router's own radio
# (dlink_pramod), using the SAME static IP, so the router's DNS setting
# never needs to change. A NetworkManager dispatcher script brings the WiFi
# connection up when the wired interface loses carrier, and back down once
# wired returns, so only one interface ever holds the address at a time.
#
# Run with: ./setup_wifi_failover.sh
# Prompts for the WiFi password (not stored in this file) and for sudo.

set -e

WIRED_IFACE="enp1s0"
WIFI_IFACE="wlp2s0"
WIFI_SSID="dlink_pramod"
WIFI_CON_NAME="dlink_pramod-failover"
STATIC_IP="192.168.1.123/24"
GATEWAY="192.168.1.1"
DNS="8.8.8.8,1.1.1.1"
DISPATCHER_SCRIPT="/etc/NetworkManager/dispatcher.d/99-wifi-failover"

read -r -s -p "WiFi password for $WIFI_SSID: " WIFI_PSK
echo

echo "Creating WiFi failover connection profile ($WIFI_CON_NAME)..."
sudo nmcli con add type wifi ifname "$WIFI_IFACE" con-name "$WIFI_CON_NAME" ssid "$WIFI_SSID" \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PSK" \
  ipv4.method manual ipv4.addresses "$STATIC_IP" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS" \
  connection.autoconnect no

unset WIFI_PSK

echo "Installing dispatcher script ($DISPATCHER_SCRIPT)..."
sudo tee "$DISPATCHER_SCRIPT" > /dev/null << SCRIPT
#!/bin/bash
# Bring up the WiFi failover connection when $WIRED_IFACE loses carrier;
# drop it again once $WIRED_IFACE is back, so only one interface ever
# holds $STATIC_IP at a time.
[ "\$1" = "$WIRED_IFACE" ] || exit 0

case "\$2" in
  down|unavailable)
    logger -t wifi-failover "$WIRED_IFACE \$2 - bringing up $WIFI_CON_NAME"
    nmcli con up "$WIFI_CON_NAME" >/dev/null 2>&1
    ;;
  up)
    logger -t wifi-failover "$WIRED_IFACE up - bringing down $WIFI_CON_NAME"
    nmcli con down "$WIFI_CON_NAME" >/dev/null 2>&1
    ;;
esac
exit 0
SCRIPT

sudo chmod 755 "$DISPATCHER_SCRIPT"

echo
echo "Done."
echo "Verify the profile: nmcli con show"
echo "Watch failover events later with: journalctl -t wifi-failover -f"
echo
echo "Real test: pull power on the range extender (or unplug the ethernet"
echo "cable from this server) and confirm the LAN stays resolvable, then"
echo "restore power/cable and confirm it fails back to wired."
echo
echo "Reminder: point the router's LAN DNS setting back at 192.168.1.123"
echo "(Pi-hole) - it's currently still set to the public-DNS fallback from"
echo "the last outage."
