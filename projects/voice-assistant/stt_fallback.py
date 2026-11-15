#!/usr/bin/env python3
"""Wyoming speech-to-text proxy: Speech-to-Phrase first, Marathi fallback after.

HA's Assist pipeline talks Wyoming to this proxy on :10300 (the port
Speech-to-Phrase used to publish, so HA's config did not change). Every event
is passed through to speech-to-phrase unchanged, and its answers come back
unchanged - except one: when it answers with an EMPTY transcript ("No text
recognized"), the proxy runs the same audio through AI4Bharat's IndicConformer
(Marathi, int8 ONNX, ~0.7s on xero) and devanagari_match.py. If that lands
clearly on one of our songs, the transcript becomes "play <spoken title>" and
HA's existing "play {song}" automation plays it. Otherwise it stays empty.

Why only on empty: Speech-to-Phrase is fast and never invents a command, but
its English model misses Marathi titles. IndicConformer hears Marathi but
not English, so it is only trusted to name one of our songs (benchmark
2026-11-15: 28/30 titles, 0 wrong, non-songs all came back as nothing).

Never makes things worse: no model yet, a model error, a Spotify error -> the
empty transcript goes through as it would have. Logs one line per fallback.
Runs in the stt-fallback container (docker-compose.yml); see README.md.
"""
import asyncio
import json
import os
import sys
import threading
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import devanagari_match as dm  # noqa: E402
import spotify_library as lib  # noqa: E402

LISTEN = int(os.environ.get("LISTEN_PORT", "10300"))
UPSTREAM = os.environ.get("UPSTREAM", "speech-to-phrase:10300")
MODEL_DIR = os.environ.get("MODEL_DIR", "/model")
MODEL_REPO = "OpenVoiceOS/ai4bharat-indicconformer-mr-onnx"
MIN_SECS = 0.4  # shorter audio is no song title
# PARALLEL=1: start IndicConformer on every request as soon as the audio ends,
# alongside speech-to-phrase, and use it only if speech-to-phrase hears
# nothing - saves speech-to-phrase's time on Marathi misses, costs CPU on every
# command. IC_THREADS: ONNX Runtime threads (0 = its default, all cores).
PARALLEL = os.environ.get("PARALLEL", "0") == "1"
IC_THREADS = int(os.environ.get("IC_THREADS", "0"))

model = None  # set by load_model() in the background


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def load_model():
    global model
    try:
        import onnx_asr
        if not Path(MODEL_DIR, "model.int8.onnx").exists():
            from huggingface_hub import snapshot_download
            snapshot_download(MODEL_REPO, local_dir=MODEL_DIR,
                              allow_patterns=["config.json", "vocab.txt", "model.int8.onnx"])
        t = time.time()
        import onnxruntime as ort
        so = ort.SessionOptions()
        if IC_THREADS:
            so.intra_op_num_threads = IC_THREADS
        m = onnx_asr.load_model("nemo-conformer-ctc", MODEL_DIR, quantization="int8", sess_options=so)
        m.recognize(np.zeros(16000, dtype=np.float32), sample_rate=16000)  # warm-up
        model = m
        log(f"fallback ready: IndicConformer loaded in {time.time() - t:.1f}s "
            f"(parallel={PARALLEL}, threads={IC_THREADS or 'default'})")
    except Exception as e:  # stay a plain proxy
        log(f"fallback DISABLED, model failed to load: {e!r}")


class Songs:
    """The song list, re-read when the nightly sync rewrites it."""
    def __init__(self):
        self.mtime, self.map, self.keys = None, {}, {}

    def get(self):
        mt = lib.OUT_PKG.stat().st_mtime
        if mt != self.mtime:
            self.map = dm.library()
            self.keys = {k: dm.squash(k) for k in self.map if " by " not in k}
            self.mtime = mt
            log(f"song list loaded: {len(self.keys)} titles")
        return self.map, self.keys


songs = Songs()


def spotify_token():
    try:
        return lib.token()
    except BaseException:  # lib.token() sys.exit()s on an expiring token
        return None


def fallback(pcm, rate, width, channels):
    """Blocking: audio -> ('play <title>' or '', log line). Worker thread."""
    t = time.time()
    a = np.frombuffer(pcm[: len(pcm) - len(pcm) % (width * channels)],
                      dtype={2: np.int16, 4: np.int32}[width])
    a = a.reshape(-1, channels)[:, 0].astype(np.float32) / float(2 ** (8 * width - 1))
    secs = len(a) / rate
    if secs < MIN_SECS:
        return "", f"fallback: {secs:.1f}s audio, too short"
    heard = model.recognize(a, sample_rate=rate).strip()
    hit = None
    if heard:
        lib_map, keys = songs.get()
        hit = dm.match(heard, lib_map, keys, spotify_token())
    out = f"play {hit[0]}" if hit else ""
    return out, (f"fallback: {secs:.1f}s audio, heard {heard!r} -> "
                 f"{(repr(out) + ' [' + hit[2] + ']') if hit else 'nothing'} ({time.time() - t:.2f}s)")


async def read_event(reader):
    """One Wyoming event: (header dict with data merged, raw bytes, payload)."""
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
    audio = {"pcm": bytearray(), "fmt": (16000, 2, 1), "job": None}
    loop = asyncio.get_running_loop()

    async def client_to_upstream():
        while ev := await read_event(c_reader):
            hdr, data, raw, payload = ev
            if hdr["type"] == "audio-start":
                audio["pcm"].clear()
                audio["fmt"] = (data.get("rate", 16000), data.get("width", 2), data.get("channels", 1))
            elif hdr["type"] == "audio-chunk":
                audio["pcm"] += payload
            elif hdr["type"] == "audio-stop" and PARALLEL and model is not None and audio["pcm"]:
                audio["job"] = loop.run_in_executor(None, fallback, bytes(audio["pcm"]), *audio["fmt"])
            u_writer.write(raw)
            await u_writer.drain()

    async def upstream_to_client():
        while ev := await read_event(u_reader):
            hdr, data, raw, payload = ev
            if (hdr["type"] == "transcript" and not (data.get("text") or "").strip()
                    and model is not None and audio["pcm"]):
                try:
                    job = audio["job"] or loop.run_in_executor(
                        None, fallback, bytes(audio["pcm"]), *audio["fmt"])
                    text, line = await job
                    log(line)
                except Exception as e:
                    log(f"fallback error, passing the empty transcript: {e!r}")
                    text = ""
                if text:
                    raw = encode(hdr, {**data, "text": text})
            c_writer.write(raw)
            await c_writer.drain()

    # One request per connection (HA opens a new one each time). Either side
    # hanging up ends both: the client leaving after its transcript, or
    # speech-to-phrase closing. Otherwise every request left a task behind.
    tasks = [asyncio.ensure_future(client_to_upstream()), asyncio.ensure_future(upstream_to_client())]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for w in (c_writer, u_writer):
            w.close()


async def main():
    threading.Thread(target=load_model, daemon=True).start()
    server = await asyncio.start_server(handle, "0.0.0.0", LISTEN)
    log(f"listening on :{LISTEN}, upstream {UPSTREAM}")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
