# Samba - `phone-uploads` share

A plain SMB file drop on xero. It was set up so videos could come off the
iPhone while Immich is disabled, and it is now the easy way to move any file
from the phone or a laptop onto xero. It is not photo management: nothing
indexes, dedupes or backs up what lands here.

The container is `samba` (`dperson/samba`), defined in `docker-compose.yml`.
There is no config file of its own: the share is set up entirely by the
`command:` flags there, and the container writes its own `smb.conf` from them.

## Basics

| | |
|---|---|
| **Share name** | `phone-uploads` |
| **Username** | `phoneupload` (`SAMBA_USER` in `.env`) |
| **Password** | `SAMBA_PASSWORD` in `.env`, and in Vaultwarden. Never in git. |
| **Directory on xero** | `/datapool/phone-uploads` (`PHONE_UPLOADS_LOCATION` in `.env`), mounted as `/share` in the container |
| **Storage** | its own ZFS dataset `datapool/phone-uploads`, compression on, no quota. It is kept separate from Immich's datasets on purpose. |
| **Redundancy** | `copies=2` on a **single-disk** pool: two copies on one disk, no mirror. See [Durability](#durability) below. |
| **File ownership** | every file lands owned by `pramod` (uid/gid 1000), whoever logged in. That is set by `USERID`/`GROUPID` in the compose file. |
| **Permissions** | read-write, no guest access, `phoneupload` is the only valid user |
| **Ports** | 445 (SMB), plus 139 for older clients. Both are published on every interface. |

## Connecting

The same login works at every address below. All three were checked
(2026-09-21) by listing the share with `smbclient`, run on xero itself.

| From | Address |
|---|---|
| Home LAN | `smb://192.168.1.123/phone-uploads` |
| Tailnet, MagicDNS | `smb://xero.<tailnet>.ts.net/phone-uploads` |
| Tailnet, by IP | `smb://100.70.215.25/phone-uploads` |

Over the tailnet it also works away from home, carried inside Tailscale, so
there is no need to open port 445 to the internet.

- **iPhone:** Files app → `...` → Connect to Server → one of the addresses
  above → Registered User.
- **Mac:** Finder → Go → Connect to Server (Cmd-K).
- **Linux:** `smbclient //192.168.1.123/phone-uploads -U phoneupload`, or
  mount it with `cifs-utils`.

## Durability

Checked 2026-09-21 with `zpool status` and `zfs get`.

| | |
|---|---|
| **Pool layout** | `datapool` is a single disk (`sda`, a Kingston SA400 960GB). There is no mirror and no raidz. |
| **`copies`** | `2`, set on this dataset (it is not inherited from the pool). ZFS stores every block twice on the same disk. |
| **`sync`** | `always`. Every write is committed to disk before it is acknowledged, which costs speed but guards against power loss. |
| **Snapshots** | none |
| **Scrub** | monthly, on the second Sunday (the stock `zfsutils-linux` cron job). The last one found 0 errors. |
| **Off-machine backup** | none. It is not in the Dropbox rclone jobs. |

What that adds up to:

- **Protected against:** bit rot and isolated bad sectors. When a checksum
  fails, ZFS repairs the block from its second copy, and the scrub finds such
  errors before a read does.
- **Not protected against:** losing the disk. Both copies are on `sda`, so if
  that SSD dies, the whole share goes with it. Accidental deletes are not
  covered either, because there are no snapshots. Treat the share as a staging
  area and keep anything irreplaceable somewhere else too.
- **Every file has two copies (since 2026-09-21).** `copies` only applies to
  blocks written after it is set, and the videos from July were written
  before, so `used` equalled `logicalused` (11.6G each).
  `rewrite_for_copies.sh` rewrote them all, and `used` is now 23.2G for 11.6G
  of data. To check it again:
  `zfs get -H -o property,value used,logicalused,copies datapool/phone-uploads`.
  About 2x means two copies; about equal means one.
- **Rewriting a file needs `dd`, not `cp` or `cat`.** The pool has block
  cloning enabled, and `cp` (and `cat`, since coreutils 9) copy through
  `copy_file_range`, which ZFS turns into a clone of the same blocks. The copy
  then keeps however many copies the original had. The first attempt at the
  rewrite used `cat` and changed nothing.

## Checking it from xero

xero has no `smbclient` installed, but the container image does:

```sh
set -a; . ./.env; set +a
docker run --rm --network host --entrypoint smbclient dperson/samba \
  //192.168.1.123/phone-uploads -U "$SAMBA_USER%$SAMBA_PASSWORD" -c ls
```

To see the share config the container generated:
`docker exec samba sed -n '/\[phone-uploads\]/,$p' /etc/samba/smb.conf`.

## Users

Users live in `docker-compose.yml`, not in the container. On every start,
`dperson/samba` runs `adduser` and `smbpasswd -a` for each `-u` flag, and
writes each share's `valid users` from its `-s` flag. Anything done with
`docker exec samba smbpasswd ...` is lost the next time the container is
recreated (for example when Watchtower updates the image), so always make the
change in the compose file.

**Adding a user - the quick way:**

```sh
services/samba/add_user.sh alice                 # read-write on phone-uploads
services/samba/add_user.sh alice other-share     # or on another share
NO_APPLY=1 services/samba/add_user.sh alice      # edit the files, don't restart
```

The script generates a password, appends `SAMBA_PASSWORD_ALICE` to `.env`,
adds the user to `docker-compose.yml` as described below, recreates the
container, checks the new login with `smbclient`, and prints the password once
so you can put it in Vaultwarden. Commit the `docker-compose.yml` change
afterwards. Recreating the container drops any SMB connections that are open,
so do it when nothing is uploading.

**Adding a user by hand** (this is what the script does):

1. Add the password to `.env` (gitignored), and store it in Vaultwarden
   too. The username is not a secret, so it goes straight into the compose
   file.
   ```sh
   SAMBA_PASSWORD_ALICE=<a long random one>
   ```
   Do not use `;` in the password. The flag below uses `;` to separate its
   fields.
2. In `docker-compose.yml`, add a second `-u` pair under the samba service's
   `command:`, and add the new user to the share's user list (field 6 of `-s`,
   comma-separated):
   ```yaml
   command:
     - "-p"
     - "-u"
     - "${SAMBA_USER};${SAMBA_PASSWORD};1000;1000;1000"
     - "-u"
     - "alice;${SAMBA_PASSWORD_ALICE}"
     - "-s"
     - "phone-uploads;/share;yes;no;no;${SAMBA_USER},alice;;;iPhone video drop zone"
   ```
   Leave the uid off the new user. The container uses busybox `adduser`,
   which refuses a uid that is already taken, and it does not matter anyway:
   the generated `smb.conf` has `force user = smbuser`, so files land owned by
   uid 1000 whoever wrote them.
3. `docker compose up -d samba`, then check the login with the `smbclient`
   command above, swapping in the new user's credentials.
   `docker exec samba pdbedit -L` lists the users Samba knows about.

**Read-only user:** list them in the share's users field (field 6) and also
set a write list (field 8) that holds only the users allowed to write, e.g.
`...;${SAMBA_USER},alice;;${SAMBA_USER};...`.

**A share of its own:** add another `-s` flag with a different name and path,
and a bind mount for that path under `volumes:`. For anything that matters,
give it its own ZFS dataset with `copies=2`, the way `phone-uploads` has.

**Changing a password:** edit it in `.env`, run `docker compose up -d samba`,
then update Vaultwarden.

**Removing a user:** delete their `-u` pair and remove them from every `-s`
user list, then run `docker compose up -d samba`. The container is recreated
from scratch, so the old account is gone.

## Gotchas

- **HEIC photos.** The iPhone uploads photos as `.heic`, which GitHub and most
  browsers will not display. Convert them on xero with ImageMagick. It has
  HEIC support, while `ffmpeg` and `heif-convert` are not installed.
  `-strip` removes EXIF data, including any GPS location:
  `convert IMG_1234.heic -auto-orient -resize '1600x1600>' -strip -quality 82 out.jpg`
