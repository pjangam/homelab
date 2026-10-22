#!/usr/bin/env python3
"""Sort verify_takeout.py's "same name, different bytes" rows into the same
photo (a re-encoded or re-saved copy) and a different photo Immich lacks.

A name match alone proves little: camera counters repeat (DSC_0001 from two
cameras), and WhatsApp names repeat across years. So for each such row this
reads the Takeout sidecar JSONs in the zips (photoTakenTime, true UTC, keyed
by their "title") and compares them with the capture times of the Immich
assets of that name (asset_exif.dateTimeOriginal, asset.localDateTime and
asset.fileCreatedAt). Immich stores a time without an EXIF offset as if it
were UTC, so a difference of a whole number of half hours (up to 14h, i.e.
a time zone) also counts as a match, within 2 minutes either way.

    python3 -I services/immich/compare_takeout_dates.py [report.tsv] [out.tsv]

Defaults: ~/takeout-verify.tsv in, ~/takeout-same-name.tsv out. The output
adds a verdict per row: same-photo, different-photo, ambiguous (several
sidecars of that title in the folder, only some matching), or no-sidecar
(no JSON with that title in that folder, so it cannot be decided).
"""
import json
import os
import subprocess
import sys
import zipfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

ZIPS = Path("/datapool/google-takeout")
REPO = Path(__file__).resolve().parents[2]
SLACK = 120          # seconds
MAX_TZ = 28          # half hours: 14h


def env(key):
    for line in (REPO / ".env").read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1]
    sys.exit(f"{key} not in .env")


def immich_times(names):
    """lower(originalFileName) -> list of epoch seconds, every time we have."""
    sql = ('select lower(a."originalFileName"), '
           'extract(epoch from e."dateTimeOriginal"), '
           'extract(epoch from a."localDateTime"), '
           'extract(epoch from a."fileCreatedAt") '
           'from asset a left join asset_exif e on e."assetId" = a.id')
    out = subprocess.run(
        ["docker", "exec", "immich_postgres", "psql", "-U", env("DB_USERNAME"),
         "-d", env("DB_DATABASE_NAME"), "-AtF", "\t", "-c", sql],
        check=True, capture_output=True, text=True).stdout
    times = defaultdict(list)
    for line in out.splitlines():
        name, *ts = line.split("\t")
        if name in names:
            times[name].extend(float(t) for t in ts if t)
    return times


def sidecars(wanted):
    """(folder, lower(title)) -> photoTakenTime epochs, for wanted keys only."""
    found = defaultdict(list)
    for z in sorted(ZIPS.glob("*.zip")):
        with zipfile.ZipFile(z) as zf:
            for info in zf.infolist():
                if not info.filename.endswith(".json"):
                    continue
                folder = str(PurePosixPath(info.filename).parent)
                if folder not in wanted:
                    continue
                try:
                    meta = json.loads(zf.read(info))
                    key = (folder, meta["title"].lower())
                    taken = int(meta["photoTakenTime"]["timestamp"])
                except (ValueError, KeyError, TypeError, zipfile.BadZipFile):
                    continue
                if key[1] in wanted[folder]:
                    found[key].append(taken)
    return found


def matches(taken, immich):
    for t in immich:
        d = abs(taken - t)
        k = round(d / 1800)
        if k <= MAX_TZ and abs(d - k * 1800) <= SLACK:
            return True
    return False


def main():
    report = Path(sys.argv[1] if len(sys.argv) > 1 else
                  os.path.expanduser("~/takeout-verify.tsv"))
    out_path = Path(sys.argv[2] if len(sys.argv) > 2 else
                    os.path.expanduser("~/takeout-same-name.tsv"))
    rows = [line.rstrip("\n").split("\t") for line in report.open()][1:]
    rows = [r for r in rows if r[2] == "yes" and r[0] != "bad-crc"]

    wanted = defaultdict(set)
    for r in rows:
        p = PurePosixPath(r[4])
        wanted[str(p.parent)].add(p.name.lower())
    side = sidecars(wanted)
    immich = immich_times({PurePosixPath(r[4]).name.lower() for r in rows})

    counts = defaultdict(int)
    with out_path.open("w") as out:
        out.write("verdict\ttaken_utc\tsha1\tsize\tzip\tentry\n")
        for r in rows:
            p = PurePosixPath(r[4])
            taken = side.get((str(p.parent), p.name.lower()), [])
            if not taken:
                verdict, when = "no-sidecar", ""
            else:
                # Several sidecars share a title when Takeout had two photos
                # of that name in one folder, and which one belongs to this
                # entry is not recorded; if only some match, say so.
                hit = [t for t in taken if matches(t, immich[p.name.lower()])]
                verdict = ("same-photo" if len(hit) == len(taken) else
                           "ambiguous" if hit else "different-photo")
                when = datetime.fromtimestamp((hit or taken)[0], timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
            counts[verdict] += 1
            out.write(f"{verdict}\t{when}\t" + "\t".join([r[0], r[1], r[3], r[4]]) + "\n")

    for v in ("same-photo", "different-photo", "ambiguous", "no-sidecar"):
        print(f"{v:16} {counts[v]}")
    print(f"report: {out_path}")


if __name__ == "__main__":
    main()
