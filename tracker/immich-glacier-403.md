# Immich Glacier archive: 2026-11-01 upload failed (S3 403 Forbidden)
**Status:** Done

#### Open items
(none - the missing 2019 photo continues as "Immich: lost original IMG-20191013-WA0002.jpg")

**Why:** the monthly offsite copy of Immich originals ("Offsite backup for Immich photo data") failed on its 2026-11-01 run, so this month's 75 new originals (4456 MB) are not offsite. It was only noticed by reading `backup.log` on 2026-11-08; no alert fired.

#### What the log shows
| Time (IST) | Line |
|---|---|
| 04:00:05 | 75 originals to archive (4456 MB) |
| 04:00:05 | uploading `bundles/2026-11-01-00024.tar.gpg` (44 MB, 3 files) |
| 04:00:33 | `rcat error: Forbidden ... status code: 403, request id: CARKS4D3GRSN3V2P` |
| 04:00:33 | `Failed to rcat with 2 errors` |

- **The first bundle was refused**, so the run stopped there; whether earlier months' bundles are intact is not checked yet.
- **A 403, not a network error:** credentials were accepted far enough to be refused, which points at the key, the IAM policy, a bucket policy or the storage class allowed, not at xero.
- Also in the same run: `missing on disk: .../library/admin/2019/2019-10-13/IMG-20191013-WA0002.jpg` (an asset in Immich's DB with no file); separate, look at after the 403.
- The bucket and IAM user are not in Terraform (no `.tf` in the repo); the policy the user should carry is `projects/immich-backup/iam-policy.json`. Any new AWS resource from the fix goes in Terraform, keys by hand.

#### Log
- 2026-11-08: found while reading the night jobs' logs for the scrub schedule. Logged as P1, Active (user); the user checks the AWS side on 2026-11-09.
- 2026-11-17: **cause found.** The upload itself succeeded: `bundles/2026-11-01-00024.tar.gpg` is in S3 at 44,809,597 bytes. Reproduced with a 200KB probe (`immich/test/probe3.bin`, `probe4.bin`) and `--dump headers`: CreateMultipartUpload, UploadPart and CompleteMultipartUpload all 200, then rclone 1.60 checks the object with `HEAD ...?versionId=` (bucket versioning is on). A HEAD that names a version needs `s3:GetObjectVersion`; the policy grants only `s3:GetObject`. `--s3-no-head` does not stop this check. rclone exits non-zero and `set -e` stops the run before the manifest line, so the rest of the month never went up.
- 2026-11-17: `iam-policy.json` now has `s3:GetObjectVersion`; needs applying in the console. Whether October's run avoided this because versioning was turned on after it is unknown; it does not change the fix.
- 2026-11-17: 00024 is in S3 but not in the local manifest, so the next run bundles those 3 files again under a new name. That is 44MB of duplicate data in Deep Archive, so it is left as is.
- 2026-11-17: **why nothing alerted:** healthcheck flags the archive only after 33 days without a completed run (last 2026-10-23), so the first alert would have come ~2026-11-25. `archive_to_glacier.sh` now has an EXIT trap that sends ntfy + email on any non-zero exit (not in test runs); tested with a forced failure and the ntfy alert arrived. `test_archive.sh` passes.
- 2026-11-17 12:40: user added `s3:GetObjectVersion` in the console; probe `test/probe5.bin` then got HEAD 200, exit 0.
- 2026-11-17 12:40-13:12: **catch-up run, exit 0.** 290 originals (6712 MB): `2026-11-17-00024` (318MB, 6 files), `-00025` (4.0G, 1 file, `GOPR0178+1.mp4`), `-00026` (2.4G, 283 files), plus the 2026-11-17 DB dump and manifest; every size matched in S3. The 3 files of the orphan `2026-11-01-00024` went up again in `-00024` (45MB). Dry run afterwards: 3 new originals, which go up on 2026-12-01. Fixed, so lowered to P3 for the missing-file item that is left.
- 2026-11-17: **Done** (user). The `missing on disk` photo is not a backup fault: it went missing from disk before 2026-10-09 (already in the Immich entry's 2026-10-11 log), so it moved to its own P3 entry.
