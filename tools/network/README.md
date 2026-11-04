# network

Diagnosis for "the network is slow / DNS is broken", kept as scripts because
each one answers a question that guessing gets wrong. Several **run on the
MacBook**, not on xero - that is noted in every header and matters.

## Throughput

| | |
|---|---|
| `lancheck.sh` | why is a copy to xero slow? Measures the LAN path hop by hop - bad Wi-Fi association vs capped wired hop vs stalled transfer |
| `speedcheck.sh` | domestic vs international throughput, to tell "my line is slow" from "my ISP's international transit is congested" |
| `queue_big_copy.sh` | copy large files over a link that stalls, optionally waiting for a transfer already in flight |

## DNS

| | |
|---|---|
| `diagnose_dns_paths.sh` | **which** resolver actually answered - marker queries down each path, then looked for in Pi-hole's log (resolution succeeding proves nothing) |
| `watch-peer-dns.sh` | live Pi-hole log for one client, with a heartbeat so silence is meaningful rather than ambiguous |
| `tailscale-dns-probe.sh` | "Tailscale can't reach configured DNS server" - captures what actually arrives on `tailscale0:53`, separating client-side from server-side |
| `fix_tailscale_resolvconf.sh` | let `tailscaled` manage `/etc/resolv.conf` again on xero (the systemd-resolved package's leftover `resolvconf` symlink) |
| `render_ts_serve_config.sh` | render a tailscale sidecar's `serve-config.json` from the template in [`services/tailscale/`](../../services/tailscale/README.md) |

## The MacBook's recurring DNS break

It has broken the same way at least three times (2026-08-28, 2026-09-10,
2026-09-16): `en0` resolving against `192.168.0.2` + `192.169.0.2`, two servers
not on this LAN, so queries hang rather than fail. Root-caused to OpenVPN
Connect's agent writing them at connect time - see `PROJECTS.md`, "MacBook DNS
keeps breaking", and `docs/incidents/2026-09-23-mac-dns-openvpn-connect-left-stale-servers.md`.

| | |
|---|---|
| `diagnose_macbook_dns.sh` | what the Mac is configured to use, right now |
| `fix_macbook_dns.sh` | undo the overrides (needs sudo, on the Mac) |
| `find_mac_stale_dns.sh` | read-only hunt for the bad pair in the places that **survive** the repair |
| `mac-dns-recorder.sh` + `setup-mac-dns-recorder.sh` | record the resolver config every time it changes, under launchd - for catching it when nobody is watching |
| `summarize_dns_snapshots.sh` | collapse that log to its transitions, against the tunnel coming up and down |
| `summarize_ovpnagent_dns.sh` | every DNS write `ovpnagent` made, and whether it restored it |
| `test_find_mac_stale_dns.sh`, `test_mac_dns_recorder.sh` | tests |
