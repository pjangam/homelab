#!/usr/bin/env python3
"""Check that every photo and video in the Google Takeout zips is in Immich.

Streams each non-JSON entry of /datapool/google-takeout/*.zip through SHA-1,
without extracting anything, and looks the hash up in Immich's own
asset.checksum. Takeout repeats a photo once per album folder, so entries are
counted by unique hash. Run on xero from the repo root, at low priority:

    nice -n 19 ionice -c3 python3 -I services/immich/verify_takeout.py [report.tsv]

Prints a summary and writes every unique hash Immich lacks to the report
(default ~/takeout-verify.tsv): sha1, size, a same-name Immich asset if one
exists (a sign of an edited or re-encoded copy rather than a lost one), then
zip and entry. Entries that fail the zip's own CRC (damaged when the zip was
saved, not on ZFS) are listed too, with sha1 "bad-crc", and not checked.
Immich assets that are in the trash count as present but are flagged, since
emptying the trash would lose them. restore_from_takeout.sh
needs an asset id, so it does not apply to photos Immich never had; upload
those with immich-go instead.
"""
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


def immich_assets():
    sql = ('select encode(checksum, \'hex\'), lower("originalFileName"), '
           '"deletedAt" is not null from asset')
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
    report = Path(sys.argv[1] if len(sys.argv) > 1 else
                  os.path.expanduser("~/takeout-verify.tsv"))
    by_hash, names = immich_assets()
    print(f"Immich: {len(by_hash)} assets", flush=True)

    seen = {}  # sha1 -> (size, zip, entry) of its first occurrence
    bad = []   # (size, zip, entry) whose bytes fail the zip's CRC
    entries = 0
    zips = sorted(ZIPS.glob("*.zip"))
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
