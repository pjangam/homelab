# Taking xero down: dependencies and checklist

What stops working when xero does, what to do before pulling the plug, and
how to check it came back. Read this **before** any planned downtime - a
shutdown, a reboot for the SSD move, a RAM swap, a case opening.

> **The one that surprises people: since 2026-10-22, xero downtime is a
> house-wide internet outage, not just a services outage.** The Airtel
> router's DHCP hands out `192.168.1.123` (xero) as the **default gateway**,
> so every phone, laptop and TV routes through it. They do not fail over.
> `projects/lan-gateway/README.md` still says "opt-in by design" - that
> describes the install, not the rollout. See "Per-device network usage
> monitoring" in `PROJECTS.md`.

## Blast radius

### Stops working

| What | Who notices | Notes |
|---|---|---|
| **Internet for the whole house** | everyone | Gateway is `.123`. No automatic failover; devices sit dark until xero is back or they get a lease pointing at `.1` |
| **Home Assistant** | everyone | Automations, both voice satellites, dashboards, the AC, lights, kandil, white noise |
| **MQTT (`mosquitto`)** | the Pi, HA | Every local integration speaks through it: the Pi's Node-RED/MirAIe AC, `pi-health`, `white-noise`, `xero-stats`. The Pi stays up but its MQTT publishes fail |
| **LAN time (`chrony`)** | the wol Pi | **The Pi has no RTC.** A long outage leaves its clock wrong on boot |
| **Vaultwarden** | passwords | Clients hold a cache; new logins and syncs fail |
| **Immich** | photos | Phone uploads queue and retry |
| **Samba shares** | `phone-uploads`, `albums`, `documents` | |
| **`albums-gallery`** | **family, over the internet** | Tailscale **Funnel is on** - the public album link is the only internet-reachable service on xero. Someone outside the house may be mid-view |
| **Pi-hole (primary)** | - | Falls to the Pi's secondary, see below |
| Caddy, Grafana, Prometheus, `projects-ui`, `/endpoints`, `wishlist`, ntfy, clawlight | you | |
| Tailscale node + every sidecar | remote access | `ha-tailscale`, `ntfy-tailscale`, `photos-tailscale`, `albums-tailscale` go with it |

### Keeps working

| What | Why |
|---|---|
| **DNS** | The router hands out `.123, .124`; the Pi's secondary Pi-hole answers. Verify it before relying on it |
| The wol Pi itself | Its own power. Audio (`spotifyd`, white noise) and Node-RED stay up, but anything of theirs that needs MQTT or HA does not |
| Router, extender, ONT | Unless the outage is a power cut |

**DNS without routing is not internet.** The Pi answering queries does not
help if the gateway is down - names resolve to addresses nothing can reach.

## Before shutting down

### First decide: roll the gateway back, or just accept the outage?

**Max Lease Time on the router is 86400s (24h)**, so a device renews at ~12h.
It will **not** pick up a changed gateway before then - every device needs a
Wi-Fi off/on. With ~26 devices routing through xero, that is the whole
decision:

| Outage | Do this | Why |
|---|---|---|
| **Short and planned** (reboot, SSD check, RAM swap - under ~30 min) | **Change nothing on the router. Just shut down.** | Devices keep their `.123` lease and resume on their own the moment xero is back. Zero reconnects. Tell the family it will be down |
| **Long or open-ended** (hours, waiting on a part, something went wrong) | Roll the gateway back first | Worth reconnecting twice to keep the house online |

Rolling it back is the fiddlier path, not the safer one. Reach for it only
when the outage is long enough to matter.

### If you are rolling the gateway back

At `http://192.168.1.1` -> **DHCP Settings**:

| Field | Normal | For the outage |
|---|---|---|
| Gateway Address | `192.168.1.123` | **`192.168.1.1`** |
| DNS1 | `192.168.1.123` | **`192.168.1.124`** (see below) |
| DNS2 | `192.168.1.124` | leave |

**Change DNS1 too.** It points at xero's Pi-hole, so with xero down every
lookup waits for DNS1 to time out before falling to DNS2 on the Pi. It still
works, but everything feels broken. Pointing DNS1 at the Pi for the window
avoids that.

Then **reconnect each device** (Wi-Fi off/on). Put both fields back
afterwards and reconnect again.

Counters are **not** a reason to hesitate either way:
`/run/lan-gateway-bytes.state` restarts at 0 on every reboot anyway, and
Prometheus handles counter resets. No history is lost.

### Then, whichever path

1. **Check nothing is mid-flight** - see the commands below.
2. **Save or close the tmux sessions on xero.** There are usually several
   agent sessions running; a shutdown kills them. `tmux ls`.
3. **Warn anyone watching the public album** if the outage is long.
4. **Take any baseline the work needs** while the machine is still up -
   e.g. `sudo smartctl -A /dev/sda` before moving the SSD. Easy to forget and
   impossible to take afterwards.
5. **Shut down cleanly**: `sudo poweroff`. `datapool` is a single disk with
   no mirror; never cut power to it mid-write.

## Is it safe right now?

```sh
# Disk busy? (anything non-zero on sda means a job is running)
ssh pramod@xero 'iostat -dx sda 1 2 | tail -3'

# Backups, archives, scrub in flight?
ssh pramod@xero 'pgrep -a -f "rclone|archive_to_glacier|backup_|zpool scrub"; zpool status datapool | grep scan'

# Cron coming up (nothing before 02:00 on a normal day)
ssh pramod@xero 'crontab -l | grep -vE "^#|^$"'

# Agent sessions that a shutdown would kill
ssh pramod@xero 'tmux ls'

# Does the secondary Pi-hole actually answer?
ssh pramod@xero 'dig +short +time=2 google.com @192.168.1.124'

# How many devices are routing through xero right now
ssh pramod@xero 'grep -c direction=\"up\" ~/code/homelab/services/node-exporter/textfile/lan_gateway.prom'
```

**Avoid these windows:** the monthly **ZFS scrub, second Wednesday 04:00**
(`tools/zfs/scrub_time.sh`); nightly backups **02:00-04:30**; the Glacier
archive **04:00 on the 1st**.

## After it comes back

1. **Only if you rolled it back:** gateway to `.123` and DNS1 to `.123` on
   the router, then reconnect devices.
2. Confirm the counters are moving again:
   `stat -c %y services/node-exporter/textfile/lan_gateway.prom` (should be
   under a minute old) and `systemctl is-active lan-gateway.service
   lan-gateway-usage.timer`. The service is a **oneshot** - "active" after it
   has loaded the nft table is correct, it does not stay running.
3. `docker ps` - every container up; Immich takes a minute to go healthy.
4. `systemctl --user list-units --state=failed` and
   `systemctl list-units --state=failed`.
5. **The Pi's clock**: if the outage was long, check `timedatectl` on the Pi -
   it has no RTC and depends on xero's chrony.
6. HA: open the dashboard, check no tiles are error cards
   (`projects/ha-dashboard/shot_dashboard.sh`).
7. `ssd-temp-guard` restarts itself (`Restart=always`, enabled) and
   `zfs_vdev_max_active` resets to 1000 on boot, which is the safe direction.
   Nothing to redo.
8. If hardware changed, update `docs/hardware.md` **before** calling the work
   done.

## Traps

- **`projects/lan-gateway/README.md` says "opt-in by design".** Stale as of
  the 2026-10-22 rollout - the router hands `.123` to everyone. Trust this
  file and the `PROJECTS.md` entry over that line.
- **DNS surviving is not the same as the internet surviving.** Checking
  `dig` against the Pi proves nothing about routing.
- **A changed gateway needs a reconnect, not a wait.** The lease is 86400s
  (renew at ~12h), so devices keep the old gateway until Wi-Fi is cycled.
  This is why leaving the router alone is better for a short outage.
- **DNS1 is xero.** With xero down, every lookup stalls on DNS1 before
  falling to the Pi on DNS2. It works, but it feels broken.
- **`datapool` has no mirror.** Clean shutdowns only.
- **The UPS situation**: xero's own mini UPS died 2026-10-08 and the router
  and ONT have none until it is back, so a mains cut takes everything
  anyway - see "xero's UPS (CRU12V3A) dead" in `PROJECTS.md`.
- **OpenWrt is the long-term fix** for xero being the house's single point of
  failure - see the Options in "Per-device network usage monitoring".

## Related

- `projects/lan-gateway/README.md` - the gateway and per-device counters
- `PROJECTS.md` "Per-device network usage monitoring" - the rollout and rollback
- `PROJECTS.md` "Move xero's datapool SSD out of the case" - the move this was first written for
- `docs/hardware.md` (gitignored) - what runs on xero, device by device
- `Readme.md` - bringing xero up, OS and hardware quirks
