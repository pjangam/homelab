# Old duplicity backup in Google Drive (`My Drive -> xero`)

Found 2026-10-26. Decision on keeping or deleting it is pending - see the
"Old duplicity backup in Google Drive" entry in `PROJECTS.md`.

## What is there

- Files named `duplicity-full.20190406T161704Z.volN.difftar.gpg`, N = 1..134,
  25 MB each: about **3.3 GB**.
- One backup set: a single full backup taken 2019-04-06 16:17 UTC. No
  `duplicity-inc.*` volumes were seen, so nothing was ever added on top of it.
  Check for the `.manifest.gpg` and `.sigtar.gpg` files too. Without the
  manifest, restoring is much harder.

## What it probably is

- Written by duplicity, most likely through Ubuntu's built-in **Backups** app
  (Deja Dup). Deja Dup backs up to Google Drive and names the folder after the
  hostname. The 25 MB volume size also points to Deja Dup.
- Deja Dup's default is the **home folder only** (minus Trash and Downloads),
  not the whole disk. 3.3 GB compressed (maybe 4-6 GB of original files) fits
  a home folder, not a system disk.
- Nothing in this repo made it. The repo starts 2025-03-12, there is no
  duplicity or Deja Dup reference in files or history, and neither tool is
  installed on xero now. Current backups go to Dropbox, not Google Drive.

## Can it be opened

Only with the GPG passphrase set when the backup was configured in 2019. The
user does not remember it, there is no recovery key, and the file names reveal
nothing about the contents. Without the passphrase it is unreadable.

Before deciding:
1. Search Vaultwarden for "backup", "deja", "duplicity", "xero".
2. Try passphrases you reused around 2019.

If one works: run duplicity in Docker on xero, pull the folder with rclone,
and run `duplicity list-current-files` to see the contents without restoring.

If none works: delete the whole `xero` folder in Drive, then empty Drive's
Trash. Files in Trash still count against storage until it is emptied. This
frees about 3.3 GB and loses nothing recoverable.
