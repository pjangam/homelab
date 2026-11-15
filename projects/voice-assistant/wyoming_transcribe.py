#!/usr/bin/env python3
"""Send a 16kHz mono WAV to a Wyoming STT server and print the transcript.

Talks to the server directly, not through HA, so it can test the stt-fallback
proxy and speech-to-phrase side by side:
    wyoming_transcribe.py 127.0.0.1:10300 clip.wav   # the proxy (what HA uses)
    wyoming_transcribe.py 127.0.0.1:10301 clip.wav   # speech-to-phrase alone
Reads the samples after the 44-byte header, so WAVs piped out of ffmpeg (no
length in the header) work too.
"""
import json
import socket
import sys
import time


def send(sock, typ, data=None, payload=b""):
    db = json.dumps(data or {}).encode()
    hdr = {"type": typ, "version": "1.5.0", "data_length": len(db)}
    if payload:
        hdr["payload_length"] = len(payload)
    sock.sendall(json.dumps(hdr).encode() + b"\n" + db + payload)


def main():
    host, port = sys.argv[1].rsplit(":", 1)
    pcm = open(sys.argv[2], "rb").read()[44:]
    fmt = {"rate": 16000, "width": 2, "channels": 1}
    t = time.time()
    s = socket.create_connection((host, int(port)), timeout=60)
    send(s, "transcribe", {"language": "en"})
    send(s, "audio-start", fmt)
    for i in range(0, len(pcm), 2048):
        send(s, "audio-chunk", fmt, pcm[i:i + 2048])
    send(s, "audio-stop")
    f = s.makefile("rb")
    while line := f.readline():
        hdr = json.loads(line)
        data = hdr.get("data") or {}
        if hdr.get("data_length"):
            data.update(json.loads(f.read(hdr["data_length"])))
        if hdr.get("payload_length"):
            f.read(hdr["payload_length"])
        if hdr["type"] == "transcript":
            print(f"{time.time() - t:.2f}s {data.get('text')!r}")
            return
    print("connection closed without a transcript")


if __name__ == "__main__":
    main()
