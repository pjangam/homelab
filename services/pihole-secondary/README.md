# services/pihole-secondary/

A second Pi-hole on the wol Pi (`192.168.1.124`), kept in step with xero's
(`192.168.1.123`) by [nebula-sync](https://github.com/lovelaze/nebula-sync).
Deployed 2026-10-06.

## Why

xero runs the house's only Pi-hole, so when xero is down the whole LAN loses
DNS (2026-08-28 was two hours of that). xero is now suspected of bad RAM and
due a memtest, which means planned downtime. With the router handing out xero
as DNS 1 and the Pi as DNS 2, devices fall back to the Pi.

This is a *second copy*, not a move. Moving Pi-hole to the Pi was ruled out
because the Pi has no UPS (PROJECTS.md, RPi load migration); xero stays the
primary and stays up on its UPS during power cuts, when the Pi drops out.

## What runs on the Pi

| Container | Image | Network | What |
|---|---|---|---|
| `pihole` | `pihole/pihole:latest` | host | DNS on :53 (TCP+UDP), admin UI on `http://192.168.1.124:8081/admin` |
| `nebula-sync` | `ghcr.io/lovelaze/nebula-sync:latest` | host | pulls xero's config into this Pi-hole at start and every 6h (`0 */6 * * *`), then runs gravity |

- Data: `~/pihole-secondary/etc-pihole` on the Pi.
- Secrets: `~/pihole-secondary.env` on the Pi (mode 600, not in git). Same
  password as xero's (`PIHOLE_PASSWORD` in xero's `.env`).
- Both `--restart unless-stopped`. Together about 20MB RSS.

Differences from xero, forced with `FTLCONF_` variables (which also makes the
sync unable to change them):

- **Admin UI on 8081**, the same port as xero's, but natively, since it is host
  networking.
- **listeningMode ALL** (LOCAL until 2026-10-08): the Pi is the tailnet's
  second DNS server (Tailscale `wol-sender`, `100.127.187.58`), and LOCAL
  refused those queries - it answers only directly attached subnets, and
  `tailscale0` is a /32. On host networking ALL answers anyone who can reach
  the Pi: the LAN and the tailnet. The Pi is not port-forwarded, so nothing
  beyond that.
- **NTP server off**: xero's Pi-hole has it on, harmlessly, because its :123 is
  not published. Here it would bind :123 on the Pi.
- **The container resolves with 1.1.1.1** (`--dns`), because the Pi's own
  resolv.conf points at xero, and gravity has to download lists while xero is
  down too. Its upstreams (8.8.8.8, 8.8.4.4, synced from xero) never involve
  xero.

### What syncs

Selective sync, **not** `FULL_SYNC`. A full sync PATCHes every config section,
and Pi-hole rejects the dns, ntp and webserver sections with 400 ("Config items
set via environment variables cannot be changed via the API") because of the
forced settings above, which fails the whole run. Synced: every gravity table
(adlists, allow/deny domains, groups, clients) and the dns (minus
listeningMode), resolver, database and misc config. Not synced: ntp, dhcp,
webserver, debug. If a sync fails with a 400 again, `diag_config_patch.py` (run
on the Pi) PATCHes one section at a time and prints Pi-hole's error.

Changes go one way: make them on **xero's** Pi-hole. Anything changed on the
Pi's is overwritten at the next sync.

## Deploy / update

From xero:

```
services/pihole-secondary/deploy_pi.sh           # first deploy, or pull new images
services/pihole-secondary/deploy_pi.sh --rekey   # after changing PIHOLE_PASSWORD
```

It writes `~/pihole-secondary.env` on the Pi over ssh stdin (only if missing,
or with `--rekey`), copies `run_containers.sh` to
`~/homelab/services/pihole-secondary/` there and runs it. The Pi has no repo
clone. No sudo needed. Re-running replaces both containers and keeps the data;
nebula-sync syncs again as soon as it starts.

Check it:

```
dig @192.168.1.124 example.com              # resolves
dig +short @192.168.1.124 doubleclick.net   # 0.0.0.0
ssh 192.168.1.124 docker logs nebula-sync   # "Sync completed"
```

## The router step (done by hand, not by any script)

In the Airtel router's LAN/DHCP settings set **DNS 1 = `192.168.1.123`** (xero)
and **DNS 2 = `192.168.1.124`** (the Pi). Devices only pick it up on their next
DHCP lease, so reconnect them to the Wi-Fi (or wait for the lease to renew).

Clients choose between the two servers themselves - many spread queries across
both rather than strictly falling back - so blocking and the query log are
split across both Pi-holes. Both block the same lists, so that is expected.
