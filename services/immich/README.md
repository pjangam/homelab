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
- `immich_machine_learning` is capped at `cpus: 2` so the ML backlog cannot
  pin all four N5105 cores (xero has reached 103°C under full load). It was
  `cpus: 1` from 2026-10-16, when face detection on a 37-photo upload took
  xero to 89°C, to 2026-10-30, when the throttled backlog run held 70-74°C on
  one core and went back to two for speed.
- **Integrity checks run at 03:00 IST and checksum 15% of the library a
  night** (set 2026-10-28; Administration -> Settings -> Integrity, stored in
  `system_metadata.system-config`). v3's default is `0 3 * * *` in the
  container's clock, which is UTC (no `TZ` on `immich_server`), i.e. 08:30 IST,
  and a checksum of 100% of the assets: an ~80GB read at ~190MB/s for 8
  minutes that took the Kingston to 75°C every morning. Now all three jobs
  (missing, untracked, checksum) are `30 21 * * *` UTC and the checksum
  `percentageLimit` is 0.15. It resumes from a checkpoint, so the whole
  library is still covered about once a week, in ~1-minute bursts.

## Load guard

`load_guard.sh`, run by the systemd --user unit `immich-load-guard.service`
(installed copy in `~/.config/systemd/user/`), stops every `immich_*`
container if xero holds `x86_pkg_temp` >= 93°C for a minute, has under 1.5GB
available memory for a minute, or sits at >= 95% CPU for 10 minutes. It sends
an urgent ntfy push and keeps Immich stopped, across reboots, until re-armed:

    services/immich/load_guard.sh --reset && docker compose up -d

Watch it with `journalctl --user -u immich-load-guard -f`. `test_load_guard.sh`
runs it against fake readings and a fake docker.

## ML backlog

Immich runs face detection and smart search on new uploads by itself, but
assets that were already there need the "Missing" jobs queued by hand.
`ml_backlog.sh` does that with the load kept down: concurrency 2, 20-minute
batches with 10-minute rests, and a pause whenever `x86_pkg_temp` >= 85°C or
the Kingston >= 70°C (its rating), until both are back under 70°C / 62°C. Face detection
first, then smart search. Run it detached:

    systemd-run --user --unit immich-ml-backlog services/immich/ml_backlog.sh
    journalctl --user -u immich-ml-backlog -f

Remote ML on the 2019 MacBook clears it several times faster. On the Mac, from
its clone of this repo (needs Docker Desktop or OrbStack; the version must
match xero's):

    services/immich/remote_ml_mac.sh v3.3.5    # starts the container, keeps the Mac awake

then on xero `services/immich/remote_ml.sh on` (Mac first, xero's own ML as the
fallback, concurrency 6), `status` to check, and `off` plus
`remote_ml_mac.sh stop` when done.

First run, 2026-10-30: ~270 assets/min face detection and ~620/min smart search
on the Mac, against ~21/min on xero's 2 cores; the Kingston's 70°C pause was
the only limit. Two lessons:
- **Check the Mac's link first.** Through the TP-Link extender it did ~250KB/s
  even on the LAN, which caps remote ML near one asset a second whatever the
  CPU. On the router directly (its 2.4GHz SSID; the 5GHz one gives xero no LAN
  access to the Mac) it did ~7.3MB/s. Use the Mac's tailnet address: its LAN IP
  is DHCP with a randomised MAC and changes on reassociation.
- **If ghcr pulls truncate** ("failed to read expected number of bytes:
  unexpected EOF"), side-load the image from xero, which already has it:
  `docker save -o <tmp>/ml.tar ghcr.io/immich-app/immich-machine-learning:vX.Y.Z`
  (no gzip, the layers are compressed already; ~270MB), serve it on the LAN
  for a while (`timeout 3600 python3 -m http.server 8765 --bind 192.168.1.123`,
  no resume support), then `docker load -i` on the Mac and run
  `remote_ml_mac.sh`, which uses the local image.

Stopping it leaves the current queue paused (new uploads get no ML until it
is resumed); run it again to continue. The Kingston's reading jumps with
activity: 63°C under load, 51°C fifteen seconds after a pause.

## Upgrading

- **Never go back to `IMMICH_VERSION=release`:** once, a plain pull of the floating tag put 3.x on a 2.x database.
- **You hear about new releases from Diun:** a notification on ntfy `homelab-updates` (`services/container-updates/`).
- **Steps** (from a real terminal, because the snapshot needs sudo):
  1. `services/immich/upgrade.sh --check` lists the releases in between with links, diffs upstream `docker-compose.yml` and `example.env`, and pulls the images. It changes nothing.
  2. Read the releases it lists. Copy into our `docker-compose.yml` / `.env` whatever from the upstream diff applies to us.
  3. `services/immich/upgrade.sh` (latest) or `upgrade.sh vX.Y.Z`. It asks for `yes`, then stops server and ML, snapshots both datasets as `@pre-vX.Y.Z`, sets `.env`, starts server, ML and redis, waits for healthy and prints the migration lines.
  4. Check the web UI and the phone app, add a line below, and delete the previous `@pre-*` snapshots.

2026-10-09: 2.7.5 -> 3.3.1 went through 2.7.5 on the
`ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0` image first,
because 3.0 dropped pgvecto.rs; the 2.7.5 server migrated the indexes to
VectorChord on its first start. Snapshots `@pre-v3` were taken before it.

2026-10-21: 3.3.1 -> 3.3.4 with `upgrade.sh` (snapshots `@pre-v3.3.4`). No
compose or `example.env` changes; one migration, `AddAssetFaceAssetState`
(denormalised owner/visibility columns on `asset_face`), ran in about a second.

2026-10-30: 3.3.4 -> 3.3.5 with `upgrade.sh` (snapshots `@pre-v3.3.5`), in the
middle of the ML backlog run; the queue sat in Redis and carried on. The
`@pre-v3` and `@pre-v3.3.4` snapshots were deleted the same day (~32G).

2026-11-14: 3.3.5 -> 3.4.1 with the new `upgrade.sh` (snapshots `@pre-v3.4.1`). Three
migrations (`AddPasskeyTable`, `AddUpdateIdIndexes`, `AddAssetOwnerIdUpdateIdIndex`) in
about a second. Copied upstream's valkey digest; **not** upstream's new
`MACHINE_LEARNING_MODEL_REVISION: v2` on the ML service (it downloads new model
files; untested whether search/face results stay compatible or the ML backlog reruns).
3.4 adds built-in backups (`futo-backups`, "Yucca"): it generates a key on start,
nothing is configured.

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

When exporting, pick **.zip**. **Part size:** 50GB means fewer Takeout requests
and cookie refreshes; 10GB makes a part that fails its zip test cheaper to
re-fetch.

| Script | Use it for |
|---|---|
| `takeout_browser.sh` | A temporary Chromium on xero, viewed over an SSH tunnel, to download an export straight to `datapool` |
| `watch_takeout.sh` | Waits on the browser's downloads and exits at the first finished, failed or stalled part, so a background Claude session can notify and re-run it |
| `test_takeout_zips.sh` | `unzip -tq` on every zip in a Takeout folder, pausing when the datapool SSD passes 65C; logs to `<dir>/zip-test.log` so a re-run skips parts already ok |
| `import_takeout.py` | A user's whole export, into that user's library |
| `verify_takeout.py` | Checking the import by SHA-1 afterwards |
| `upload_from_takeout.sh` | Topping up a few rows from `verify_takeout.py`, from zips directly in `/datapool/google-takeout/` |

Not immich-go: 0.32 (the latest release) cannot read Immich 3.3's asset list
(simulot/immich-go#1442).

### Running a whole-library import

Run on xero, from the repo root, in tmux. `<user>` is a folder name you pick;
`<email>` is the Immich login of the person whose photos these are.

1. Have that person make an API key in Immich (Account Settings -> API Keys,
   logged in as them, all permissions). Add it to `.env`:
   `IMMICH_API_KEY_<USER>=...`
2. Download through a browser running on xero. `takeout_download.sh` does not
   work against real Google: on 2026-11-08 it was sent to the interactive
   sign-in page even with cookies from `takeout` and `accounts.google.com`.
   ```
   services/immich/takeout_browser.sh start <user>
   ```
   On the Mac run `ssh -N -L 3001:127.0.0.1:3001 pramod@xero`, open
   https://localhost:3001, sign in as that person and click Download on about
   5 parts at a time. When all are in, test them and remove the browser and
   its signed-in profile:
   ```
   for z in /datapool/google-takeout/<user>/*.zip; do unzip -tq "$z" || echo "BAD $z"; done
   services/immich/takeout_browser.sh stop
   ```
3. Look at what is in the zips (albums, counts, files with no JSON):
   ```
   python3 -I services/immich/import_takeout.py /datapool/google-takeout/<user> --dry-run
   ```
4. Try a handful, then look at them in Immich (dates, names, that they are in
   the right library):
   ```
   python3 -I services/immich/import_takeout.py /datapool/google-takeout/<user> --key-var IMMICH_API_KEY_<USER> --as <email> --limit 5
   ```
5. Run it all. It carries on from step 4, and can be re-run after any stop:
   ```
   python3 -I services/immich/import_takeout.py /datapool/google-takeout/<user> --key-var IMMICH_API_KEY_<USER> --as <email>
   ```
6. Check it (see below), then delete `~/cookies.txt`, the zips and the `.env` key.

**What the importer does and does not carry over**

- **Carried over:** capture date for files with no EXIF date, favourites,
  archived state, original filename, albums.
- **Left out:** photos in Google's bin; descriptions; locations added in
  Google Photos (GPS in the file's own EXIF still works).
- **Live Photos:** the still and video go up as separate files; Immich pairs
  them from their metadata.

**Traps**

- **Wrong library:** `--as` stops the run if the key is not that person's.
  A photo both people have is deliberately imported into both libraries.
- **Heat:** capped at 20 MB/s (`--max-mb-per-s`), pauses at SSD 70°C or CPU
  85°C until 62°C / 70°C. Stops at 50 GB free on the pool.
- **Immich down:** it waits for Immich to come back, e.g. after the load guard
  has stopped it. A tripped guard needs clearing by hand (see "Load guard").
- **Failures:** listed in `<dir>/import-failures.tsv` and retried on the next
  run. `<dir>/import-state.jsonl` is what makes re-runs safe: keep it until
  the zips go.
- **After a big import:** thumbnails, transcodes and ML catch up in the
  background. See "ML backlog".

`test_import_takeout.py` runs the importer against a fake Immich and a made-up
export.

### Checking an import is complete

`verify_takeout.py` hashes every photo and video in the zips and looks each
SHA-1 up in `asset.checksum`; `compare_takeout_dates.py` settles the rows
where Immich has a file of the same name but other bytes, by capture time.
For a whole-library import, pass the folder and the owner, or a photo already
in someone else's library counts as imported:

```
nice -n 19 ionice -c3 python3 -I services/immich/verify_takeout.py ~/takeout-verify.tsv --dir /datapool/google-takeout/<user> --owner <email>
```

Photos Google had in the bin show up as missing; that is expected. For anything
else, re-run `import_takeout.py`. For the admin zips directly in
`/datapool/google-takeout/`, upload what is really missing with
`upload_from_takeout.sh rows.tsv`.

2026-10-22, admin's June export: 13,237 unique files, 12,906 already in
Immich. 282 same-name rows were the same photos (time matched to the second;
Takeout's copies smaller). 13 were really missing - the import's 90
"pending": GoPro videos GOPR0103/0274/0300 and 10 photos from January 2018 -
and were uploaded, as were the 26 Google "-edited" copies. Never uploaded:
10 GoPro `.THM`/`.LRV` side files. `Photos from 2023/IMG_4352.MOV`, damaged in
the zip (bad CRC), was re-downloaded from Google Photos by hand (link from
`takeout_photo_url.sh`) and uploaded the same day. The zips were deleted
that evening; these scripts need a fresh export to run again.

## Transcodes and thumbnails at copies=1

`split_regenerable.sh` (2026-11-02, done 2026-11-10) moves `encoded-video/` and
`thumbs/` into child datasets of `datapool/immich-upload` with `copies=1`:
both are regenerable, and at `copies=2` they took ~124G of the Kingston for
~62G of data. Same paths, so compose does not change. `sudo ... check` first;
`run` stops Immich, copies paced by SSD temperature, verifies and restarts;
`finish` deletes the `.old` copies after a spot-check; `rollback` undoes it.
See "datapool storage headroom" in PROJECTS.md.

When you decide to run it:

```
sudo services/immich/split_regenerable.sh check
sudo services/immich/split_regenerable.sh run
```

Then spot-check Immich in the browser: thumbnails load, a few videos play, and a new upload gets a thumbnail. After that:

```
sudo services/immich/split_regenerable.sh finish
```

If anything looks wrong before `finish`, `rollback` puts everything back as it was:

```
sudo services/immich/split_regenerable.sh rollback
```

## Thumbnails on the boot disk

`move_thumbs_to_boot.sh` moved `thumbs/` to `/var/lib/immich-thumbs` on 2026-11-10, through a bind mount in `docker-compose.yml`.

- **Switch:** `IMMICH_THUMBS_LOCATION` in `.env`. Without it the mount uses the datapool path.
- **Needs first:** `split_regenerable.sh finish`.
- **Dry test:** `services/immich/test_move_thumbs.sh`.

Run steps:

1. `sudo services/immich/move_thumbs_to_boot.sh check`
2. `sudo services/immich/move_thumbs_to_boot.sh run`
3. Spot-check: thumbnails load in the timeline, a new upload gets one.
4. `sudo services/immich/move_thumbs_to_boot.sh finish` destroys the old dataset. Before this, `rollback` undoes the move.

Traps:

- **Boot disk space:** thumbnails take ~3G per 10,000 photos, and the boot disk has ~43G free. Check before a large import.
- **After `finish`:** do not re-run `split_regenerable.sh`, which would recreate a `thumbs` dataset nothing uses.
- **`.env` line lost:** Immich would mount an empty folder on datapool and fail its storage check. Put the line back.

## Hardware requirements


Immich + its ML container + Postgres + Redis + the rest of the stack causes kernel panics on 8 GB RAM due to memory exhaustion. **Immich is disabled in docker-compose.yml until hardware is upgraded.**

Data is safe on the ZFS pool: `datapool/immich-upload` (15 GB), `datapool/immich-db` (133 MB).

To re-enable, uncomment the `immich-server`, `immich-machine-learning`, `redis`, `database` services and the `model-cache` volume in `docker-compose.yml`.

Options to bring Immich back:
- **Add RAM to this machine** — 16 GB minimum recommended
- **Dedicated machine** — run Immich on a separate device (Raspberry Pi 5 with 8 GB works)
- **Disable ML only** — comment out just `immich-machine-learning`; server runs with much less RAM but no face/object recognition
