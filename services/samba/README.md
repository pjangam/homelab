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
- **Older files have only one copy.** `copies` only applies to blocks written
  after it is set. For this dataset, `used` equals `logicalused` (11.6G each),
  so the videos already here when `copies=2` was turned on are still stored
  once. Compare `datapool/recovered-media`, whose 425M of data uses 851M.
  Copying a file to a new name and replacing the original rewrites it with two
  copies. To check the dataset as a whole:
  `zfs get -H -o property,value used,logicalused,copies datapool/phone-uploads`.

## Checking it from xero

xero has no `smbclient` installed, but the container image does:

```sh
set -a; . ./.env; set +a
docker run --rm --network host --entrypoint smbclient dperson/samba \
  //192.168.1.123/phone-uploads -U "$SAMBA_USER%$SAMBA_PASSWORD" -c ls
```

To see the share config the container generated:
`docker exec samba sed -n '/\[phone-uploads\]/,$p' /etc/samba/smb.conf`.

## Gotchas

- **HEIC photos.** The iPhone uploads photos as `.heic`, which GitHub and most
  browsers will not display. Convert them on xero with ImageMagick. It has
  HEIC support, while `ffmpeg` and `heif-convert` are not installed.
  `-strip` removes EXIF data, including any GPS location:
  `convert IMG_1234.heic -auto-orient -resize '1600x1600>' -strip -quality 82 out.jpg`
- **Changing the password:** edit `SAMBA_PASSWORD` in `.env`, run
  `docker compose up -d samba`, then update Vaultwarden.
