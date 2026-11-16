#!/usr/bin/env python3
"""Stream a 16kHz mono WAV to a Wyoming wake-word server, print what it detects.

Asks for one wake word, like HA does, so it tests wake_proxy.py:
    wyoming_wake.py 127.0.0.1:10400 hey_jarvis clip.wav   # the proxy (what HA uses)
    wyoming_wake.py 127.0.0.1:10401 hey_jarvis clip.wav   # openwakeword alone
Prints "detected <name>" or "not detected". 1s of silence is added after the
clip so the detector sees the end of the word.
"""
import json
import socket
import sys


def send(sock, typ, data=None, payload=b""):
    db = json.dumps(data or {}).encode()
    hdr = {"type": typ, "version": "1.5.0", "data_length": len(db)}
    if payload:
        hdr["payload_length"] = len(payload)
    sock.sendall(json.dumps(hdr).encode() + b"\n" + db + payload)


def main():
    host, port = sys.argv[1].rsplit(":", 1)
    pcm = open(sys.argv[3], "rb").read()[44:] + bytes(32000)
    fmt = {"rate": 16000, "width": 2, "channels": 1}
    s = socket.create_connection((host, int(port)), timeout=30)
    send(s, "detect", {"names": [sys.argv[2]]})
    send(s, "audio-start", fmt)
    for i in range(0, len(pcm), 2048):
        send(s, "audio-chunk", {**fmt, "timestamp": i // 32}, pcm[i:i + 2048])
    send(s, "audio-stop")
    f = s.makefile("rb")
    while line := f.readline():
        hdr = json.loads(line)
        data = hdr.get("data") or {}
        if hdr.get("data_length"):
            data.update(json.loads(f.read(hdr["data_length"])))
        if hdr.get("payload_length"):
            f.read(hdr["payload_length"])
        if hdr["type"] == "detection":
            print(f"detected {data.get('name')}")
            return
        if hdr["type"] == "not-detected":
            print("not detected")
            return
    print("connection closed")


if __name__ == "__main__":
    main()
