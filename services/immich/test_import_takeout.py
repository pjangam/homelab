#!/usr/bin/env python3
"""Tests import_takeout.py against a fake Immich and a made-up Takeout.

    python3 -I services/immich/test_import_takeout.py

Covers: sidecar name variants, one upload per file despite album copies, the
bytes arriving intact, dates/favourite/archive/bin, albums, re-runs, the
owner check, retry after a 500, pausing while hot, and a damaged zip entry.
"""
import email
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "import_takeout.py"
GP = "Takeout/Google Photos"
YEAR = f"{GP}/Photos from 2019"
TRIP = f"{GP}/Goa Trip"
failures = 0


def check(name, ok, detail=""):
    global failures
    print(("ok   " if ok else "FAIL ") + name + (f" -- {detail}" if not ok else ""))
    failures += not ok


class Fake:
    def __init__(self):
        self.uploads, self.albums, self.by_sum = [], {}, {}
        self.fail_next, self.me_email = 0, "her-login"


def handler(fake):
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def reply(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def body(self):
            return self.rfile.read(int(self.headers.get("Content-Length", 0)))

        def do_GET(self):
            if self.path == "/api/server/ping":
                self.reply(200, {"res": "pong"})
            elif self.path == "/api/users/me":
                self.reply(200, {"name": "Her", "email": fake.me_email})
            elif self.path == "/api/albums":
                self.reply(200, [{"albumName": t, "id": t.replace(" ", "_")} for t in fake.albums])

        def do_POST(self):
            raw = self.body()
            if len(raw) < int(self.headers["Content-Length"]):
                self.close_connection = True   # client gave up mid-upload: nothing is stored
                return
            if self.path == "/api/albums":
                title = json.loads(raw)["albumName"]
                fake.albums[title] = set()
                return self.reply(201, {"id": title.replace(" ", "_")})
            if fake.fail_next:
                fake.fail_next -= 1
                return self.reply(500, {"message": "boom"})
            msg = email.message_from_bytes(
                b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + raw)
            parts = {p.get_param("name", header="content-disposition"): p for p in msg.get_payload()}
            fields = {k: p.get_payload(decode=True).decode()
                      for k, p in parts.items() if k != "assetData"}
            data = parts["assetData"].get_payload(decode=True)
            fields["data"] = data
            known = fake.by_sum.get(data)
            if known:
                return self.reply(200, {"id": known, "status": "duplicate"})
            fake.by_sum[data] = f"id{len(fake.by_sum)}"
            fake.uploads.append(fields)
            self.reply(201, {"id": fake.by_sum[data], "status": "created"})

        def do_PUT(self):
            title = self.path.split("/")[3].replace("_", " ")
            fake.albums[title] |= set(json.loads(self.body())["ids"])
            self.reply(200, [])

    return H


def sidecar(ts, **extra):
    return json.dumps({"title": extra.pop("title", "x"), "photoTakenTime": {"timestamp": str(ts)}, **extra})


LONG = "a-very-long-photo-name-that-google-truncates-x"
FILES = {
    f"{YEAR}/plain.jpg": b"plain-bytes",
    f"{YEAR}/plain.jpg.json": sidecar(1000000000, title="plain.jpg"),
    f"{TRIP}/plain.jpg": b"plain-bytes",                       # album copy
    f"{TRIP}/plain.jpg.json": sidecar(1000000000, title="plain.jpg", favorited=True),
    f"{TRIP}/metadata.json": json.dumps({"title": "Goa Trip"}),
    f"{YEAR}/metadata.json": json.dumps({"title": "Photos from 2019"}),
    f"{YEAR}/new.jpg": b"new-bytes",
    f"{YEAR}/new.jpg.supplemental-metadata.json": sidecar(1100000000, title="new.jpg"),
    f"{YEAR}/cut.jpg": b"cut-bytes",
    f"{YEAR}/cut.jpg.supplemen.json": sidecar(1200000000, title="other-title.jpg"),
    f"{YEAR}/dup.jpg": b"dup-zero",
    f"{YEAR}/dup.jpg.json": sidecar(1300000000, title="dup.jpg"),
    f"{YEAR}/dup(1).jpg": b"dup-one",
    f"{YEAR}/dup.jpg.supplemental-metadata(1).json": sidecar(1310000000, title="dup.jpg"),
    f"{YEAR}/edit.jpg": b"edit-orig",
    f"{YEAR}/edit-edited.jpg": b"edit-changed",
    f"{YEAR}/edit.jpg.json": sidecar(1400000000, title="edit.jpg"),
    f"{YEAR}/live.HEIC": b"live-still",
    f"{YEAR}/live.MP4": b"live-video",
    f"{YEAR}/live.HEIC.json": sidecar(1500000000, title="live.HEIC"),
    f"{YEAR}/{LONG}.jpg": b"long-bytes",
    f"{YEAR}/{LONG[:40]}.json": sidecar(1510000000, title=f"{LONG}.jpg"),
    f"{YEAR}/kept.jpg": b"kept-bytes",
    f"{YEAR}/kept.jpg.json": sidecar(1520000000, title="kept.jpg", archived=True),
    f"{GP}/Bin/gone.jpg": b"gone-bytes",
    f"{GP}/Bin/gone.jpg.json": sidecar(1530000000, title="gone.jpg", trashed=True),
    f"{YEAR}/bare.jpg": b"bare-bytes",
    f"{GP}/shared_album_comments.json": "[]",
    "Takeout/archive_browser.html": b"<html>",
}


def write_zips(folder):
    # A second zip, so a file and its JSON can be in different parts.
    items = list(FILES.items())
    with zipfile.ZipFile(folder / "takeout-001.zip", "w") as a, \
         zipfile.ZipFile(folder / "takeout-002.zip", "w") as b:
        for i, (name, content) in enumerate(items):
            info = zipfile.ZipInfo(name, (2021, 3, 4, 5, 6, 8))
            (a if i % 2 else b).writestr(info, content)


def by_data(fake, data):
    return next((u for u in fake.uploads if u["data"] == data), None)


def main():
    fake = Fake()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler(fake))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}"

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        zips = tmp / "zips"
        zips.mkdir()
        write_zips(zips)
        ssd, cpu = tmp / "ssd", tmp / "cpu"
        ssd.write_text("40000")
        cpu.write_text("40000")
        env = {**os.environ, "SECRET": "k", "SSD_TEMP_FILE": str(ssd), "CPU_TEMP_FILE": str(cpu),
               "RETRY_WAIT": "0.05", "TEMP_POLL": "0.05", "MIN_FREE_GB": "0"}

        def importer(*extra, expect="her-login"):
            return subprocess.run(
                [sys.executable, "-I", str(SCRIPT), str(zips), "--server", url,
                 "--key-var", "SECRET", "--as", expect, "--max-mb-per-s", "1000", *extra],
                env=env, capture_output=True, text=True)

        dry = importer("--dry-run")
        check("dry run uploads nothing", dry.returncode == 0 and not fake.uploads, dry.stdout + dry.stderr)
        check("dry run names the album, not the year or bin",
              "Goa Trip: 1" in dry.stdout and "Photos from 2019:" not in dry.stdout and "Bin:" not in dry.stdout,
              dry.stdout)
        check("dry run counts the bin", "in Google's bin:    1" in dry.stdout, dry.stdout)

        wrong = importer(expect="someone-else")
        check("wrong owner stops before uploading", wrong.returncode == 2 and not fake.uploads, wrong.stdout)

        fake.fail_next = 1                 # the first upload gets a 500
        run = importer()
        check("import succeeds", run.returncode == 0, run.stdout + run.stderr)
        check("each distinct file once", len(fake.uploads) == 12, [u["filename"] for u in fake.uploads])

        expected = {
            b"plain-bytes": 1000000000, b"new-bytes": 1100000000, b"cut-bytes": 1200000000,
            b"dup-zero": 1300000000, b"dup-one": 1310000000, b"edit-orig": 1400000000,
            b"edit-changed": 1400000000, b"live-still": 1500000000, b"live-video": 1500000000,
            b"long-bytes": 1510000000, b"kept-bytes": 1520000000,
        }
        for data, ts in expected.items():
            u = by_data(fake, data)
            when = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(ts))
            check(f"date of {data.decode()}", u and u["fileCreatedAt"] == when, u)
        check("favourite from the album's JSON", by_data(fake, b"plain-bytes").get("isFavorite") == "true")
        check("not everything is a favourite", "isFavorite" not in by_data(fake, b"new-bytes"))
        check("archived stays archived", by_data(fake, b"kept-bytes").get("visibility") == "archive")
        check("bin is left out", by_data(fake, b"gone-bytes") is None)
        check("JSON title used as the name", by_data(fake, b"plain-bytes")["filename"] == "plain.jpg")
        bare = by_data(fake, b"bare-bytes")
        check("file with no JSON uses the zip's date", bare and bare["fileCreatedAt"] == "2021-03-04T05:06:08.000Z", bare)
        check("album has its photo", fake.albums.get("Goa Trip") == {fake.by_sum[b"plain-bytes"]}, fake.albums)

        before = len(fake.uploads)
        again = importer()
        check("re-run uploads nothing", again.returncode == 0 and len(fake.uploads) == before, again.stdout)
        check("re-run leaves one album", list(fake.albums) == ["Goa Trip"], fake.albums)

        # Hot SSD: nothing goes up until it cools.
        (zips / "import-state.jsonl").unlink()
        fake.uploads.clear()
        fake.by_sum.clear()
        ssd.write_text("75000")
        env["TEMP_POLL"] = "0.05"
        proc = subprocess.Popen(
            [sys.executable, "-I", str(SCRIPT), str(zips), "--server", url, "--key-var", "SECRET",
             "--as", "her-login", "--max-mb-per-s", "1000"],
            env=env, stdout=subprocess.PIPE, text=True)
        time.sleep(1.5)
        check("waits while the SSD is hot", not fake.uploads, fake.uploads)
        ssd.write_text("60000")
        proc.communicate(timeout=30)
        check("carries on once cool", len(fake.uploads) == 12, len(fake.uploads))

        # One damaged entry: reported, the rest still go up.
        for f in zips.glob("*"):
            f.unlink()
        fake.uploads.clear()
        fake.by_sum.clear()
        zip_path = zips / "takeout-001.zip"
        with zipfile.ZipFile(zip_path, "w") as z:
            z.writestr("Takeout/Google Photos/Photos from 2019/bad.jpg", b"DAMAGE-ME-PLEASE")
            z.writestr("Takeout/Google Photos/Photos from 2019/good.jpg", b"good-bytes")
        raw = zip_path.read_bytes().replace(b"DAMAGE-ME-PLEASE", b"DAMAGED-BY-A-BIT")
        zip_path.write_bytes(raw)
        bad = importer()
        report = (zips / "import-failures.tsv").read_text()
        check("damaged file fails the run", bad.returncode == 1, bad.stdout + bad.stderr)
        check("damaged file reported", "bad.jpg" in report and "damaged" in report, report)
        check("damaged file never stored", by_data(fake, b"DAMAGED-BY-A-BIT") is None)
        check("the rest still imported", by_data(fake, b"good-bytes") is not None)

    server.shutdown()
    print("all passed" if not failures else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
