# Syncthing - offline copies of `documents` on every device

Replaces Dropbox for sensitive personal documents (IDs, tax papers). Every
paired device keeps a **full local copy** that works offline, and catches up
whenever it comes online. xero is the always-on peer, so two devices that are
never online at the same time still converge through it. No cloud is involved
and there is no storage cap. Why it was picked over the alternatives:
`PROJECTS.md`, "Peer-to-peer sensitive document sync (Syncthing)".

## Basics

| | |
|---|---|
| **Host** | xero |
| **Container** | `syncthing` (`syncthing/syncthing:2.1.7`, pinned), `docker-compose.yml`, `network_mode: host` |
| **Synced folder** | ID `documents`, label "Documents" = `/datapool/documents` (`DOCUMENTS_LOCATION`), the **same files** as the `documents` SMB share ([`services/samba`](../samba/README.md)) |
| **Config + device keys** | named volume `homelab_syncthing-config` (`/var/syncthing/config`) |
| **GUI** | `https://xero.<tailnet>/syncthing/`, through Caddy to `127.0.0.1:8384` |
| **GUI login** | `pramod` / `SYNCTHING_GUI_PASSWORD` in `.env` (and Vaultwarden) |
| **Sync ports** | 22000 TCP + QUIC/UDP; LAN discovery on UDP 21027. Every interface, LAN and tailnet |
| **Internet exposure** | none: global discovery, relays, UPnP and STUN are off, and the router forwards nothing |
| **xero's device ID** | `HLA4HKO-44G357L-FPDXG7B-Y6STXV2-HRR5GAB-GA7LB6N-A2XOJBE-JK3LOQ7` |
| **Versioning** | staggered, 90 days, on xero only, in `/datapool/documents/.stversions/` |
| **Off-site backup** | unchanged: [`backup_documents.sh`](../../projects/certs-backup/README.md) (gpg tar to Dropbox), which skips `.stversions/` |

## Files

| file | what |
|---|---|
| `configure.sh` | puts xero's Syncthing into the settled config (options, GUI login, the folder, `.stignore`). Idempotent. |

## Setup / after a change

1. `docker compose up -d syncthing`
2. `./services/syncthing/configure.sh`. It prints the device ID.

Re-run step 2 after a rebuild, an image upgrade, or if a GUI click turned discovery or relays back on.

## Adding a device

Each device pairs with xero only, not with the other devices. xero passes changes on.

1. **Install the client:**

   | device | client |
   |---|---|
   | Mac | `brew install syncthing && brew services start syncthing`, GUI at `http://127.0.0.1:8384` |
   | iPhone | **Synctrain** (free, App Store). It only syncs while open, so open it to catch up |
   | Windows / Linux | official Syncthing from syncthing.net/downloads |
   | Android | **Syncthing-Fork** (F-Droid / Play) |

2. **On the client:** Settings → Connections: untick *Global Discovery*, *Enable Relaying* and *Enable NAT traversal*.
3. **On the client:** Add Remote Device with xero's ID (table above). Leave Addresses on `dynamic` (the field is easy to miss; on the LAN, local discovery finds xero anyway).
4. **On xero:** accept the device and share **Documents** with it. Set *its* addresses on xero's side to `dynamic, tcp://<device's tailnet name>.<tailnet>:22000` (`tailscale status` lists the name), so xero can dial it when it is away from home. One side knowing the other's address is enough.
5. **On the client:** accept the Documents share and pick a local path. On a Mac use `~/xero-documents`, never under `~/Documents` or `~/Desktop`: iCloud / OneDrive / company backup often sync those. The first sync copies the full share (~450 MB).
   - **Synctrain (iPhone) never showed the offer.** Instead: Folders → Add → **Regular** → Folder ID `documents` (exact), share with xero, keep all files. Matching IDs join the share straight away.
   - Synctrain's settings are named differently: turn off *Announce globally*, *Enable relaying*, *Enable NAT-PMP/UPnP* and *Enable STUN*; leave *Announce on local network* and *Announce LAN addresses* on.
6. **On the client:** Documents → Edit → *Ignore Patterns*: paste the same list as xero's `.stignore` (in `configure.sh`). Ignores are per device, so without it the client offers its own `.DS_Store` and junk to everyone else.
7. Check that both GUIs show the device as **Connected** and the folder as **Up to Date**.

## Paired devices

| name on xero | device | tailnet name | local path | since |
|---|---|---|---|---|
| `work-m1` | employer M1 MacBook Pro | `sonalis-macbook-pro` | `~/xero-documents` | 2026-11-10 |
| `iphone-14` | iPhone 14 (Synctrain) | `iphone-14` | Synctrain regular folder | 2026-11-10 |

## Traps

- **Not a backup.** A delete or overwrite on any device syncs everywhere.
  - Recover through xero's GUI → Documents → *Versions* (kept 90 days).
  - The Dropbox gpg archive is the copy of last resort.
- **`configure.sh` once un-shared Documents from every device** (2026-11-10). Changing GUI settings restarts Syncthing's API; the next read failed mid-restart, and a `|| echo []` fallback saved an empty device list. It now waits for the API and aborts on any read failure but 404. If devices show "Disconnected / unshared" after a run, check *Share With* on the folder first.
- **A fresh config volume is root-owned.** Syncthing runs as uid 1000 and fails with `Failed to acquire lock ... permission denied`. `configure.sh` chowns the volume.
- **GUI host check is off** (`insecureSkipHostcheck`). Caddy sends `Host: xero.<tailnet>`, which the GUI would otherwise reject. This is safe only because the GUI listens on 127.0.0.1. Never publish 8384.
- **SMB and Syncthing write the same files.** The file watcher picks up SMB changes within about 10s. If two devices edit the same file offline, Syncthing keeps both, as `*.sync-conflict-*`.
- **`.stignore` is generated.** `configure.sh` rewrites it, so edit it there. It drops `.DS_Store`, `._*`, `Thumbs.db`, `desktop.ini` and Samba's recycle bin `/.deleted` (keeps SMB-deleted files on xero only; it leaked to the first device before this was added).
- **Away from home a device needs Tailscale on**, since there are no relays. The iPhone's tunnel can die silently without showing an error. If Synctrain stays "Disconnected", toggle Tailscale.
- **Work laptop:** installing a sync client there may be visible to the employer's policy tooling. This is the same worry that kept Dropbox off it. Decide before installing (`PROJECTS.md` open question).
