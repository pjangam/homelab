## New Machine Setup

Run `new_machine_setup.sh` then complete these manual steps:

1. **Rclone / Dropbox** — `rclone config` (name the remote `backup`), then create `.env.backup`:
   ```
   BACKUP_PASSPHRASE='your-passphrase'
   ```
2. **Secrets** — create `.env` (gitignored) with service passwords:
   ```
   PIHOLE_PASSWORD=<your-password>
   ```
   Pi-hole password is stored in `.env` on the server (not in git). Check Bitwarden for the current value.
3. **Tailscale** — `sudo tailscale up` and follow the auth URL, then re-run the script so `tailscale cert` can generate the SSL cert for Caddy
4. **Reboot** — required for the C-state GRUB fix to take effect (N5105 machines only)

---

## Miraie AC (Node-RED + MQTT)

Mosquitto and the `node-red-contrib-ha-miraie-ac` node are set up automatically. Manual steps after first run:

1. Open Node-RED at `http://192.168.1.123:1880`
2. Find the `ha-miraie-ac` node in the palette (left sidebar), drag it into a flow
3. Configure it with your Miraie registered mobile number + password
4. In Home Assistant: Settings → Integrations → Add Integration → MQTT → host `192.168.1.123`, port `1883`
5. Search for `climate` entities in HA — your AC should appear after the node connects

---

## Vaultwarden

Signups are currently **disabled** (`SIGNUPS_ALLOWED: "false"` in `docker-compose.yml`). To allow a new account, temporarily set it to `"true"`, run `sudo docker compose up -d vaultwarden`, create the account, then set it back to `"false"`.

---

## Services to run

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

## Machine-specific config (Beelink Mini PC, Intel N5105, Lubuntu)
These fixes are gated behind a CPU model check (`N5105` in `/proc/cpuinfo`) in `new_machine_setup.sh` and won't run on other machines.

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

