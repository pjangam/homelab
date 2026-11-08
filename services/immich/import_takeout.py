#!/usr/bin/env python3
"""Import a whole Google Takeout export into one user's Immich library.

Run on xero, in tmux or detached (README: "Importing a Google Takeout export"):

    python3 -I services/immich/import_takeout.py DIR --dry-run
    python3 -I services/immich/import_takeout.py DIR \
        --key-var IMMICH_API_KEY_BHAKTI --as her@email --limit 5

DIR holds the takeout zips. --key-var names a variable in the environment or
.env holding an API key made BY THE USER WHOSE LIBRARY IT IS, and --as must
match that key's owner (name or email): the import stops before uploading
anything if it does not, because a wrong key puts the photos in the wrong
library with nothing to show for it until someone looks.

What it does:
- Reads only the zips' file lists and the small JSON files first, so a dry run
  is cheap. Takeout repeats a photo once per album; each is uploaded once.
- Streams each file from its zip straight to /api/assets, one at a time.
  Nothing is extracted, which spares the Kingston SSD a write and a delete.
- Uses Takeout's JSON for the capture date (Immich prefers the file's own
  EXIF and falls back to this), favourite and archived flags and the original
  filename. Photos Google has in the bin are left out.
- Recreates albums at the end. Adding to an album that exists is harmless.
- Caps throughput (--max-mb-per-s) and waits while the SSD or CPU is hot, or
  while Immich is down (the load guard stops it when xero is struggling).
- Records each uploaded file in DIR/import-state.jsonl: re-running carries on.
  Failures are retried on the next run and listed in DIR/import-failures.tsv.

Not imported: Google's descriptions and locations added in Google Photos.
A location that is in the file's EXIF is read by Immich as usual.
Check the result with verify_takeout.py --dir DIR --owner EMAIL.

Not immich-go: 0.32 cannot read Immich 3.3's asset list (simulot/immich-go#1442).
"""
import argparse
import collections
import datetime
import glob
import http.client
import json
import os
import posixpath
import re
import sys
import time
import uuid
import zipfile
from pathlib import Path
from urllib.parse import quote

REPO = Path(__file__).resolve().parents[2]
CHUNK = 1 << 20
ATTEMPTS = 5
RETRY_WAIT = float(os.environ.get("RETRY_WAIT", 30))
TEMP_POLL = float(os.environ.get("TEMP_POLL", 15))
SSD_HOT, SSD_OK = 70, 62   # same limits as ml_backlog.sh; the SA400 is rated 70
CPU_HOT, CPU_OK = 85, 70
MIN_FREE_GB = float(os.environ.get("MIN_FREE_GB", 50))  # the database lives on this pool too
SUPPLEMENTAL = ".supplemental-metadata"
SPECIAL_FOLDERS = {"archive", "bin", "trash", "untitled"}
YEAR_FOLDER = re.compile(r"^Photos from \d{4}$")


def log(msg):
    print(f"{datetime.datetime.now():%F %T} {msg}", flush=True)


# --- Takeout's sidecar names -------------------------------------------------
# For IMG.jpg Google has written, depending on the year of the export and the
# length of the name: IMG.jpg.json, IMG.jpg.supplemental-metadata.json, the
# same cut off at 46 characters (IMG.jpg.supplemen.json), and for a second file
# of that name IMG(1).jpg with IMG.jpg(1).json or
# IMG.jpg.supplemental-metadata(1).json. IMG-edited.jpg shares the original's,
# and the video half of a Live Photo has none of its own.

def split_counter(stem):
    m = re.match(r"^(.*)\((\d+)\)$", stem)
    return (m[1], m[2]) if m else (stem, "")


def strip_supplemental(stem):
    for n in range(len(SUPPLEMENTAL), 0, -1):
        if stem.endswith(SUPPLEMENTAL[:n]):
            return stem[:-n]
    return stem


class Sidecars:
    """The JSON files of one folder, and the lookup from a media file to its."""

    def __init__(self):
        self.by_name, self.by_stem, self.by_title = {}, {}, {}
        self.names = []

    def add(self, filename, data):
        stem, counter = split_counter(filename[:-len(".json")])
        name = strip_supplemental(stem)
        self.by_name.setdefault((name, counter), data)
        self.by_stem.setdefault((posixpath.splitext(name)[0], counter), data)
        title = data.get("title")
        if isinstance(title, str):
            self.by_title.setdefault(title, data)
        self.names.append((stem, counter, data))

    def find(self, basename):
        stem, ext = posixpath.splitext(basename)
        base, counter = split_counter(stem)
        unedited = re.sub(r"-edited$", "", base)
        for key in ((basename, ""), (base + ext, counter), (unedited + ext, counter)):
            if key in self.by_name:
                return self.by_name[key]
        for title in (basename, base + ext, unedited + ext):
            if title in self.by_title:
                return self.by_title[title]
        # Names Google cut short. Only long ones, so "IMG" never matches "IMG_1".
        for name, c, data in self.names:
            if c == counter and len(name) >= 30 and (unedited + ext).startswith(name):
                return data
        return self.by_stem.get((unedited, counter))  # a Live Photo's video


# --- What is in the zips -----------------------------------------------------

Entry = collections.namedtuple("Entry", "zip info dir base")


class Item:
    """One distinct file, with every place Takeout put a copy of it."""

    def __init__(self, key):
        self.key, self.entries, self.sidecars = key, [], []

    @property
    def trashed(self):
        return bool(self.sidecars) and all(s.get("trashed") for s in self.sidecars)

    @property
    def favorite(self):
        return any(s.get("favorited") for s in self.sidecars)

    @property
    def archived(self):
        return any(s.get("archived") for s in self.sidecars)

    def taken(self):
        for s in self.sidecars:
            try:
                ts = int(s["photoTakenTime"]["timestamp"])
            except (KeyError, TypeError, ValueError):
                continue
            if ts > 0:
                return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc)
        when = datetime.datetime(*self.entries[0].info.date_time)
        return when.replace(tzinfo=datetime.timezone.utc)

    def filename(self):
        base = self.entries[0].base
        for s in self.sidecars:
            title = s.get("title")
            if isinstance(title, str) and title:
                title = title.replace("/", "_")
                if posixpath.splitext(title)[1].lower() == posixpath.splitext(base)[1].lower():
                    return title
        return base


def is_album(folder, title):
    name = posixpath.basename(folder)
    return not (YEAR_FOLDER.match(name) or YEAR_FOLDER.match(title)
                or name.lower() in SPECIAL_FOLDERS or not title.strip())


def read_takeout(zip_paths):
    """Returns (items by key, {album title: set of item keys}, open ZipFiles)."""
    media, folders, album_dirs, zips, unreadable = [], {}, {}, {}, 0
    for path in zip_paths:
        zf = zips[path.name] = zipfile.ZipFile(path)
        for info in sorted(zf.infolist(), key=lambda i: i.header_offset):
            if info.is_dir():
                continue
            folder, base = posixpath.split(info.filename)
            low = base.lower()
            if low.endswith(".html"):
                continue
            if not low.endswith(".json"):
                media.append(Entry(path.name, info, folder, base))
                continue
            try:
                data = json.loads(zf.read(info))
            except (ValueError, zipfile.BadZipFile):
                unreadable += 1
                continue
            if not isinstance(data, dict):
                continue
            if "photoTakenTime" in data:
                folders.setdefault(folder, Sidecars()).add(base, data)
            elif isinstance(data.get("title"), str) and is_album(folder, data["title"]):
                album_dirs[folder] = data["title"]
    if unreadable:
        log(f"{unreadable} JSON files could not be read; those photos use the zip's date")

    items, albums = {}, collections.defaultdict(set)
    for e in media:
        # Same name, size and CRC: the same file. A file under two names is
        # simply sent twice, and Immich answers "duplicate" with the same id.
        key = f"{e.info.CRC:08x}:{e.info.file_size}:{e.base}"
        item = items.setdefault(key, Item(key))
        item.entries.append(e)
        sidecar = folders[e.dir].find(e.base) if e.dir in folders else None
        if sidecar:
            item.sidecars.append(sidecar)
        if e.dir in album_dirs:
            albums[album_dirs[e.dir]].add(key)
    return items, albums, zips


def summarise(items, albums):
    wanted = [i for i in items.values() if not i.trashed]
    bytes_ = sum(i.entries[0].info.file_size for i in wanted)
    bare = sorted(i.entries[0].info.filename for i in wanted if not i.sidecars)
    print(f"distinct files:     {len(items)}")
    print(f"to import:          {len(wanted)} ({bytes_ / 1e9:.1f} GB)")
    print(f"in Google's bin:    {len(items) - len(wanted)} (left out)")
    print(f"favourites:         {sum(i.favorite for i in wanted)}")
    print(f"archived:           {sum(i.archived for i in wanted)}")
    print(f"no JSON matched:    {len(bare)} (these use the zip's date if they have no EXIF)")
    for name in bare[:20]:
        print(f"    {name}")
    if len(bare) > 20:
        print(f"    ... and {len(bare) - 20} more")
    print(f"albums:             {len(albums)}")
    for title in sorted(albums):
        print(f"    {title}: {len(albums[title])}")


# --- Immich ------------------------------------------------------------------

class Fatal(Exception):
    pass


class Immich:
    def __init__(self, server, key):
        self.host, self.key = server.split("://", 1)[1].rstrip("/"), key

    def connect(self):
        return http.client.HTTPConnection(self.host, timeout=300)

    def api(self, method, path, body=None):
        conn = self.connect()
        try:
            data = None if body is None else json.dumps(body)
            conn.request(method, "/api" + path, data, {
                "x-api-key": self.key, "Accept": "application/json",
                "Content-Type": "application/json"})
            resp = conn.getresponse()
            text = resp.read()
        finally:
            conn.close()
        if resp.status >= 300:
            raise Fatal(f"{method} {path}: HTTP {resp.status}: {text[:300]!r}")
        return json.loads(text) if text else None

    def alive(self):
        conn = self.connect()
        try:
            conn.request("GET", "/api/server/ping")
            return conn.getresponse().status == 200
        except (OSError, http.client.HTTPException):
            return False
        finally:
            conn.close()

    def upload(self, zf, item, max_rate):
        """Streams one file; returns (HTTP status, response body)."""
        info = item.entries[0].info
        when = item.taken().strftime("%Y-%m-%dT%H:%M:%S.000Z")
        fields = {"fileCreatedAt": when, "fileModifiedAt": when, "filename": item.filename()}
        if item.favorite:
            fields["isFavorite"] = "true"
        if item.archived:
            fields["visibility"] = "archive"
        boundary = uuid.uuid4().hex
        head = b"".join(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
            for k, v in fields.items())
        name = quote(item.entries[0].base, safe=" ()-_.,'")
        head += (f'--{boundary}\r\nContent-Disposition: form-data; name="assetData"; '
                 f'filename="{name}"\r\n'
                 "Content-Type: application/octet-stream\r\n\r\n").encode()
        tail = f"\r\n--{boundary}--\r\n".encode()

        conn = self.connect()
        try:
            conn.putrequest("POST", "/api/assets")
            conn.putheader("x-api-key", self.key)
            conn.putheader("Accept", "application/json")
            conn.putheader("Content-Type", f"multipart/form-data; boundary={boundary}")
            conn.putheader("Content-Length", str(len(head) + info.file_size + len(tail)))
            conn.endheaders()
            conn.send(head)
            start, sent = time.monotonic(), 0
            with zf.open(info) as f:   # a bad CRC raises here and drops the request
                while chunk := f.read(CHUNK):
                    conn.send(chunk)
                    sent += len(chunk)
                    ahead = sent / max_rate - (time.monotonic() - start)
                    if ahead > 0:
                        time.sleep(ahead)
            conn.send(tail)
            resp = conn.getresponse()
            return resp.status, resp.read()
        finally:
            conn.close()


# --- Staying cool ------------------------------------------------------------

def sensor(env, pattern_files):
    if os.environ.get(env):
        return os.environ[env]
    return pattern_files() or None


def find_ssd_sensor():
    for model in glob.glob("/sys/block/sd*/device/model"):
        if "KINGSTON" in Path(model).read_text():
            found = glob.glob(str(Path(model).parent / "hwmon/hwmon*/temp1_input"))
            if found:
                return found[0]
    return None


def find_cpu_sensor():
    for zone in glob.glob("/sys/class/thermal/thermal_zone*"):
        if Path(zone, "type").read_text().strip() == "x86_pkg_temp":
            return f"{zone}/temp"
    return None


def read_temp(path):
    try:
        return int(Path(path).read_text()) / 1000
    except (OSError, ValueError):
        return 0     # a failed read must not hold the import forever


class Thermals:
    def __init__(self):
        self.ssd = sensor("SSD_TEMP_FILE", find_ssd_sensor)
        self.cpu = sensor("CPU_TEMP_FILE", find_cpu_sensor)
        if not (self.ssd and self.cpu):
            raise Fatal("temperature sensors not found")

    def wait(self):
        ssd, cpu = read_temp(self.ssd), read_temp(self.cpu)
        if ssd < SSD_HOT and cpu < CPU_HOT:
            return
        log(f"pausing: SSD {ssd:.0f}C, CPU {cpu:.0f}C")
        while ssd >= SSD_OK or cpu >= CPU_OK:
            time.sleep(TEMP_POLL)
            ssd, cpu = read_temp(self.ssd), read_temp(self.cpu)
        log(f"resuming: SSD {ssd:.0f}C, CPU {cpu:.0f}C")


# --- The run -----------------------------------------------------------------

def api_key(var):
    if os.environ.get(var):
        return os.environ[var]
    env_file = REPO / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            if line.startswith(var + "="):
                return line.split("=", 1)[1].strip()
    raise Fatal(f"{var} is not in the environment or .env")


def wait_for_immich(immich):
    if immich.alive():
        return
    log("Immich is not answering; waiting for it (is the load guard holding it?)")
    while not immich.alive():
        time.sleep(RETRY_WAIT)
    log("Immich is back")


def load_state(path):
    done = {}
    if path.exists():
        for line in path.read_text().splitlines():
            row = json.loads(line)
            done[row["key"]] = row["id"]
    return done


def send(immich, zf, item, thermals, max_rate):
    """Returns (asset id, status, None) or (None, None, why it failed)."""
    why = "no attempt made"
    for attempt in range(1, ATTEMPTS + 1):
        thermals.wait()
        try:
            code, body = immich.upload(zf, item, max_rate)
        except zipfile.BadZipFile as e:
            return None, None, f"damaged in the zip: {e}"
        except (OSError, http.client.HTTPException) as e:
            why = f"connection: {e}"
            wait_for_immich(immich)
            continue
        if code in (401, 403):
            raise Fatal(f"Immich refused the API key: HTTP {code}: {body[:300]!r}")
        if code in (200, 201):
            try:
                row = json.loads(body)
                return row["id"], row["status"], None
            except (ValueError, KeyError) as e:
                return None, None, f"unexpected response: {e}: {body[:200]!r}"
        why = f"HTTP {code}: {body[:200].decode(errors='replace')}"
        if code < 500 and code != 429:
            return None, None, why
        log(f"{item.entries[0].base}: {why}; try {attempt}/{ATTEMPTS}")
        time.sleep(RETRY_WAIT * attempt)
        wait_for_immich(immich)
    return None, None, why


def make_albums(immich, albums, done):
    existing = {a["albumName"]: a["id"] for a in immich.api("GET", "/albums")}
    for title in sorted(albums):
        ids = sorted({done[k] for k in albums[title] if k in done})
        if not ids:
            continue
        album = existing.get(title)
        if album is None:
            album = immich.api("POST", "/albums", {"albumName": title})["id"]
            existing[title] = album
        for start in range(0, len(ids), 500):
            immich.api("PUT", f"/albums/{album}/assets", {"ids": ids[start:start + 500]})
        log(f"album {title}: {len(ids)} of {len(albums[title])} files")


def run(args):
    folder = Path(args.dir)
    zip_paths = sorted(folder.glob("*.zip"))
    if not zip_paths:
        raise Fatal(f"no zips in {folder}")
    log(f"reading {len(zip_paths)} zips")
    items, albums, zips = read_takeout(zip_paths)
    if args.dry_run:
        summarise(items, albums)
        return 0

    immich = Immich(args.server, api_key(args.key_var))
    me = immich.api("GET", "/users/me")
    if args.expect.lower() not in (me["name"].lower(), me["email"].lower()):
        raise Fatal(f"this key belongs to {me['name']} <{me['email']}>, not {args.expect}")
    log(f"importing as {me['name']} <{me['email']}>")
    thermals = Thermals()

    state_path = folder / "import-state.jsonl"
    done = load_state(state_path)
    todo = [i for i in items.values() if not i.trashed and i.key not in done]
    log(f"{len(done)} already done, {len(todo)} to go")
    if args.limit:
        todo = todo[:args.limit]

    counts, failures = collections.Counter(), []
    max_rate = args.max_mb_per_s * 1e6
    with state_path.open("a") as state:
        for n, item in enumerate(todo, 1):
            stat = os.statvfs(folder)
            if stat.f_bavail * stat.f_frsize < MIN_FREE_GB * 1e9:
                raise Fatal(f"under {MIN_FREE_GB} GB free on {folder}; stopping")
            first = item.entries[0]
            asset, status, why = send(immich, zips[first.zip], item, thermals, max_rate)
            if asset is None:
                counts["failed"] += 1
                failures.append((first.zip, first.info.filename, why))
                log(f"FAILED {first.info.filename}: {why}")
            else:
                counts[status] += 1
                done[item.key] = asset
                state.write(json.dumps({"key": item.key, "id": asset, "status": status}) + "\n")
                state.flush()
            if n % 100 == 0 or n == len(todo):
                log(f"{n}/{len(todo)} {dict(counts)}")

    (folder / "import-failures.tsv").write_text(
        "".join("\t".join(row) + "\n" for row in failures))
    make_albums(immich, albums, done)
    log(f"finished: {dict(counts)}; see import-failures.tsv for any failures")
    return 1 if failures else 0


def main():
    p = argparse.ArgumentParser(description="Import a Google Takeout into an Immich user's library")
    p.add_argument("dir", help="folder holding the takeout zips")
    p.add_argument("--dry-run", action="store_true", help="report what is in the zips, upload nothing")
    p.add_argument("--key-var", help="variable (environment or .env) holding that user's API key")
    p.add_argument("--as", dest="expect", help="name or email the key must belong to")
    p.add_argument("--limit", type=int, default=0, help="stop after this many files, to try it out")
    p.add_argument("--max-mb-per-s", type=float, default=20, help="upload speed cap (default 20)")
    p.add_argument("--server", default="http://localhost:2283")
    args = p.parse_args()
    if not args.dry_run and not (args.key_var and args.expect):
        p.error("--key-var and --as are required unless --dry-run")
    try:
        return run(args)
    except Fatal as e:
        log(f"STOPPED: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
