# Tailscale on the wol Pi, as the tailnet's second DNS server
**Status:** Done

**Why:** tailnet devices lose DNS whenever xero's Pi-hole is down, even at home with the secondary Pi-hole running (found 2026-10-08, see "Secondary Pi-hole on the wol Pi"). Tailscale's DNS settings have "Override local DNS" on with a single global nameserver, xero's `100.70.215.25`, so the Tailscale resolver on each device (`100.100.100.100`) forwards only to xero and never reaches the DHCP-provided Pi.
**Outcome:** done 2026-10-08: Tailscale runs on the Pi as `wol-sender` (`100.127.187.58`), its Pi-hole listens on the tailnet, and the tailnet's global nameservers are xero's `100.70.215.25`, then the Pi's `100.127.187.58`. Fallback tested from the Mac with xero's `pihole` stopped. Left open: not tested on a phone on mobile data; the log does not record step 6's `docs/hardware.md` update or the check-script re-run.

#### Options rejected
- **Adding the Pi's LAN IP `192.168.1.124` as the second global nameserver.** The setting applies tailnet-wide, wherever a device is, and Tailscale may query nameservers in parallel rather than only on failure. A laptop on an office or cafe LAN would then also send its lookups to whatever host has `192.168.1.124` there - a very common subnet - which could see or answer them.
- **Turning "Override local DNS" off.** At home it would work through DHCP's pair, but away from home it drops Pi-hole ad-blocking, and the Mac DNS work assumes tailnet-wide DNS.

#### Plan
1. Install Tailscale on the Pi (needs `sudo` - the user runs it from a real terminal with `ssh -t`, a `!` command has no tty): `curl -fsSL https://tailscale.com/install.sh | sh`, then `sudo tailscale up --accept-dns=false` (the Pi must keep resolving through its own resolv.conf, not loop through MagicDNS). Note its `100.x` address.
2. In the admin console, disable key expiry for the Pi, so the fallback does not silently die months later.
3. Pi-hole on the Pi: listeningMode `LOCAL` -> `ALL` in `services/pihole-secondary/run_containers.sh`, since LOCAL refuses queries from `100.x` sources (tailscale0 is a /32, not a local subnet). With host networking ALL means anyone on the LAN or the tailnet, and the Pi is not port-forwarded. Redeploy with `deploy_pi.sh`; update the README's listeningMode rationale.
4. Admin console -> DNS -> Global nameservers: **replace** the stopgap `192.168.1.124` with the Pi's `100.x`, below xero's `100.70.215.25`. Keep "Override local DNS" on.
5. Test: `docker stop pihole` on xero, then `ping -c 3 google.com` on the Mac (and a phone on mobile data with Tailscale on), check the Pi's log shows the queries from `100.x` addresses, then `docker start pihole`.
6. Update `docs/hardware.md` (the Pi's tailnet name and address, tailscaled) and `projects/endpoints/endpoints.toml` (the Pi's DNS on the tailnet), and re-run both check scripts.

#### Cost
tailscaled is about 30-40MB RSS; the Pi has about 380MB available with Node-RED and both Pi-hole containers running (2026-10-08).

#### Log
- 2026-10-08: gap found (see "Secondary Pi-hole on the wol Pi").
- 2026-10-08: stopgap - the user added `192.168.1.124` as the second global nameserver anyway, for now, carrying the foreign-LAN risk above until step 4 swapped it out. Tested the same day: with xero's `pihole` stopped, the Mac's lookups reached the Pi (from `192.168.1.4`).
- 2026-10-08: steps 1-2 done by the user (Tailscale up on the Pi as `wol-sender`, `100.127.187.58`; key expiry off).
- 2026-10-08: step 3 done: listeningMode ALL deployed with `deploy_pi.sh`; before it, `dig @100.127.187.58 google.com` from the Mac timed out, after it resolves and `doubleclick.net` gives `0.0.0.0`; LAN still answers; nebula-sync "Sync completed". `endpoints.toml` updated.
- 2026-10-08: step 4 done by the user the same evening: the Mac's `tailscale dns status` lists resolvers `100.70.215.25`, then `100.127.187.58`; the LAN stopgap is gone.
- 2026-10-08: **step 5 passed 22:38:** with xero's `pihole` stopped, the Mac's lookups of google.com still resolved and `ping google.com` worked, and the Pi's `pihole.log` shows the queries arriving from the Mac's tailnet address `100.74.192.33`. xero's `pihole` started again straight after. Not tested: a phone on mobile data.
