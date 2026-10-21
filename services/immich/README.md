# Immich

Self-hosted photos at `http://192.168.1.123:2283` on the LAN, and
`https://photos.<tailnet>/` over Tailscale (the `photos-tailscale` sidecar,
since 2026-10-18; tailnet only, no Funnel). The compose
block is the `### photos servers` section of the root `docker-compose.yml`;
the version is pinned in `.env` as `IMMICH_VERSION`.

- Library: `datapool/immich-upload` (`copies=2`; the June 2026 import was
  rewritten with `services/samba/rewrite_for_copies.sh` on 2026-10-09 so it is
  really stored twice). Database: `datapool/immich-db`.
- The library is mounted at `/usr/src/app/upload`, not upstream's newer
  `/data`: the database records that path (`system_metadata.MediaLocation`)
  and every `asset.originalPath` starts with it. Do not "fix" the mount to
  match upstream's compose.
- External library (2026-10-18): the public album's folder,
  `datapool/albums/ojaswi-1st-birthday`, is mounted read-only at
  `/mnt/albums/ojaswi-1st-birthday` and added under Administration ->
  External Libraries, so Immich and the albums gallery (`services/albums/`)
  share one copy. Favourites, faces and albums live in Immich's DB and work;
  deleting such an asset in Immich never touches the file. Approved family
  uploads land in the same folder and appear on the next library scan.
- Video transcoding runs on the N5105's iGPU through **VAAPI** (`/dev/dri`
  passed to `immich_server`; set in Administration -> Settings -> Video
  Transcoding -> Hardware Acceleration). Tested 2026-10-09 inside the
  container: H.264 and VP9 sources to 720p H.264 in about a second per 30s of
  video; Jasper Lake only has the low-power encoder (`EncSliceLP`) and ffmpeg
  picks it by itself. QSV failed (`h264_qsv` error -22) - use VAAPI.
- `immich_machine_learning` is capped at `cpus: 1` so the ML backlog cannot
  pin all four N5105 cores (xero has reached 103°C under full load). It was
  `cpus: 2` until 2026-10-16, when face detection on a 37-photo upload still
  took xero to 89°C; one core halves ML throughput (about 10 minutes for a
  batch that size).

## Load guard

`load_guard.sh`, run by the systemd --user unit `immich-load-guard.service`
(installed copy in `~/.config/systemd/user/`), stops every `immich_*`
container if xero holds `x86_pkg_temp` >= 93°C for a minute, has under 1.5GB
available memory for a minute, or sits at >= 95% CPU for 10 minutes. It sends
an urgent ntfy push and keeps Immich stopped, across reboots, until re-armed:

    services/immich/load_guard.sh --reset && docker compose up -d

Watch it with `journalctl --user -u immich-load-guard -f`. `test_load_guard.sh`
runs it against fake readings and a fake docker.

## Upgrading

Never go back to `IMMICH_VERSION=release`: a floating tag pulled 3.x over a
2.x database once a plain pull happened. Read the release notes, change the
pin, and compare the compose file and `example.env` at the old and new tags
(`gh api 'repos/immich-app/immich/contents/docker/docker-compose.yml?ref=vX.Y.Z'`).
Snapshot first, with Immich stopped:

    sudo zfs snapshot datapool/immich-db@<name> datapool/immich-upload@<name>

`upgrade.sh vX.Y.Z` does the stop, snapshot (`@pre-vX.Y.Z`), `.env` change
and restart in one go; run it from a real terminal for the sudo prompt.

2026-10-09: 2.7.5 -> 3.3.1 went through 2.7.5 on the
`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` image first,
because 3.0 dropped pgvecto.rs; the 2.7.5 server migrated the indexes to
VectorChord on its first start. Snapshots `@pre-v3` were taken before it.

2026-10-21: 3.3.1 -> 3.3.4 with `upgrade.sh` (snapshots `@pre-v3.3.4`). No
compose or `example.env` changes; one migration, `AddAssetFaceAssetState`
(denormalised owner/visibility columns on `asset_face`), ran in about a second.

**v3 needs video metadata re-extracted.** 3.x stores video stream details in
a new `asset_video` table, filled by metadata extraction. Videos extracted
under 2.x have `asset_job_status."metadataExtractedAt"` set but no
`asset_video` row, so Extract Metadata -> Missing skips them, and thumbnail
generation ("Missing video metadata") and transcoding skip them too - VP9
videos then do not play on iPhones. Fixed 2026-10-12 for 953 videos by
clearing `metadataExtractedAt` for videos with no `asset_video` row, then
Extract Metadata -> Missing, Generate Thumbnails -> Missing, Transcode
Videos -> Missing.

## Importing a Google Takeout export

`takeout_download.sh` downloads the zips straight to xero instead of through a
browser, because Google allows 5 download attempts per part and the 2026-06
admin export lost part 019 to broken browser downloads
(`docs/google_takeout_missing.md`). It asks Takeout for each part once, resumes
against the signed storage URL it gets back, tests every zip with `unzip -tq`,
skips parts already done, and logs each Takeout request to
`takeout-asks.log`. Usage and inputs are in the script's header;
`test_takeout_download.sh` runs it against a fake Takeout.

When exporting, pick **.zip** and the **50GB** part size: fewer parts means
fewer links to go wrong, and resume makes a big part safe. Download into
`/datapool/google-takeout/<user>/`, then import with immich-go
(`~/bin/immich-go`) using an API key made by **that** user, so the photos land
in their library and not admin's.
