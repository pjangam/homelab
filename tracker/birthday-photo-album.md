# Public photo album for Ojaswi's 1st birthday (Tailscale Funnel)
**Status:** Done

**Why:** a public album for Ojaswi's 1st birthday, viewable without Tailscale.
**Outcome:** live since 2026-09-29 at `https://albums.<tailnet>/<secret>/` (secret: `OJASWI_ALBUM_PATH` in `.env`), with review-first family uploads added the same day. Left open: retire the public gallery once family stop opening it (the photos are in Immich as an external library since 2026-10-18; an Immich shared link was decided against, see Log).

#### Setup

`albums-gallery` (copyparty, read-only and hardened, ~40MB) behind the `albums-tailscale` sidecar with Funnel, serving `datapool/albums/ojaswi-1st-birthday` (copies=2); uploads go in through the new `albums` SMB share. Funnel is granted only to `tag:funnel` in the tailnet policy. Only the secret path is routed - copyparty's own `/?tree` would list volumes. `services/albums/check_public.sh` verified it over public DNS: album, thumbnails, and 404/401/403 for everything else. Setup gotchas (untagged auth key, restart after the grant): `services/albums/README.md`.

#### Family uploads

Review-first - per-person logins (`uploader.sh`) can only add photos/videos to a hidden inbox, hooks refuse non-media by extension and by content, and `review.sh approve` moves them into `from-family/`. `check_uploads.sh` passes 15/15 over the public route; the gallery is on an internal-only docker network.

#### Log
- 2026-09-29: album live over Funnel; family uploads (review-first) added.
- 2026-10-18: the album folder is also an Immich external library (read-only mount, one copy; `services/immich/README.md`), for faces, favourites and an Immich album. The public copyparty link stays: moving it to an Immich shared link would mean putting all of Immich on Funnel, a far bigger exposure than one read-only folder. Retire the gallery once family stop opening it.
