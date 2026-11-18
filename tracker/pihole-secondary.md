# Secondary Pi-hole on the wol Pi
**Status:** Done

**Why:** xero runs the only Pi-hole, so xero down = the whole house without DNS (2026-08-28 was ~2h of it). xero is now suspected of bad RAM (gcc segfaults, the 2026-09-23 oops) and memtest means planned downtime. Decided 2026-10-06: a *second* Pi-hole on the wol Pi, with the router handing out xero as DNS 1 and the Pi as DNS 2. This does not reopen "RPi load migration", which ruled out *moving* Pi-hole to the Pi for lack of a UPS: xero stays primary and stays up on its UPS in a power cut.
**Outcome:** deployed 2026-10-06 (`services/pihole-secondary/`, README there); the router hands out both Pi-holes and LAN fallback was verified 2026-10-08. Left open: devices running Tailscale did not fall back (fix tracked in "Tailscale on the wol Pi, as the tailnet's second DNS server").

#### Deployment
Containers `pihole` (DNS :53, admin http://192.168.1.124:8081/admin, host networking) and `nebula-sync` (xero -> Pi every 6h, then gravity) on the Pi, via `deploy_pi.sh` from xero; password in `~/pihole-secondary.env` on the Pi (600). No sudo needed. ~20MB RSS together; the Pi's available memory went 457 -> 429MB.
- Forced on the Pi with `FTLCONF_`: web port 8081, listeningMode LOCAL (host networking), Pi-hole's NTP server off (would take :123), DHCP off. `--dns 1.1.1.1` for the container, since the Pi's resolv.conf points at xero.
- **Gotcha:** nebula-sync `FULL_SYNC=true` fails with 400 on `/api/config` - Pi-hole refuses API changes to env-forced keys (dns.listeningMode, ntp.*, webserver.port). Switched to selective sync: all gravity tables + dns (minus listeningMode), resolver, database, misc. `diag_config_patch.py` reproduces a sync section by section.

#### Gap: devices running Tailscale do not fall back
With xero's Pi-hole stopped, `ping google.com` on the Mac still failed, and the Mac sent the Pi no queries. Tailscale's "Override local DNS" is on with one global nameserver, xero's `100.70.215.25`, so a tailnet device sends every lookup to `100.100.100.100`, which forwards only to xero; the DHCP pair is never tried. Devices without Tailscale are fine. Fix tracked in "Tailscale on the wol Pi, as the tailnet's second DNS server".

#### Testing tip
Stop just the container (`docker stop pihole`, then `docker start pihole`), not the whole of xero. And `dig 192.168.1.124 google.com` without the `@` queries the system resolvers, not the Pi.

#### Log
- 2026-10-06: decided and deployed. Verified from xero: `dig @192.168.1.124 example.com` resolves, `doubleclick.net` -> `0.0.0.0`, query log shows real client IPs, adlists match xero (1, StevenBlack) and gravity counts match (72234 each), nebula-sync "Sync completed".
- 2026-10-08: router step done, fallback verified. The Airtel router's DHCP hands out `192.168.1.123, 192.168.1.124` (seen on the MacBook's lease), and LAN clients' queries now show up in both Pi-holes' logs. With xero's `pihole` container stopped, xero refused on :53 and the Pi answered, both from xero and from the Mac (`dig @192.168.1.124 google.com`). Found the Tailscale gap (above).
