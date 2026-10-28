#!/usr/bin/env python3
"""Make a grid collage from an Immich album.

    python3 -I services/immich/collage.py "navratri 2026 oju" [--cols 3]
        [--width 3240] [--gap 32] [--bg white] [--bg-photo IMG_6581.jpg]
        [--bg-blur 0] [--out collage.jpg] [--newest-first] [--upload]

Photos are placed oldest first, left to right, top to bottom. Nothing is
cropped: every photo in a row is scaled to the same height so the row fills
the width exactly, which keeps each photo whole whatever its shape. Images
come from Immich's JPEG preview (2560px long side), so HEIC - including
iPhone HEICs named .jpg - needs no decoder here. With --upload the collage
goes back into Immich and into the same album. --bg-photo (a file name or
asset id anywhere in the library) is stretched over the whole sheet so it
shows through the gaps instead of the plain --bg colour.
"""
import argparse
import io
import json
import sys
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageFilter, ImageOps

REPO = Path(__file__).resolve().parents[2]
SERVER = "http://localhost:2283/api"


def env(key):
    for line in (REPO / ".env").read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1]
    sys.exit(f"{key} not in .env")


KEY = env("IMMICH_API_KEY")


def api(path, body=None, raw=False, data=None, headers=None, method=None):
    h = {"x-api-key": KEY, **(headers or {})}
    if body is not None:
        data = json.dumps(body).encode()
        h["content-type"] = "application/json"
    req = urllib.request.Request(SERVER + path, data=data, headers=h,
                                 method=method or ("POST" if data else "GET"))
    with urllib.request.urlopen(req) as r:
        out = r.read()
    return out if raw else json.loads(out)


def album(name):
    for a in api("/albums"):
        if a["albumName"].lower() == name.lower():
            return a
    sys.exit(f"no album named {name!r}")


def assets(album_id):
    items, page = [], 1
    while page:
        res = api("/search/metadata", {"albumIds": [album_id], "type": "IMAGE",
                                       "size": 250, "page": page})["assets"]
        items += res["items"]
        page = res["nextPage"] and int(res["nextPage"])
    # leave out collages this script uploaded on an earlier run
    # (Immich 3 no longer returns deviceId, so go by the name it saves them as)
    items = [a for a in items if not a["originalFileName"].endswith("_collage.jpg")]
    return sorted(items, key=lambda a: a["localDateTime"])


def photo(asset):
    img = Image.open(io.BytesIO(
        api(f"/assets/{asset['id']}/thumbnail?size=preview", raw=True)))
    return ImageOps.exif_transpose(img).convert("RGB")


def find(name_or_id):
    try:
        return api(f"/assets/{uuid.UUID(name_or_id)}")
    except ValueError:
        hits = api("/search/metadata", {"originalFileName": name_or_id,
                                        "type": "IMAGE"})["assets"]["items"]
        if not hits:
            sys.exit(f"no photo named {name_or_id!r}")
        return hits[0]


def rows(photos, cols, width, gap):
    """Each row of `cols` photos at the one height that makes it `width` wide."""
    out = []
    for i in range(0, len(photos), cols):
        row = photos[i:i + cols]
        inner = width - gap * (len(row) + 1)
        h = inner / sum(p.width / p.height for p in row)
        if out and len(row) < cols:
            h = min(h, out[-1][0])  # a short last row stays the size of the others
        out.append((round(h), row))
    return out


def upload(path, album):
    name = album["albumName"].replace(" ", "_") + "_collage.jpg"  # what assets() skips
    boundary = uuid.uuid4().hex
    now = datetime.now(timezone.utc).isoformat()
    fields = {"deviceAssetId": f"collage-{name}-{now}", "deviceId": "collage.py",
              "fileCreatedAt": now, "fileModifiedAt": now}
    body = b"".join(
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
        for k, v in fields.items())
    body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"assetData\"; "
             f"filename=\"{name}\"\r\nContent-Type: image/jpeg\r\n\r\n").encode()
    body += path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    res = api("/assets", data=body,
              headers={"content-type": f"multipart/form-data; boundary={boundary}"})
    api(f"/albums/{album['id']}/assets", {"ids": [res["id"]]}, method="PUT")
    return res["id"]


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("album")
    p.add_argument("--cols", type=int, default=3)
    p.add_argument("--width", type=int, default=3240, help="collage width in pixels")
    p.add_argument("--gap", type=int, default=32, help="pixels between and around photos")
    p.add_argument("--bg", default="white")
    p.add_argument("--bg-photo", help="Immich photo (file name or id) behind the gaps")
    p.add_argument("--bg-blur", type=float, default=0, help="blur radius for --bg-photo")
    p.add_argument("--out", type=Path)
    p.add_argument("--newest-first", action="store_true")
    p.add_argument("--upload", action="store_true", help="add the collage to the album")
    a = p.parse_args()

    alb = album(a.album)
    items = assets(alb["id"])
    if a.newest_first:
        items.reverse()
    if not items:
        sys.exit("album has no photos")
    photos = []
    for i, asset in enumerate(items):
        print(f"{i + 1}/{len(items)} {asset['originalFileName']}", file=sys.stderr)
        photos.append(photo(asset))
    g, layout = a.gap, rows(photos, a.cols, a.width, a.gap)
    size = (a.width, sum(h + g for h, _ in layout) + g)
    sheet = Image.new("RGB", size, a.bg)
    if a.bg_photo:
        sheet = ImageOps.fit(photo(find(a.bg_photo)), size, Image.LANCZOS)
        if a.bg_blur:
            sheet = sheet.filter(ImageFilter.GaussianBlur(a.bg_blur))
    y = g
    for h, row in layout:
        x = g
        for p in row:
            w = round(p.width * h / p.height)
            sheet.paste(p.resize((w, h), Image.LANCZOS), (x, y))
            x += w + g
        y += h + g
    out = a.out or Path(f"{a.album.replace(' ', '_')}_collage.jpg")
    sheet.save(out, quality=92)
    print(out)
    if a.upload:
        print("uploaded", upload(out, alb))


if __name__ == "__main__":
    main()
