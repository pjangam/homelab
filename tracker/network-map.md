# Network device + access map
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** export the router DHCP table (router admin page)
- [ ] **Claude:** diff it and the Pi-hole client list against `docs/hardware.md`, extend the file with the access columns below

**Why:** there is no single place that answers "what is on the network, and what can each thing reach or be reached by". Those facts are spread across `docker-compose.yml`, Readme, Pi-hole, the router, and past PROJECTS.md entries. The map is the answer to reach for when a device misbehaves, when something new joins the LAN, or when deciding whether a change widens exposure.
**State:** partly done, and deliberately kept out of git.
- **`docs/hardware.md` exists (2026-08-25) but is gitignored.** It was held back from the public repo on 2026-08-26 (commit `b40a457`) pending `docs/security_findings_2026-08-25.md`, also gitignored. The file adds no new individual facts, but collecting already-public ones in one place makes them easier to use. That review never concluded, so the hold still stands.
- **It is a hardware inventory, not an access map.** It covers the three managed devices (xero, the wol-sender Pi, the iPhone) with specs and services, and nothing about access.
- **It is also three weeks stale.** It predates the MacBook's role in clawlight, the ntfy and HA tailnet sidecars going live, clawlight itself, and Node-RED's watchdog being re-enabled.
- **Unmanaged devices are missing entirely.** The router, the WiFi extender, both Tinxy units, the MirAIe AC, the Tinxy valve, and anything else that got a DHCP lease are not listed.

#### What the map should add on top of the inventory, per device
- **Address:** LAN IP, static or DHCP reservation, tailnet name if any.
- **Inbound:** listening ports, reachable from where (localhost / LAN / tailnet / internet), and what auth guards each one.
- **Outbound:** which cloud it depends on (Tinxy cloud, MirAIe cloud, the ntfy.sh APNs relay, Dropbox for backups). This is also the "what breaks in an ISP outage" list.
- **Credentials:** where they live, as a *pointer* to the Vaultwarden item, never the secret.

#### Method
**Build it from the network, not from memory.** Seed the list from the router's DHCP table and Pi-hole's client list, and check exposure with a port scan from a LAN client and from a tailnet-only client. The documented view and the real one are what should be compared. A device nobody remembers adding is the most useful thing this could find.

#### Keep it gitignored
Extend `docs/hardware.md` (or a sibling `docs/network_map.md` with a gitignore line) rather than committing it. Listing which admin panels still lack auth (finding #2 in the security review) is precisely what should not be in a public repo. Revisit only if the repo goes private or finding #2 gets fixed.

#### Log
- 2026-08-25: `docs/hardware.md` written.
- 2026-08-26: `docs/hardware.md` held back from the public repo (commit `b40a457`) pending the security review.
- 2026-09-15: noted.
