#!/usr/bin/env bash
set -euo pipefail

sudo apt install -y openssh-server
sudo systemctl enable --now ssh

sudo apt install -y net-tools copyq gnupg rclone

# Autostart CopyQ on login
mkdir -p ~/.config/autostart
cp /usr/share/applications/com.github.hluk.copyq.desktop ~/.config/autostart/

# Schedule daily Vaultwarden backup at 2 AM
HOMELAB_DIR="$(cd "$(dirname "$0")" && pwd)"
(crontab -l 2>/dev/null | grep -v "backup_vaultwarden.sh"; echo "0 2 * * * $HOMELAB_DIR/backup_vaultwarden.sh >> $HOMELAB_DIR/backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null | grep -v "backup_homeassistant.sh"; echo "0 3 * * * $HOMELAB_DIR/backup_homeassistant.sh >> $HOMELAB_DIR/backup.log 2>&1") | crontab -


git config --global user.email "pjangam2015@gmail.com"
git config --global user.name "Pramod"

# Free port 53 for Pi-hole
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
sudo rm /etc/resolv.conf
printf "nameserver 127.0.0.1\nnameserver 1.1.1.1\n" | sudo tee /etc/resolv.conf

# Start services
cd "$(dirname "$0")"
sudo docker compose up -d

# Set static IP (last — drops network connection)
if ! ip addr show enp1s0 | grep -q "192.168.1.123"; then
  sudo nmcli con mod "Wired connection 1" \
    ipv4.method manual \
    ipv4.addresses 192.168.1.123/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8 1.1.1.1"
  sudo nmcli con up "Wired connection 1"
else
  echo "Static IP already set, skipping."
fi
