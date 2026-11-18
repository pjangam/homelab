# iPhone → ZFS video uploads via local SMB share
**Status:** Done

**Why:** reclaiming phone storage, which was running low. Immich (the normal ingestion path) is currently disabled, but videos still needed to get off the phone - this is a plain file dump, not photo management.
**Outcome:** a `dperson/samba` container serves a new, separate ZFS dataset (`datapool/phone-uploads`) over SMB; first real batch of 53 videos moved off the phone 2026-07-31. Explicitly a stopgap: it loses the AI features (face/object search, memories, etc.) that Google Photos/Immich provide, so it's not a replacement for Immich re-enablement (the parked Immich entry), just what's usable in the meantime.

#### Setup
- Rejected a Dropbox-relay approach as an unnecessary cloud round-trip since phone and server share the same LAN.
- `datapool/phone-uploads` is deliberately isolated from Immich's managed datasets.
- Credentials pushed into Vaultwarden (not relayed through chat) for retrieval via the Bitwarden mobile app.
- Confirmed the container is healthy and the share config (`valid users = phoneupload`, `read only = No`) is correct; connects from iOS via Files app → Connect to Server → `smb://192.168.1.123`.

#### Log
- 2026-07-31: first real batch - 53 large video files uploaded and moved off the phone, all verified non-corrupt via `ffprobe`.
