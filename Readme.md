Services to run

- [ ] Pinhole: ad blocker
- [ ] Node red : workflow engine for IOT
- [ ] MQTT broker
- [ ] 1password
- [ ] https://immich.app/docs/install/docker-compose/ : photos
- [ ] ftp server to dump files
- [ ] ftp backups- compress and encrypt
- [ ] Immich data redundancy: evaluate RAID (RAID-1 mirror or RAID-5) for the photo volume — backup is skipped due to size, so disk redundancy is the safety net
- [x] Tailscale
  - [ ] Bhakti user not able to connect to exit node

## Machine-specific config (xero — Beelink Mini PC, Intel N5105, Lubuntu)
These fixes are gated behind `hostname == xero` in `new_machine_setup.sh` and won't run on other machines.

- [x] Disable deep CPU C-states — N5105 Jasper Lake has a known Linux kernel bug causing hard freezes (`intel_idle.max_cstate=1` in GRUB)
- [x] Increase swap to 4GB — 512MB default is too low for Docker workloads
- [x] Disable USB auto-suspend — Logitech USB receiver disconnects due to Linux USB power management
- [ ] Temperature monitoring via Home Assistant — CPU idles at ~65°C, monitor spikes under load






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

