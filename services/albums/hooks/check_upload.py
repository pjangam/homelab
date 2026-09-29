#!/usr/bin/env python3
"""copyparty upload hooks for the album inbox (services/albums/README.md).

Two modes, both run inside the albums-gallery container. copyparty cannot pass
a hook arguments, so the mode is the name it is invoked by (both are symlinks
to this file):

  pre_upload.py  <json>   xbu (before upload): reject anything whose
                                extension is not a photo/video format.
  post_upload.py <json>   xau (after upload): the extension can lie, so
                                check the file's first bytes are a real photo
                                or video container; delete it if not. Then log
                                who uploaded what to /inbox/.upload-log.tsv,
                                which review.sh reads.

Exit non-zero = copyparty refuses the upload (both hooks run with the c flag).
The inbox is never shown to viewers, so this is defence in depth: nothing an
uploader sends reaches the album until review.sh approves it.
"""
import json
import os
import sys
import time

ALLOWED = {"jpg", "jpeg", "png", "heic", "heif", "webp", "gif",
           "mov", "mp4", "m4v", "3gp"}
LOG = "/inbox/.upload-log.tsv"


def ext_of(name):
    return name.rsplit(".", 1)[-1].lower() if "." in name else ""


def real_media(path):
    with open(path, "rb") as f:
        head = f.read(16)
    return (head[:3] == b"\xff\xd8\xff"                      # JPEG
            or head[:8] == b"\x89PNG\r\n\x1a\n"               # PNG
            or head[:6] in (b"GIF87a", b"GIF89a")             # GIF
            or (head[:4] == b"RIFF" and head[8:12] == b"WEBP")
            or head[4:8] == b"ftyp")                          # HEIC/HEIF/MP4/MOV/M4V/3GP


def main():
    mode = "pre" if os.path.basename(sys.argv[0]).startswith("pre") else "post"
    info = json.loads(sys.argv[1])
    path = info.get("ap") or info.get("vp") or ""
    name = os.path.basename(path)
    if ext_of(name) not in ALLOWED:
        print(f"rejected {name!r}: not a photo/video type", file=sys.stderr)
        return 1
    if mode == "pre":
        return 0

    ok = os.path.isfile(path) and real_media(path)
    if not ok:
        print(f"rejected {name!r}: contents are not a photo/video", file=sys.stderr)
        try:
            os.remove(path)
        except OSError:
            pass
    with open(LOG, "a") as f:
        f.write("\t".join([time.strftime("%Y-%m-%d %H:%M:%S"),
                           str(info.get("user", "?")), str(info.get("ip", "?")),
                           name, str(info.get("sz", "?")),
                           "ok" if ok else "REJECTED-deleted"]) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
