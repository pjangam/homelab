# Public photo albums (Tailscale Funnel + copyparty)

A way to share an album with family who do not have Tailscale, while Immich
is parked on RAM. First album: Ojaswi's 1st birthday.

```
phone/laptop --SMB--> samba "albums" share --> /datapool/albums/ojaswi-1st-birthday
                                                       | (mounted :ro)
browser --https--> albums.<tailnet>.ts.net/<secret>/ --> albums-tailscale (Funnel) --> albums-gallery (copyparty)
```

## Pieces

| | |
|---|---|
| **Storage** | ZFS dataset `datapool/albums`, `copies=2`, `sync=always`, compression on. Same single-disk caveats as `phone-uploads` (see `services/samba/README.md`, Durability): two copies on one SSD, no snapshots, no offsite copy. The originals should also live somewhere else. |
| **Upload** | SMB share `albums` (same `phoneupload` login as `phone-uploads`), read-write. Drop files into `ojaswi-1st-birthday/`. |
| **Gallery** | `albums-gallery` container (copyparty), grid view, thumbnails incl. video, "download all" zip. Read-only for viewers, album mounted `:ro`; the only writable path is the upload inbox (see Family uploads). Non-root, read-only rootfs, cache in tmpfs (thumbnails regenerate after a restart). No published port. Network-isolated: only on the `internal` network `albums-internal`, so it cannot reach the LAN, the internet or other containers (verified 2026-09-29: HA, ntfy, vaultwarden, 1.1.1.1 all blocked). |
| **Public URL** | `albums-tailscale` sidecar, Funnel on, on `albums-internal` + its own `albums-egress` (not the default network). Only `/<secret>/` is routed; everything else is a Tailscale 404. |
| **Secret** | `OJASWI_ALBUM_PATH` in `.env`. The rendered `services/tailscale/albums/serve-config.json` contains it and is gitignored. |

New files show up on refresh; there is no regenerate step.

## Family uploads (review-first, since 2026-09-29)

Relatives with a login can add photos from their phone at
`https://albums.<tailnet>/<secret>/upload/` (log in with the password alone,
then pick photos; uploads are chunked and resumable). Nothing they send is
visible to anyone until approved.

| | |
|---|---|
| **Logins** | `services/albums/uploader.sh add <name>` prints the upload link + password; `remove <name>` revokes one person; `list`. Stored in the gitignored `accounts.conf` (included by `copyparty.conf`). |
| **Inbox** | `/datapool/albums/_inbox/ojaswi-1st-birthday` (same dataset, copies=2). Uploaders can only add: no listing, reading, deleting or overwriting (a clashing name is saved under a new name). Viewers never see it. Also visible over SMB as `albums/_inbox/`. |
| **Review** | `services/albums/review.sh list` (with who sent what), `approve <file>... / --all` (moves into the album's `from-family/`), `reject <file>...`. |
| **Refused** | anything not jpg/jpeg/png/heic/heif/webp/gif/mov/mp4/m4v/3gp (`hooks/pre_upload.py`); anything whose first bytes are not a real photo/video container, deleted after upload (`hooks/post_upload.py`); files under 1 KiB or over 4 GiB; uploads once datapool has under 50G free; more than 30G/day or 500 files/hour from one IP. |
| **Log** | `_inbox/.upload-log.tsv`: time, login, client IP, file, size, ok/REJECTED. |
| **No thumbnails in the inbox** | untrusted files are never decoded until approved. |
| **Brute force** | copyparty bans an IP after 9 wrong passwords in an hour. It sees real client IPs (X-Forwarded-For from the sidecar, trusted only from the private network), so a ban hits the guesser, not the whole family. |

Tests: `services/albums/check_uploads.sh` (throwaway login, 15 checks over the
public route, cleans up after itself). Also verified once by hand with
copyparty's own up2k client (`u2c.py`, the protocol the phone's browser uses):
real photo accepted, fake rejected, approve made it public. Note u2c retries a
rejected file forever - the log then shows the same REJECTED line repeating.

## Privacy model

It is an unguessable link, like a Google Photos share link: anyone who has it
can view and download, and nobody else can find it. `albums.<tailnet>.ts.net`
itself is public (CT logs), which is why the path is the secret, not the
hostname. Copyparty must never be reachable at its own `/` - its `/?tree`
lists the mounted volumes - which is why Tailscale routes the one path only.

To revoke or rotate: change `OJASWI_ALBUM_PATH` in `.env`, then
`services/albums/render_serve_config.sh && docker compose up -d albums-gallery albums-tailscale`.
To take it offline: `docker compose stop albums-tailscale`.

## One-time setup

1. Dataset (needs sudo, from a real terminal):
   `sudo zfs create -o copies=2 -o sync=always -o compression=lz4 datapool/albums && sudo install -d -o pramod -g pramod /datapool/albums/ojaswi-1st-birthday && sudo chown pramod: /datapool/albums`
2. Tailnet policy: `tagOwners` `"tag:funnel": ["autogroup:admin"]` and `nodeAttrs` `{"target": ["tag:funnel"], "attr": ["funnel"]}`.
3. Auth key from the admin console (Settings -> Keys), tagged `tag:funnel`, into `TS_AUTHKEY_ALBUMS` in `.env`.
4. `services/albums/render_serve_config.sh && docker compose up -d albums-gallery albums-tailscale samba`
5. `services/albums/check_public.sh` - resolves via public DNS and goes through
   the Funnel relays; checks the album works and that /, `/?tree`, uploads and
   deletes are refused.

What actually happened on 2026-09-29, for next time:

- **Funnel is granted by tag, not to every device.** The tailnet policy has
  `tagOwners` `tag:funnel` (autogroup:admin) and `nodeAttrs`
  `{"target": ["tag:funnel"], "attr": ["funnel"]}`, so only the `albums` node
  can be public. The auth key came out untagged anyway; tagging the machine in
  the admin console (Machines -> albums -> Edit ACL tags) fixed it live.
- **"Funnel on" in `tailscale funnel status` proves nothing.** It shows the
  config, not the grant. Check the node has the capability:
  `docker exec albums-tailscale tailscale status --json` -> `Self.CapMap` must
  contain `funnel`.
- **After granting it, restart the sidecar.** It had announced ingress before
  it held the capability, and no public DNS record appeared until
  `docker compose restart albums-tailscale`; then it resolved within seconds.

## Upload bandwidth

Home upload is slow, so every viewer pulls full-size originals through it.
Fine for a few relatives; for a big video-heavy album, consider uploading
phone-exported (reduced) copies rather than originals.

## Adding another album

Each album is its own copyparty instance + secret (a shared instance would
let one link list every album). Copy the two services with a new name,
secret and handler, or generalise the script when there is a second one.
