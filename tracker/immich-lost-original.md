# Immich: lost original IMG-20191013-WA0002.jpg
**Status:** Done

#### Open items
- Nothing open.

**Why:** one Immich photo has a DB row but no file on disk (user, 2026-11-17: "record it as seperate p3 entry"). Split out of "Immich Glacier archive: 2026-11-01 upload failed", where it showed up as `missing on disk:`.
**State:** researched on xero 2026-11-17; the only candidate source left is Google Photos itself.

#### The asset
| Field | Value |
|---|---|
| Asset id | `83a258e2-ec0a-4875-b253-6863b164a999` |
| `originalPath` | `/usr/src/app/upload/library/admin/2019/2019-10-13/IMG-20191013-WA0002.jpg` |
| On the host | `/datapool/immich-upload/library/admin/2019/2019-10-13/` - the folder does not exist |
| `originalFileName` | `IMG-20191013-WA0002.jpeg` (note `.jpeg`; Google Photos may show this name) |
| SHA-1 (`asset.checksum`) | `0520323229ea29eb97da0ac071526c22bad98551` |
| `fileCreatedAt` | 2019-10-13 08:59:36 UTC (14:29 IST) |
| DB state | active, visible in the timeline, `deletedAt` null |

#### What is known
- **Imported 2026-06-26** in the Google Takeout import (6,711 assets that hour). Immich computed its SHA-1 then, so the whole file was on disk.
- **Gone before 2026-10-09**, most likely in the bad-RAM / ZFS corruption period. Not in the `@pre-v3.3.5` or `@pre-v3.4.1` snapshots, not anywhere under `/datapool`.
- **Not in the Takeout zips:** 57 others lost the same way were restored from them (`services/immich/restore_from_takeout.sh`); this one is in none of the 22 zips in `datapool/google-takeout/`, probably in the never-downloaded part `019`.
- **Not in the S3 Glacier archive:** `projects/immich-backup/archive_to_glacier.sh` logs `missing on disk:` for it and skips it on every run (2026-10-22, 2026-11-01, 2026-11-17).
- **Restore method:** `restore_from_takeout.sh` shows it - copy in through the `immich_server` container so it lands root:root 644, and only if the SHA-1 matches. A file re-downloaded from Google Photos may not match byte for byte (Google can re-encode or strip metadata); if it does not, decide then between putting it in anyway or uploading it as a new asset and deleting the old one.
- **Already in the record:** the "Immich re-enablement" entry's 2026-10-11 and 2026-10-14 logs and its Outcome ("Lost for good").

#### Log
- 2026-11-17: entry created (user, P3) from the facts gathered while fixing the Glacier archive.
- 2026-11-17: **resolved (user).** Found in Google Photos: an MNGL gas meter reading, not worth restoring. Asset deleted through the Immich API (`DELETE /api/assets`, `force: true`, 204); the row is gone, and the archive dry run no longer logs `missing on disk:`.
