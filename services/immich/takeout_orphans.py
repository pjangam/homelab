#!/usr/bin/env python3
"""List photos and videos the Takeout zips describe but do not contain.

Takeout writes a sidecar JSON per file, and a sidecar can land in a
different part from its file. So when a part is lost (part 019 of the
2026-06 export, out of download attempts) its files still show up as
sidecars with no file of that title in their folder in any zip. For each
one this prints the capture time, whether Immich has an asset of that name
taken within 2 minutes of it (any whole half hour off, for time zones), and
the Google Photos link to download it from by hand:

    python3 -I services/immich/takeout_orphans.py

GoPro .THM/.LRV side files are skipped: Immich does not need them.
"""
import json
import subprocess
import sys
import zipfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

ZIPS = Path("/datapool/google-takeout")
REPO = Path(__file__).resolve().parents[2]


def env(key):
    for line in (REPO / ".env").read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1]
    sys.exit(f"{key} not in .env")


def immich_times():
    sql = ('select lower(a."originalFileName"), '
           'extract(epoch from e."dateTimeOriginal"), '
           'extract(epoch from a."localDateTime") '
           'from asset a left join asset_exif e on e."assetId" = a.id')
    out = subprocess.run(
        ["docker", "exec", "immich_postgres", "psql", "-U", env("DB_USERNAME"),
         "-d", env("DB_DATABASE_NAME"), "-AtF", "\t", "-c", sql],
        check=True, capture_output=True, text=True).stdout
    times = defaultdict(list)
    for line in out.splitlines():
        name, *ts = line.split("\t")
        times[name].extend(float(t) for t in ts if t)
    return times


def near(taken, times):
    for t in times:
        d = abs(taken - t)
        k = round(d / 1800)
        if k <= 28 and abs(d - k * 1800) <= 120:
            return True
    return False


def main():
    files = set()     # (folder, lower(name)) of every media entry
    sides = []        # (folder, meta) of every sidecar
    for z in sorted(ZIPS.glob("*.zip")):
        with zipfile.ZipFile(z) as zf:
            for info in zf.infolist():
                p = PurePosixPath(info.filename)
                if info.is_dir() or p.suffix.lower() == ".html":
                    continue
                if p.suffix.lower() != ".json":
                    files.add((str(p.parent), p.name.lower()))
                    continue
                try:
                    meta = json.loads(zf.read(info))
                    meta["title"], int(meta["photoTakenTime"]["timestamp"])
                except (ValueError, KeyError, TypeError):
                    continue          # album metadata.json and the like
                sides.append((str(p.parent), meta))

    immich = immich_times()
    seen = set()
    rows = []
    for folder, meta in sides:
        title = meta["title"]
        key = (folder, title.lower())
        if key in files or key in seen or title.upper().endswith((".THM", ".LRV")):
            continue
        seen.add(key)
        taken = int(meta["photoTakenTime"]["timestamp"])
        have = near(taken, immich.get(title.lower(), []))
        rows.append((taken, title, have, meta.get("url", ""), folder))

    rows.sort()
    for taken, title, have, url, folder in rows:
        when = datetime.fromtimestamp(taken, timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        print(f"{'in Immich' if have else 'MISSING  '}  {when}  {title}  "
              f"[{PurePosixPath(folder).name}]  {url}")
    print(f"\n{len(rows)} files only described by a sidecar, "
          f"{sum(1 for r in rows if not r[2])} not in Immich")


if __name__ == "__main__":
    main()
