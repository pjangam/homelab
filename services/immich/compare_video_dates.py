#!/usr/bin/env python3
"""Tell which local videos Immich already has under other bytes.

A video that is not in Immich by SHA-1 may still be there: phone backup
apps, Photos exports and Google Photos all re-encode. And a name proves
nothing either way, since iPhone and GoPro counters repeat (IMG_9033.MOV in
phone-uploads is from 2024, Immich's from 2026). So for each file this reads
its capture time and length with ffprobe (in the mwader/static-ffmpeg image)
and looks for an Immich video taken within 2 seconds of it whose length is
within a second. Only when the file's time has no UTC offset of its own (a
GoPro's creation_time is local time labelled UTC; an iPhone's
com.apple.quicktime.creationdate carries one) may it also be a whole number
of half hours off, up to 14h. GoPro clocks also drift and reset, and copies
via the GoPro app or Google get new times, so a video whose name starts with
the file's name stem (GOPR0004_1516366859406_high.MP4 for GOPR0004.MP4) and
whose length is within 0.15s also counts, whatever its time:

    python3 -I services/immich/compare_video_dates.py FILE...

Prints one line per file: in-immich (with the asset's name when it differs),
other-length (same moment, different length: a trimmed or another clip),
missing, no-date (ffprobe found no capture time) or not-video.
"""
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SLACK = 2            # seconds
MAX_TZ = 28          # half hours: 14h
VIDEO = {".mov", ".mp4", ".m4v", ".3gp", ".avi", ".mkv", ".mts"}


def env(key):
    for line in (REPO / ".env").read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1]
    sys.exit(f"{key} not in .env")


def immich_videos():
    sql = ('select a."originalFileName", a.duration, '
           'extract(epoch from coalesce(e."dateTimeOriginal", a."fileCreatedAt")) '
           'from asset a left join asset_exif e on e."assetId" = a.id '
           "where a.type = 'VIDEO' and a.\"deletedAt\" is null")
    out = subprocess.run(
        ["docker", "exec", "immich_postgres", "psql", "-U", env("DB_USERNAME"),
         "-d", env("DB_DATABASE_NAME"), "-AtF", "\t", "-c", sql],
        check=True, capture_output=True, text=True).stdout
    vids = []
    for line in out.splitlines():
        name, dur, ts = line.split("\t")
        vids.append((float(ts), int(dur) / 1000 if dur else None, name))
    return vids


def probe(path):
    """(capture epoch or None, whether the time had its own offset,
    duration seconds or None)."""
    out = subprocess.run(
        ["docker", "run", "--rm", "-v", f"{path.parent}:/d:ro",
         "--entrypoint", "/ffprobe", "mwader/static-ffmpeg", "-v", "error",
         "-show_entries", "format=duration:format_tags", "-of", "json",
         f"/d/{path.name}"], capture_output=True, text=True).stdout
    fmt = json.loads(out or "{}").get("format", {})
    tags = {k.lower(): v for k, v in fmt.get("tags", {}).items()}
    when, own_tz = None, False
    for key, fmt_s in (("com.apple.quicktime.creationdate", "%Y-%m-%dT%H:%M:%S%z"),
                       ("creation_time", None)):
        if key in tags:
            s = tags[key]
            when = (datetime.strptime(s, fmt_s) if fmt_s else
                    datetime.fromisoformat(s.replace("Z", "+00:00")))
            own_tz = bool(fmt_s)
            break
    dur = float(fmt["duration"]) if "duration" in fmt else None
    return (when.timestamp() if when else None), own_tz, dur


def tz_close(d, own_tz):
    if own_tz:
        return d <= SLACK
    k = round(d / 1800)
    return k <= MAX_TZ and abs(d - k * 1800) <= SLACK


def main():
    vids = immich_videos()
    for arg in sys.argv[1:]:
        path = Path(arg).resolve()
        if path.suffix.lower() not in VIDEO:
            print(f"not-video    {path}")
            continue
        taken, own_tz, dur = probe(path)
        if taken is None:
            print(f"no-date      {path}")
            continue
        when = datetime.fromtimestamp(taken, timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        near = [v for v in vids if tz_close(abs(v[0] - taken), own_tz)]
        same = [v for v in near if dur is None or v[1] is None or abs(v[1] - dur) <= 1]
        stem = path.stem.lower()
        same += [v for v in vids if v not in same and dur and v[1] is not None
                 and v[2].lower().startswith(stem) and abs(v[1] - dur) <= 0.15]
        if same:
            names = {v[2] for v in same}
            other = "" if path.name.lower() in {n.lower() for n in names} else \
                f" as {', '.join(sorted(names))}"
            print(f"in-immich    {when}  {path}{other}")
        elif near:
            print(f"other-length {when}  {path}  ({dur:.0f}s here; Immich: "
                  + ", ".join(f"{v[2]} {v[1]:.0f}s" for v in near if v[1] is not None) + ")")
        else:
            print(f"missing      {when}  {path}  ({dur:.0f}s)" if dur else
                  f"missing      {when}  {path}")


if __name__ == "__main__":
    main()
