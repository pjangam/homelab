#!/usr/bin/env python3
"""Check that every photo and video in the Google Takeout zips is in Immich.

Streams each non-JSON entry of /datapool/google-takeout/*.zip through SHA-1,
without extracting anything, and looks the hash up in Immich's own
asset.checksum. Takeout repeats a photo once per album folder, so entries are
counted by unique hash. Run on xero from the repo root, at low priority:

    nice -n 19 ionice -c3 python3 -I services/immich/verify_takeout.py [report.tsv] \\
        [--dir /datapool/google-takeout/bhakti] [--owner her@email]

--owner checks against that user's library only. Without it, a photo in anyone's
library counts as present, which is wrong for a second person's import: photos
the two of you share would look imported when they are not in hers.

Prints a summary and writes every unique hash Immich lacks to the report
(default ~/takeout-verify.tsv): sha1, size, a same-name Immich asset if one
exists (a sign of an edited or re-encoded copy rather than a lost one), then
zip and entry. Entries that fail the zip's own CRC (damaged when the zip was
saved, not on ZFS) are listed too, with sha1 "bad-crc", and not checked.
Immich assets that are in the trash count as present but are flagged, since
emptying the trash would lose them. restore_from_takeout.sh
needs an asset id, so it does not apply to photos Immich never had; upload
those with upload_from_takeout.sh, or re-run import_takeout.py for a user's
import. Files Google had in the bin are in the zips but deliberately not
imported, so they show up here as missing.
"""
import argparse
import hashlib
import os
import subprocess
import sys
import zipfile
from pathlib import Path

ZIPS = Path("/datapool/google-takeout")
REPO = Path(__file__).resolve().parents[2]


def env(key):
    for line in (REPO / ".env").read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1]
    sys.exit(f"{key} not in .env")


def immich_assets(owner=None):
    where = ""
    if owner:
        email = owner.replace("'", "''")
        where = f" where \"ownerId\" = (select id from \"user\" where email = '{email}')"
    sql = ('select encode(checksum, \'hex\'), lower("originalFileName"), '
           '"deletedAt" is not null from asset' + where)
    out = subprocess.run(
        ["docker", "exec", "immich_postgres", "psql", "-U", env("DB_USERNAME"),
         "-d", env("DB_DATABASE_NAME"), "-AtF", "\t", "-c", sql],
        check=True, capture_output=True, text=True).stdout
    by_hash, names = {}, set()
    for line in out.splitlines():
        h, name, trashed = line.split("\t")
        by_hash[h] = trashed == "t"
        names.add(name)
    return by_hash, names


def sha1(zf, info):
    h = hashlib.sha1()
    with zf.open(info) as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report", nargs="?", default=os.path.expanduser("~/takeout-verify.tsv"))
    parser.add_argument("--dir", default=str(ZIPS), help="folder holding the zips")
    parser.add_argument("--owner", help="email of the user whose library to check against")
    args = parser.parse_args()
    report = Path(args.report)
    by_hash, names = immich_assets(args.owner)
    print(f"Immich: {len(by_hash)} assets" + (f" owned by {args.owner}" if args.owner else ""), flush=True)
    if args.owner and not by_hash:
        sys.exit(f"no assets for {args.owner}: wrong email?")

    seen = {}  # sha1 -> (size, zip, entry) of its first occurrence
    bad = []   # (size, zip, entry) whose bytes fail the zip's CRC
    entries = 0
    zips = sorted(Path(args.dir).glob("*.zip"))
    for i, z in enumerate(zips, 1):
        with zipfile.ZipFile(z) as zf:
            for info in zf.infolist():
                if info.is_dir() or info.filename.lower().endswith((".json", ".html")):
                    continue
                entries += 1
                try:
                    h = sha1(zf, info)
                except zipfile.BadZipFile:
                    bad.append((info.file_size, z.name, info.filename))
                    print(f"  bad CRC: {info.filename}", flush=True)
                    continue
                seen.setdefault(h, (info.file_size, z.name, info.filename))
        print(f"[{i}/{len(zips)}] {z.name}: {entries} entries, "
              f"{len(seen)} unique so far", flush=True)

    missing = {h: v for h, v in seen.items() if h not in by_hash}
    trashed = [h for h in seen if by_hash.get(h)]
    with report.open("w") as out:
        out.write("sha1\tsize\tsame_name_in_immich\tzip\tentry\n")
        for h, (size, z, entry) in sorted(missing.items(), key=lambda kv: kv[1][2]):
            same = "yes" if Path(entry).name.lower() in names else ""
            out.write(f"{h}\t{size}\t{same}\t{z}\t{entry}\n")
        for size, z, entry in bad:
            same = "yes" if Path(entry).name.lower() in names else ""
            out.write(f"bad-crc\t{size}\t{same}\t{z}\t{entry}\n")

    lost = [v for v in missing.values() if Path(v[2]).name.lower() not in names]
    print(f"\n{entries} media entries, {len(seen)} unique by SHA-1")
    print(f"in Immich:      {len(seen) - len(missing)} ({len(trashed)} of them in the trash)")
    print(f"not in Immich:  {len(missing)} "
          f"({sum(v[0] for v in missing.values()) / 1e9:.2f} GB)")
    print(f"  same name exists in Immich: {len(missing) - len(lost)}")
    print(f"  no asset of that name:      {len(lost)} "
          f"({sum(v[0] for v in lost) / 1e9:.2f} GB)")
    print(f"damaged in the zip (bad CRC): {len(bad)}, "
          f"{sum(1 for v in bad if Path(v[2]).name.lower() not in names)} with no asset of that name")
    print(f"report: {report}")


if __name__ == "__main__":
    main()
