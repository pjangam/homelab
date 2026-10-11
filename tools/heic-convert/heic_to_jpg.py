#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10", "pillow-heif>=0.16"]
# ///
"""Convert HEIC/HEIF images to JPEG next to the original.

Usage:
  tools/heic-convert/heic_to_jpg.py PATH [PATH ...]   # files and/or directories (recursive)
  tools/heic-convert/heic_to_jpg.py --samba           # the samba shares (not albums)

Options:
  --delete-originals  remove the .heic once its .jpg is written and verified
  --quality N         JPEG quality (default 92)
  --dry-run           list what would be converted, write nothing

Keeps EXIF (date taken, GPS, camera), the ICC colour profile and the file's
mtime. Rotation is baked into the pixels, so EXIF Orientation is reset to 1.
An existing IMG_1.jpg is never overwritten; that file is skipped.

Needs uv (no sudo, no system packages): ImageMagick on xero can read HEIC but
drops all EXIF, which loses the photo dates.
"""
import argparse
import os
import sys
from pathlib import Path

from PIL import Image
from pillow_heif import register_heif_opener

register_heif_opener()

# Samba shares from docker-compose.yml, minus albums (served publicly by
# albums-gallery, leave its originals alone).
SAMBA_DIRS = ["/datapool/phone-uploads", "/datapool/documents"]
HEIC_EXTS = {".heic", ".heif"}
ORIENTATION_TAG = 0x0112


def find_heic(paths):
    for p in map(Path, paths):
        if p.is_dir():
            for root, _, files in os.walk(p):
                for f in sorted(files):
                    if Path(f).suffix.lower() in HEIC_EXTS:
                        yield Path(root) / f
        elif p.is_file() and p.suffix.lower() in HEIC_EXTS:
            yield p
        elif not p.exists():
            print(f"missing: {p}", file=sys.stderr)


def convert(src: Path, quality: int) -> Path | None:
    dst = src.with_suffix(".jpg")
    if dst.exists() or src.with_suffix(".jpeg").exists():
        return None
    with Image.open(src) as im:
        exif = im.getexif()
        exif[ORIENTATION_TAG] = 1
        kwargs = {"quality": quality, "exif": exif.tobytes()}
        if icc := im.info.get("icc_profile"):
            kwargs["icc_profile"] = icc
        tmp = dst.with_name(dst.name + ".part")
        im.convert("RGB").save(tmp, "JPEG", **kwargs)
    with Image.open(tmp) as check:
        check.verify()
    st = src.stat()
    os.utime(tmp, (st.st_atime, st.st_mtime))
    tmp.rename(dst)
    return dst


def main():
    ap = argparse.ArgumentParser(description="Convert HEIC/HEIF to JPEG")
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--samba", action="store_true", help="convert in the samba shares")
    ap.add_argument("--delete-originals", action="store_true")
    ap.add_argument("--quality", type=int, default=92)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    paths = args.paths + (SAMBA_DIRS if args.samba else [])
    if not paths:
        ap.error("give a file/directory or --samba")

    done = skipped = failed = 0
    for src in find_heic(paths):
        if args.dry_run:
            print(f"would convert: {src}")
            continue
        try:
            dst = convert(src, args.quality)
        except Exception as e:
            print(f"FAILED {src}: {e}", file=sys.stderr)
            failed += 1
            continue
        if dst is None:
            print(f"skip (jpg exists): {src}")
            skipped += 1
            continue
        print(f"ok: {dst}")
        done += 1
        if args.delete_originals:
            src.unlink()

    if not args.dry_run:
        print(f"\nconverted {done}, skipped {skipped}, failed {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
