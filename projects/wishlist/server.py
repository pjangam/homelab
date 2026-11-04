#!/usr/bin/env python3
"""Wishlist: a priority-ordered list of the expensive things to buy, with a
rough price each. Serves one page and a tiny JSON API under /wishlist/*.

Storage is one JSON file (DATA_FILE), rewritten whole on every save. The list is
tens of items, so a database would only add something to operate; the file is
human-readable, diffable, and trivially backed up.

Concurrency: the page sends back the `version` it loaded with every save. If the
file has moved on since (the phone saved while the laptop had the page open),
the save is refused with 409 and the page reloads instead of silently
overwriting the other device's edit.

Stdlib only, so the container is a stock python image with no build step.
"""
import json
import os
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = "0.0.0.0"
PORT = int(os.environ.get("PORT", "8128"))
PREFIX = "/wishlist"
WEB_DIR = Path(__file__).parent / "web"
DATA_FILE = Path(os.environ.get("DATA_FILE", Path(__file__).parent / "data" / "wishlist.json"))
MAX_BODY = 1_000_000

LOCK = threading.Lock()
EMPTY = {"version": 0, "monthlyBudget": None, "items": []}


def load():
    try:
        return json.loads(DATA_FILE.read_text())
    except FileNotFoundError:
        return dict(EMPTY)


def save(doc):
    """Atomic replace, keeping the previous file as .bak - one bad save (a bug
    in the page, a fat-fingered delete) is then a `cp` away from undone."""
    DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
    if DATA_FILE.exists():
        os.replace(DATA_FILE, DATA_FILE.with_suffix(".json.bak"))
    fd, tmp = tempfile.mkstemp(dir=DATA_FILE.parent, prefix=".wishlist-")
    with os.fdopen(fd, "w") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, DATA_FILE)


def clean_item(raw):
    """Keep only known fields, with the types the page expects. Anything else
    the client sends is dropped rather than stored."""
    if not isinstance(raw, dict) or not str(raw.get("name", "")).strip():
        raise ValueError("every item needs a name")
    price = raw.get("price")
    if price in ("", None):
        price = None
    else:
        price = float(price)
        if price < 0:
            raise ValueError("price cannot be negative")
    return {
        "id": str(raw.get("id") or f"{time.time_ns():x}"),
        "name": str(raw["name"]).strip()[:200],
        "price": price,
        "notes": str(raw.get("notes") or "").strip()[:2000],
        "link": str(raw.get("link") or "").strip()[:1000],
        "added": str(raw.get("added") or time.strftime("%Y-%m-%d")),
        "bought": str(raw["bought"]) if raw.get("bought") else None,
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "wishlist/1"

    def log_message(self, fmt, *args):  # quieter than the default, still in `docker logs`
        if not self.path.endswith("/api/health"):
            super().log_message(fmt, *args)

    def send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == PREFIX:
            self.send_response(301)
            self.send_header("Location", PREFIX + "/")
            self.end_headers()
        elif path == PREFIX + "/api/list":
            with LOCK:
                self.send_json(200, load())
        elif path == PREFIX + "/api/health":
            self.send_json(200, {"ok": True})
        elif path in (PREFIX + "/", PREFIX + "/index.html"):
            body = (WEB_DIR / "index.html").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_json(404, {"error": "not found"})

    def do_PUT(self):
        if self.path.split("?", 1)[0] != PREFIX + "/api/list":
            return self.send_json(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > MAX_BODY:
                return self.send_json(413, {"error": "too large"})
            doc = json.loads(self.rfile.read(length))
            items = [clean_item(i) for i in doc.get("items", [])]
            budget = doc.get("monthlyBudget")
            budget = float(budget) if budget not in ("", None) else None
        except (ValueError, TypeError, AttributeError) as e:
            return self.send_json(400, {"error": str(e)})
        with LOCK:
            current = load()
            if doc.get("version") != current["version"]:
                return self.send_json(409, {"error": "changed elsewhere", **current})
            new = {"version": current["version"] + 1, "monthlyBudget": budget, "items": items}
            save(new)
        self.send_json(200, new)


if __name__ == "__main__":
    print(f"wishlist on {HOST}:{PORT}{PREFIX}/ data={DATA_FILE}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
