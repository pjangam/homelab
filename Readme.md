Services to run

- [ ] Pinhole: ad blocker
- [ ] Node red : workflow engine for IOT
- [ ] MQTT broker
- [ ] 1password
- [ ] https://immich.app/docs/install/docker-compose/ : photos
- [ ] ftp server to dump files
- [ ] ftp backups- compress and encrypt
- [x] Tailscale
  - [ ] Bhakti user not able to connect to exit node






✅ Better Approach: Free up port 53 for Pi-hole
If you want Pi-hole to function properly and easily intercept DNS queries, the best approach is to free up port 53 on the host:

Option A: Disable systemd-resolved

Disable and stop it:
sudo systemctl disable systemd-resolved
sudo systemctl stop systemd-resolved
Remove the symlink to /run/systemd/resolve from /etc/resolv.conf:
sudo rm /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
(You can replace 1.1.1.1 with another DNS if needed; this is just temporary until Pi-hole takes over.)
Start your Pi-hole Docker container with port 53 available.

