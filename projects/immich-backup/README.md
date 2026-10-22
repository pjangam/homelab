# Immich backup

Off-site copy of Immich's originals in S3 Glacier Deep Archive, read only if
the Kingston SSD and the local backup are both lost. Plan, costs and the
local (SD card) half: the "Offsite backup for Immich photo data" entry in
`PROJECTS.md`. How it works and how to restore: the header of
`archive_to_glacier.sh`.

## AWS setup (once, in the console, as the root/admin login)

1. **S3 -> Create bucket**, region **US East (N. Virginia) `us-east-1`**.
   Bucket names are global, so pick something unguessable, e.g.
   `xero-immich-archive-<random>`. Leave "Block all public access" on.
   Turn **Bucket Versioning on**: if anything ever writes an existing name
   again, the old object stays as a version instead of being replaced.
2. Bucket -> **Management -> Create lifecycle rule**, whole bucket:
   "Delete expired object delete markers or incomplete multipart uploads",
   incomplete multipart uploads after **7 days**. A run that dies mid-upload
   otherwise leaves its parts billed at the Standard rate.
3. **IAM -> Policies -> Create policy -> JSON**: paste `iam-policy.json`
   with `BUCKET_NAME` replaced (both places). Name it `immich-archive-upload`.
4. **IAM -> Users -> Create user** `xero-immich-archive`, no console access,
   attach that policy. Then Security credentials -> **Create access key**
   ("Application running outside AWS").
5. On xero, add to `.env` (gitignored):

   ```
   AWS_ACCESS_KEY_ID=...
   AWS_SECRET_ACCESS_KEY=...
   IMMICH_BACKUP_BUCKET=<bucket name>
   ```

The key can add objects under `immich/` and list them, nothing else: it
cannot delete, cannot change the bucket, and cannot restore, so it cannot
read an archived photo either (they are gpg-encrypted besides). A restore
uses the admin login.

## Running

```
projects/immich-backup/archive_to_glacier.sh --dry-run   # what would go up
projects/immich-backup/archive_to_glacier.sh             # first run: ~80G, hours
```

Monthly from cron after the first run, logging into `backup.log` like the
other backups.
