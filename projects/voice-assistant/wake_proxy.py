#!/usr/bin/env python3
"""Wyoming wake-word proxy: more than one wake word live at once.

HA's Assist pipeline asks openWakeWord for exactly ONE wake word (the
pipeline's `wake_word_id`, "hey_jarvis") and drops any detection with another
name ("Expected wake word ... skipping", HA 2026.11 wyoming/wake_word.py).
openWakeWord itself can listen for several at once. This proxy sits on :10400
(the port openwakeword used to publish, so HA's config did not change) and
rewrites two events, passing everything else through unchanged:

- `detect` from HA: names [hey_jarvis] -> [hey_jarvis, dumbledore, ...]
- `detection` from openwakeword: name dumbledore -> the name HA asked for

So "Dumbledore" wakes the satellites exactly as "Hey Jarvis" does. Logs one
line per detection with the word that was really heard. No satellite flashing:
the boards only stream audio; wake words are detected here on xero.
EXTRA_WAKE_WORDS (comma-separated, default "dumbledore") must be preloaded
by the openwakeword container. Runs in the wake-proxy container
(docker-compose.yml); see README.md.
"""
import asyncio
import json
import os
import time

LISTEN = int(os.environ.get("LISTEN_PORT", "10400"))
UPSTREAM = os.environ.get("UPSTREAM", "openwakeword:10400")
EXTRA = [w.strip() for w in os.environ.get("EXTRA_WAKE_WORDS", "dumbledore").split(",") if w.strip()]


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


async def read_event(reader):
    """One Wyoming event: (header, data with data_length part merged, raw bytes, payload)."""
    line = await reader.readline()
    if not line:
        return None
    hdr = json.loads(line)
    raw = line
    data = dict(hdr.get("data") or {})
    if hdr.get("data_length"):
        db = await reader.readexactly(hdr["data_length"])
        raw += db
        data.update(json.loads(db))
    payload = b""
    if hdr.get("payload_length"):
        payload = await reader.readexactly(hdr["payload_length"])
        raw += payload
    return hdr, data, raw, payload


def encode(hdr, data):
    db = json.dumps(data, ensure_ascii=False).encode()
    h = {"type": hdr["type"], "data_length": len(db)}
    if "version" in hdr:
        h["version"] = hdr["version"]
    return json.dumps(h, ensure_ascii=False).encode() + b"\n" + db


async def handle(c_reader, c_writer):
    host, port = UPSTREAM.rsplit(":", 1)
    try:
        u_reader, u_writer = await asyncio.open_connection(host, int(port))
    except OSError as e:
        log(f"upstream {UPSTREAM} unreachable: {e}")
        c_writer.close()
        return
    asked = {"names": None}  # what HA asked for on this connection

    async def client_to_upstream():
        while ev := await read_event(c_reader):
            hdr, data, raw, _ = ev
            if hdr["type"] == "detect" and data.get("names"):
                asked["names"] = list(data["names"])
                names = asked["names"] + [w for w in EXTRA if w not in asked["names"]]
                raw = encode(hdr, {**data, "names": names})
            u_writer.write(raw)
            await u_writer.drain()

    async def upstream_to_client():
        while ev := await read_event(u_reader):
            hdr, data, raw, _ = ev
            if hdr["type"] == "detection":
                heard = data.get("name")
                if asked["names"] and heard not in asked["names"]:
                    raw = encode(hdr, {**data, "name": asked["names"][0]})
                    log(f"heard {heard!r} -> reported as {asked['names'][0]!r}")
                else:
                    log(f"heard {heard!r}")
            c_writer.write(raw)
            await c_writer.drain()

    # Either side hanging up ends both (same as stt_fallback.py).
    tasks = [asyncio.ensure_future(client_to_upstream()), asyncio.ensure_future(upstream_to_client())]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    except Exception as e:
        log(f"connection error: {e!r}")
    finally:
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for w in (c_writer, u_writer):
            w.close()


async def main():
    server = await asyncio.start_server(handle, "0.0.0.0", LISTEN)
    log(f"listening on :{LISTEN}, upstream {UPSTREAM}, extra wake words {EXTRA}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
