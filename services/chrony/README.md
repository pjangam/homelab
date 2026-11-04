# chrony (LAN time server)

xero answers NTP for the LAN, because the wol-sender Pi has **no RTC**. On
2026-09-28 a power cut plus an ISP outage left the Pi booting on its last saved
time, 15 minutes behind, and stuck there for the 10 hours until the internet
came back.

- [`lan-server.conf`](lan-server.conf) - dropped into `/etc/chrony/conf.d/` on
  xero. Ubuntu's stock config still supplies the upstream pools; this adds only
  the LAN-server half: `allow 192.168.1.0/24`, plus `local stratum 10` so xero
  **keeps serving from its own battery-backed RTC through an ISP outage**
  (without it chrony refuses to serve until it has reached an upstream - the
  exact case this exists for). Stratum 10 means any real upstream still wins.
- [`timesyncd-xero.conf`](timesyncd-xero.conf) - points the Pi's
  systemd-timesyncd at xero first.
- [`deploy.sh`](deploy.sh) - installs both halves. Run it **on xero, in a real
  terminal**; both halves sudo-prompt. `deploy.sh xero` does just the server.

chrony replaces systemd-timesyncd on xero.
