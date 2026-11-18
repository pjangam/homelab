# Minecraft server on xero (family world, local and over Tailscale)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹0
**Effort:** ~2 evenings (4-6h)

#### Open items
- [ ] **Pramod:** list who will play and on which devices (PC Java, PC Bedrock, phone/tablet, Xbox/Switch/PlayStation) - that picks the server software
- [ ] **Claude:** then the build, about an evening's work

**Why:** user, 2026-11-02: "add new project minecraft server". Nothing else was given: no edition, no list of players or devices, no host. The point of a server over a world on one player's device is that the world is always there (no host device needs to be on) and can be joined from outside the house over Tailscale.
**State:** idea only, researched 2026-11-02. Nothing is decided. The first decision is which edition the players use, and that comes from what devices they play on (see Open questions).

#### Feasibility
Yes, this is a common build, and xero has the headroom for a small family server. Checked 2026-11-02: 31GB total, ~18GB available (`free -m`), load average ~0.8 on 4 cores. **The bad-RAM rule no longer blocks it:** the failing 8GB stick was replaced by the 32GB one on 2026-10-09 and passed memtester (see "Check if server RAM is expandable"). The constraints that remain are heat and the CPU's speed:
- **CPU:** the N5105 is 4 slow cores (2.0GHz, 2.9GHz burst). A Minecraft server's game loop runs on one core, so what matters is single-core speed, not core count. 2-4 players at view distance 6-8 is fine. **What costs the most is generating new terrain** (exploring with an elytra, or several players heading off in different directions). To avoid it, pre-generate a fixed area once, on a cool night, with the Chunky plugin on Paper (or by walking the area on Bedrock), and set a world border so play never needs new terrain.
- **Heat:** a sustained full-core load on the pegboard reached 92-95°C on 2026-10-08. Long play sessions in summer depend on "xero cooling on the Skadis pegboard" (P2, due before Feb 2027). Before then, play is fine in winter; pre-generation should run only in winter. Immich's `load_guard.sh` stops only `immich_*` containers when xero gets hot, so a heavy Immich job and a play session will compete for CPU. Do not pre-generate while an Immich job is running.
- **Disk:** autosaves are small writes every few minutes, not the long bulk I/O that overheats the Kingston SSD.

#### Design
- **Edition decides everything.** Java (PC only) and Bedrock (phones, tablets, consoles, Windows) cannot play together natively. A family with a child usually means Bedrock on a tablet or console.
  - **Everyone on Bedrock, nobody on Java PC: run Bedrock Dedicated Server** (`itzg/minecraft-bedrock-server`, UDP 19132). It is Mojang's own server, so every Bedrock feature works, and it uses ~0.5-1GB of RAM. Recommended in that case. It has no plugins, so there is no Chunky.
  - **Any Java player: run Paper with Geyser + Floodgate** (`itzg/minecraft-server`, `TYPE=PAPER`, TCP 25565 for Java and UDP 19132 for Bedrock, through Geyser). Both editions share one world. Floodgate lets Bedrock players join with only their Microsoft account; without it, every Bedrock player also needs a paid Java account ([Geyser + Floodgate](https://xgamingserver.com/docs/minecraft/setup-geyser-floodgate)). The downside is that Geyser only translates between editions, so some Bedrock behaviour is missing or different (some redstone, combat and UI details). Give it `MEMORY=3G` and a container memory limit of ~4G; the image defaults to 1G ([JVM options](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/jvm-options/)).
- **Image:** the itzg images ([docs](https://docker-minecraft-server.readthedocs.io/en/latest/)) are the standard choice. Configuration is entirely environment variables, set as a service in the root `docker-compose.yml`, with `EULA=TRUE`, `restart: unless-stopped` and the version pinned (watchtower must not upgrade the world in the middle of a season; pin and upgrade on purpose after a backup).
- **Idle cost:** recent Java servers pause the game when nobody is on (`PAUSE_WHEN_EMPTY_SECONDS`, 1.21.2+). The image's older `ENABLE_AUTOPAUSE` is no longer recommended ([autopause](https://docker-minecraft-server.readthedocs.io/en/latest/misc/autopause-autostop/autopause/)). Measure the idle CPU and RAM after the build.
- **World data:** in a new dataset, `datapool/minecraft`, mounted at `/data`. Do not put it on the 128GB boot SSD, which is already tight. Use `copies=2`, like the other datasets: a world is a few GB at most, so the extra copy costs nothing.
- **Backups:** a world corrupted by a crash or by a griefing child is the likely failure. Do three things: a ZFS snapshot hourly while the server is running; a nightly archive, gpg-encrypted with `BACKUP_PASSPHRASE` and sent to Dropbox the same way as `projects/certs-backup/backup_vaultwarden.sh`, with a healthcheck heartbeat; and save-off/save-on around each copy (the `itzg/mc-backup` sidecar does this) so the copy is never taken mid-write.
- **Remote play:** over Tailscale only, never a router port-forward. PCs and phones run the Tailscale app and add the server as `xero.{tailnet}` or its 100.x address. **Consoles cannot run Tailscale, and console Bedrock has no "add server" button**, so consoles join only on the LAN. Even there, a dedicated server needs a workaround: BedrockConnect, a DNS redirect that the house Pi-hole could serve, or the MCXboxBroadcast Geyser extension ([Geyser on consoles](https://wiki.geysermc.org/geyser/using-geyser-with-consoles)). Build that only if a console is actually in the list.
- **Power:** xero is on the router's mini UPS, and the watchdog shuts it down cleanly after 10 minutes of outage (see "xero's UPS (CRU12V3A) dead"). A clean shutdown stops the container, which saves the world. A crash loses up to one autosave interval, and the snapshots cover that.
- **Never lie about state:** if it reports anywhere (HA, the endpoint page), it shows "unknown" when unreachable. Optional: `itzg/mc-monitor` exports Prometheus metrics. Graph the p95 and max tick time (MSPT), never the average.
- **Rejected: the wol Pi.** A Pi 3B with 1GB of RAM, a microSD card and mains-only power. Paper needs about 2GB of heap. Bedrock Dedicated Server is built for x86_64 only. Constant world writes would wear out the SD card. Every power cut kills it.
- **Rejected: a spare laptop.** `docs/hardware.md` keeps them for jobs with an end date, not 24/7 services (10-20W each, plus another machine to patch).

#### Readymade alternatives
- **Built-in LAN world (free):** on Bedrock, one device hosts and the others on the same Wi-Fi join from the Friends tab. It needs nothing built, and consoles join natively. It is limited to the host being on and to players at home. **If everyone plays together in the house, this may be enough, and the project can close.**
- **Realms (Mojang's hosted server, monthly fee, price not checked for India):** always on, consoles join natively, backups included. It is the honest competitor if consoles are involved. It costs a subscription and is not local-first, but nothing on xero depends on it.
- **Paid hosts:** cheap, but they add nothing over xero except freedom from power cuts.

```parts
qty | item | est | note
0 | server hardware | 0 | runs on xero; nothing to buy
1 | Minecraft licence per player without one | 465-2250 | estimate, not a fetched listing: Bedrock mobile ~600-700, Java+Bedrock PC bundle quoted 465-2250 by unreliable sources (2026-11-02); check the Play Store / Microsoft Store India price
```

**Cost detail:** ₹0 for the server. Licences are only for players who do not already own the game.
**Effort detail:** ~4-6h.
1. Decide the edition from the device list (0.5h; this decides the rest).
2. Compose service, dataset and first world (1h).
3. Backups: snapshots, the Dropbox job and the heartbeat (1-1.5h).
4. Client connections: Tailscale on each phone or PC, and a console workaround if needed (1-2h). **This is the phase that overruns:** each family device is its own setup, and consoles are the unknown.
5. Pre-generate the world (unattended; on a winter night).

**Done when:** the service is in `docker-compose.yml` with its version pinned; the first backup has been restored once into a scratch container; `projects/endpoints/endpoints.toml` lists it (Java TCP 25565 and/or Bedrock UDP 19132 on `xero.{tailnet}`) and has been re-rendered; xero's entry in `docs/hardware.md` lists the container and dataset (gitignored, never committed); and `tools/repo-tools/check_endpoints_toml.sh` and `check_hardware_md.sh` are clean.

#### Open questions (for the user)
- Who plays, and on what devices? Is the child old enough to play, or is this for an older relative or friends? Does anyone play Java on a PC?
- Is there a console (Switch, Xbox, PlayStation)? If yes, compare Realms seriously.
- Does anyone play from outside the house, or is the built-in LAN world enough?
- Survival or creative? Is griefing protection (whitelist, rollback) needed?
- Do the players already own the game?

#### Log
- 2026-11-02: idea recorded and researched. No overlap with existing entries, apart from depending on xero's cooling (summer sessions) and on its UPS.
