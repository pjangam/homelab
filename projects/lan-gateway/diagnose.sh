#!/bin/bash
# Why isn't a device's traffic getting through xero as its gateway? Run on
# xero from a real terminal (sudo):  projects/lan-gateway/diagnose.sh [device-ip]
# Has the device (default: the wol Pi, over ssh) ping 1.1.1.1 while it
# captures, then shows where the packets stopped. Changes nothing.
set -uo pipefail
dev=${1:-192.168.1.124}
out="$(dirname "$0")/diagnose-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$out") 2>&1

echo "== lan_gateway table (counters)"; sudo nft list table ip lan_gateway
echo; echo "== iptables FORWARD (packet counts)"; sudo iptables -L FORWARD -v -n --line-numbers
echo; echo "== ufw-user-forward"; sudo iptables -L ufw-user-forward -v -n
echo; echo "== nat POSTROUTING"; sudo iptables -t nat -L POSTROUTING -v -n
echo; echo "== ufw status"; sudo ufw status verbose | head -20
echo; echo "== ip rules / route to 1.1.1.1 from $dev"; ip rule; ip route get 1.1.1.1 from "$dev" iif enp1s0
echo; echo "== rp_filter"; sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.enp1s0.rp_filter

echo; echo "== capture: $dev pings 1.1.1.1"
sudo timeout 8 tcpdump -lni enp1s0 -c 40 "icmp and host 1.1.1.1" &
sleep 2
[ "$dev" = 192.168.1.124 ] && ssh -o ConnectTimeout=5 wol-sender 'ping -c3 -W1 1.1.1.1 | tail -2'
wait
echo; echo "== after: FORWARD counters"; sudo iptables -L FORWARD -v -n
echo; echo "Saved to $out"
