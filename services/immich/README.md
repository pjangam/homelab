# Immich

Self-hosted photos at `http://192.168.1.123:2283` (LAN only). The compose
block is the `### photos servers` section of the root `docker-compose.yml`;
the version is pinned in `.env` as `IMMICH_VERSION`.

- Library: `datapool/immich-upload` (`copies=2`; the June 2026 import was
  rewritten with `services/samba/rewrite_for_copies.sh` on 2026-10-09 so it is
  really stored twice). Database: `datapool/immich-db`.
- The library is mounted at `/usr/src/app/upload`, not upstream's newer
  `/data`: the database records that path (`system_metadata.MediaLocation`)
  and every `asset.originalPath` starts with it. Do not "fix" the mount to
  match upstream's compose.
- Video transcoding runs on the N5105's iGPU through **VAAPI** (`/dev/dri`
  passed to `immich_server`; set in Administration -> Settings -> Video
  Transcoding -> Hardware Acceleration). Tested 2026-10-09 inside the
  container: H.264 and VP9 sources to 720p H.264 in about a second per 30s of
  video; Jasper Lake only has the low-power encoder (`EncSliceLP`) and ffmpeg
  picks it by itself. QSV failed (`h264_qsv` error -22) - use VAAPI.
- `immich_machine_learning` is capped at `cpus: 2` so the ML backlog cannot
  pin all four N5105 cores (xero has reached 103°C under full load).

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

2026-10-09: 2.7.5 -> 3.3.1 went through 2.7.5 on the
`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` image first,
because 3.0 dropped pgvecto.rs; the 2.7.5 server migrated the indexes to
VectorChord on its first start. Snapshots `@pre-v3` were taken before it.
