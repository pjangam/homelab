# xero as the LAN gateway (per-device usage)

xero forwards and NATs internet traffic for any LAN device whose default
gateway is `192.168.1.123`, and counts bytes per device IP on the way through.
The counts go to Prometheus via node-exporter's textfile collector as
`homelab_lan_gateway_bytes_total{ip, direction="up"|"down"}`.

**Opt-in by design.** The router (`192.168.1.1`) stays the gateway that DHCP
hands out, so installing this changes nothing for any device. A device only
goes through xero once it is pointed at it. `PROJECTS.md` "Per-device network
usage monitoring" tracks the rollout.

## Files

- `lan-gateway.nft` - nftables table `ip lan_gateway`: masquerade for
  LAN -> internet through `enp1s0`, and two dynamic sets (`up`, `down`) with a
  counter per device IP. Reloading it resets the counters.
- `usage_textfile.sh` - writes the counters to
  `services/node-exporter/textfile/lan_gateway.prom` (root, every minute).
- `setup_lan_gateway.sh` - installs it all; `--remove` undoes it. Run from a
  real terminal on xero (sudo).

What setup changes on xero: `/etc/sysctl.d/90-lan-gateway.conf` (forwarding
on, ICMP redirects off, or xero would tell devices to bypass it), and the
system units `lan-gateway.service` and `lan-gateway-usage.timer`. The service
loads the nft table and adds two ACCEPT rules to iptables' `DOCKER-USER`
chain (LAN -> internet, and its replies), after docker.service: Docker sets
the FORWARD policy to DROP, and ufw is installed but **inactive** on xero, so
a ufw rule does nothing (the first install's `ufw route allow` did exactly
that, 2026-10-22: every forwarded packet hit Docker's DROP).

`diagnose.sh` shows where a device's packets stop (counters, FORWARD chain,
a capture), when the gateway doesn't work.

## Testing with one device (the wol Pi)

Not persistent: a Pi reboot puts the router back. If forwarding is broken,
the Pi only loses internet; it stays reachable from xero on the LAN.

```bash
ssh -t wol-sender sudo ip route replace default via 192.168.1.123   # through xero
ssh wol-sender curl -sS -o /dev/null -w '%{http_code}\n' https://example.com
ssh wol-sender traceroute -n -m 2 1.1.1.1                           # hop 1 = .123
sudo nft list set ip lan_gateway up                                 # .124 counting
ssh -t wol-sender sudo ip route replace default via 192.168.1.1     # back to router
```

## Known limits

- **xero becomes the internet for every device that uses it.** A reboot, a
  kernel update or a crash cuts them off until it is back.
- **IPv6 bypasses xero.** The router advertises an IPv6 default route; today
  no global IPv6 address shows on xero, so the LAN looks IPv4-only, but check
  a device before trusting its numbers.
- **Devices behind the TP-Link extender** keep their own IPs, so per-IP
  counting still separates them (it rewrites their MACs).
- **Link speed:** 100Mb/s full duplex until xero's patch cable is replaced -
  enough for the 40 Mbps plan, tight at 100.
