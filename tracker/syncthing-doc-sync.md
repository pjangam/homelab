# Peer-to-peer sensitive document sync (Syncthing) - Dropbox replacement
**Status:** Active
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Together:** pair the 2019 MacBook (`services/syncthing/README.md`, "Adding a device")
- [ ] **Pramod:** decide whether Bhakti's phone keeps Tailscale on (needed to sync away from home)
- [ ] **Claude:** add Syncthing to `healthcheck.sh` (container up, Documents folder not in error)

**Why:** currently uses Dropbox to keep sensitive personal documents (ID cards, tax documents, etc.) available across devices.

Problems with that:
- Cloud storage is a leak risk for this class of document.
- Has a storage limit.
- Needs internet connectivity.
- The work laptop specifically avoids Dropbox's offline-files feature out of concern the employer could flag/ban Dropbox on a work machine - meaning that device currently has no reliable access at all.

This is a distinct need from the iPhone-upload SMB share (Done section) - continuous, automatic, always-available-everywhere sync, not a manual one-off drop zone.
**State (2026-11-10):** xero side is up: container `syncthing` on `datapool/documents`, GUI at `https://xero.<tailnet>/syncthing/`. Paired: the work M1, the iPhone 14, Bhakti's OnePlus 7. Still to pair: the 2019 MacBook. Details in `services/syncthing/README.md`.

#### Decisions (user, 2026-11-10)
- **Devices:** xero (always-on peer), the 2019 MacBook, the iPhone, Bhakti's devices, the work laptop - all get the full copy.
- **Scope:** the whole `documents` share as one folder, `Bhakti/` included.
- **Network:** LAN + tailnet. No global discovery, relays or UPnP, so nothing reachable from the internet.
- **Work laptop (2026-11-10):** gets a full Syncthing client after all - user accepted the policy-visibility risk. Settles the Open question below.
- **Versioning:** staggered, 90 days, on xero only; the Dropbox gpg archive skips `.stversions/`.

**Background:** Syncthing identified as the right fit - true peer-to-peer, no cloud storage or third-party leak surface, no storage cap, works over LAN and (via Tailscale) when away from home. Homelab server would act as an always-on peer so devices stay in sync even when not simultaneously online.
**Requirement (user, 2026-10-30):** files readily available on every device **even when it is offline**, and devices sync whenever they come online. That is Syncthing's model (a full local copy on each device) and rules out on-demand access as the main path.

#### Options compared (2026-10-30)
- **Syncthing - chosen, meets the requirement.** Full copy per device, peer-to-peer, no cloud, no cap; xero as the always-on peer so devices that are never online together still converge. iPhone: no official app - **Synctrain** (free, open source) or **Möbius Sync** (paid); both keep real local files, but iOS only syncs while the app is open or in short background windows, so open it to catch up. Not a backup: a deletion syncs everywhere - keep the existing gpg Dropbox backup of `documents` (`projects/certs-backup/backup_documents.sh`), and turn on Syncthing's file versioning on xero's copy.
- **Seafile / Nextcloud on xero** - server-centric; offline only for files pinned in the apps. Web UI would suit the work laptop. Heavier (Nextcloud especially); not needed if Syncthing covers it.
- **Vaultwarden attachments** - works (free in Vaultwarden, end-to-end encrypted, web vault for the work laptop) but **attachments are fetched on demand, not cached offline**, so it fails the requirement; only the typed text of a note is offline. Also `backup_vaultwarden.sh` keeps 7 full copies of `vw-data` in Dropbox (2.75GiB free), so attachments multiply there. At most for a few ID scans, with the key numbers typed into the note.
- **SMB share over Tailscale / a read-only web file browser** - no offline copies; only as a no-install fallback for the work laptop.
- **Dropbox + Cryptomator** - fixes the leak risk only; still capped and cloud-dependent.

#### Open question
How the work laptop fits in - same policy-visibility risk that ruled out Dropbox offline-files there could apply to installing any sync client. Not yet decided whether that machine gets a full Syncthing client, browser/web-GUI-only access, no access at all, or gets figured out later. Scope for phone + personal devices + homelab server first.

#### Log
- 2026-10-30: Parked -> Active so it stays visible (user: to work on in the near future, after the Diwali lights).
- 2026-11-10: Syncthing 2.1.7 running on xero (`services/syncthing/`), configured by `configure.sh`; Caddy route `/syncthing/`; endpoints and `docs/hardware.md` updated; `backup_documents.sh` now skips `.stversions/`.
- 2026-11-10: work M1 paired as `work-m1` (`~/xero-documents`, 224 files, 257 MiB). Test passed: file made on the Mac reached xero, its delete was kept in xero's Versions, restore from xero brought it back to the Mac. Samba's `.deleted/` recycle bin had synced to the Mac; now in `.stignore`.
- 2026-11-10: iPhone 14 paired as `iphone-14` via Synctrain (folder created by hand with ID `documents`; the share offer never showed). STUN off on xero too. Bug found and fixed: a `configure.sh` re-run had un-shared Documents from all devices (API restarting after the GUI patch, empty-list fallback); it now waits and aborts instead.
- 2026-11-10: GUI password copied into Vaultwarden (user).
- 2026-11-10: Bhakti's OnePlus 7 (Android, Syncthing-Fork) paired as `bhakti-oneplus-7`, folder created by hand; full sync in under a minute on Wi-Fi.
