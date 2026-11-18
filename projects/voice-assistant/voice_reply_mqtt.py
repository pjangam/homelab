#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["paho-mqtt"]
# ///
"""Voice-reply bridge: play HA's spoken reply on this room's speaker.

Runs on the wol Pi (bedroom, 3.5mm jack) and on xero (living room, Bluetooth
Apollo One) as the `voice-reply` systemd --user unit, next to an always-running
VLC (`voice-reply-vlc`, driven over a unix socket). HA's `voice_reply` script
publishes voice_reply/<host>/play {id, url | sound: "tone", volume?}; this
plays it and answers voice_reply/<host>/done {id} - for every play, dropped or
not. Design and reasons: plan-room-replies.md, Design row 2.

Per play:
 0. drop (still answering done) if: the url is not HA's tts_proxy mp3, the
    sound is not "tone", it waited > 10s in this queue, on the Pi white noise
    is active/activating/deactivating, on xero the Bluetooth speaker is not
    connected or not the default sink (Bluetooth errors are ignored: no
    reconnect, user 2026-11-18)
 1. only if `volume` is given: save level + mute to a file, set the preset
    with unmute
 2. download the mp3 (no VLC network buffer), VLC plays the local file;
    wait for playing (3s), then stopped (20s); xero +300ms Bluetooth tail
 3. restore the level - on the Pi, if white noise started meanwhile, set its
    own level (WHITE_NOISE_LEVEL) instead
 4. done, never sooner than 1s after the play arrived (HA subscribes for it
    0.1-0.5s after publishing)

Also: retained voice_reply/<host>/available (online only while VLC answers,
last will offline) + MQTT discovery binary_sensor.voice_reply_<host>.
"""
import hashlib
import json
import math
import os
import queue
import random
import re
import socket
import struct
import subprocess
import threading
import time
import urllib.request
import wave
from pathlib import Path

import paho.mqtt.client as mqtt

HOST = os.environ["VOICE_REPLY_HOST"]  # "pi" or "xero"
BROKER = os.environ.get("MQTT_HOST", "localhost")
RUN = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
SOCK = RUN / "voice-reply.sock"
STATE = Path.home() / ".local/state/voice-reply"
SAVED = STATE / "saved-volume.json"
TONE = STATE / "tone.wav"
# HA plays its acknowledge chime instead of the spoken answer when every
# device a command touched is in the satellite's room (assist_pipeline,
# acknowledge.mp3; no setting to turn it off). The user wants an answer
# spoken (2026-11-18): the chime is swapped for done.mp3 ("Done.", Piper
# lessac like the replies). Matched by HA's file hash - an HA update that
# changes acknowledge.mp3 brings the chime back; add the new hash here.
ACK_SHA256 = {"88762f0f72e04bab3b545d4852d0badd017bb4a8799cc4f3ef0cb4fc8e7ecdae"}
DONE = Path(__file__).resolve().parent / "done.mp3"
LEAD = STATE / "lead-in.wav"  # xero: played before each sound, see make_lead
# Which mixer the preset goes to: the same control as the room's volume slider
# (volume-mqtt). Pi: -c Headphones PCM (its default card is HDMI). xero:
# -D pipewire Master = PipeWire's default sink, the Bluetooth speaker.
AMIXER = ["amixer"] + os.environ.get("VOICE_REPLY_AMIXER", "-c Headphones").split()
CONTROL = os.environ.get("VOICE_REPLY_CONTROL", "PCM")
BT_MAC = os.environ.get("BT_SPEAKER_MAC", "")  # xero only
URL_PREFIX = "http://192.168.1.123:8123/api/tts_proxy/"
MAX_QUEUE_AGE = 10.0
MIN_DONE_AFTER = 1.0

TOPIC = f"voice_reply/{HOST}"
UID = f"voice_reply_{HOST}"
PCT = re.compile(r"\[(\d+)%\]")
SW = re.compile(r"\[(on|off)\]")

jobs = queue.Queue()
online = {"value": None}


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


# --- VLC over its oldrc unix socket --------------------------------------
class Vlc:
    """oldrc prints async "status change" lines too, so every command first
    drains what is waiting, and is_playing reads until a bare 0/1 line."""
    def __init__(self):
        self.s = None

    def _sock(self):
        if self.s is None:
            self.s = socket.socket(socket.AF_UNIX)
            self.s.connect(str(SOCK))
        return self.s

    def _drain(self):
        s = self._sock()
        s.setblocking(False)
        try:
            while s.recv(65536):
                pass
        except (BlockingIOError, InterruptedError):
            pass
        finally:
            s.setblocking(True)

    def _send(self, c):
        try:
            self._drain()
            self._sock().sendall((c + "\n").encode())
        except OSError:
            if self.s:
                self.s.close()
            self.s = None
            self._drain()
            self._sock().sendall((c + "\n").encode())

    def cmd(self, c):
        self._send(c)

    def playing(self):
        self._send("is_playing")
        s = self._sock()
        s.settimeout(1)
        buf = b""
        try:
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    raise OSError("VLC closed the socket")
                buf += chunk
                for line in buf.decode(errors="replace").replace("\r", "").split("\n"):
                    if line.strip().lstrip("> ").strip() in ("0", "1"):
                        return line.strip().endswith("1")
        except socket.timeout:
            raise OSError("no is_playing answer")

    def alive(self):
        try:
            self.playing()
            return True
        except OSError:
            if self.s:
                self.s.close()
            self.s = None
            return False


vlc = Vlc()
vlc_lock = threading.Lock()


# --- mixer ----------------------------------------------------------------
def mixer_get():
    out = subprocess.run(AMIXER + ["sget", CONTROL], capture_output=True, text=True).stdout
    p, m = PCT.search(out), SW.search(out)
    return {"level": int(p.group(1)) if p else None, "on": (m.group(1) == "on") if m else True}


def mixer_set(level, on=True):
    subprocess.run(AMIXER + ["-q", "sset", CONTROL, f"{int(level)}%", "unmute" if on else "mute"],
                   check=False)


def white_noise_busy():
    if HOST != "pi":
        return False
    st = subprocess.run(["systemctl", "--user", "is-active", "white-noise"],
                        capture_output=True, text=True).stdout.strip()
    return st in ("active", "activating", "deactivating")


def white_noise_level():
    out = subprocess.run(["systemctl", "--user", "show", "white-noise", "-p", "Environment"],
                         capture_output=True, text=True).stdout
    m = re.search(r"WHITE_NOISE_LEVEL=(\d+)", out)
    return int(m.group(1)) if m else 91


def restore_saved():
    """Put back a level saved before a reply; on the Pi not over white noise."""
    if not SAVED.exists():
        return
    try:
        saved = json.loads(SAVED.read_text())
        if white_noise_busy():
            mixer_set(white_noise_level(), True)
            log(f"restore skipped (white noise on): set {white_noise_level()}%")
        elif saved.get("level") is not None:
            mixer_set(saved["level"], saved.get("on", True))
            log(f"restored {saved['level']}% {'on' if saved.get('on', True) else 'muted'}")
    finally:
        SAVED.unlink(missing_ok=True)


def speaker_ready():
    """xero: the Bluetooth speaker is connected and PipeWire's default sink."""
    if HOST != "xero" or not BT_MAC:
        return True
    info = subprocess.run(["bluetoothctl", "info", BT_MAC], capture_output=True, text=True).stdout
    if "Connected: yes" not in info:
        return False
    sink = subprocess.run(["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"],
                          capture_output=True, text=True).stdout
    return f'node.name = "bluez_output.{BT_MAC.replace(":", "_")}' in sink


def make_tone():
    """A short soft two-note chime, written once (no TTS call for failures)."""
    if TONE.exists():
        return
    rate, notes = 22050, [(660, 0.16), (880, 0.24)]
    frames = bytearray()
    for f, dur in notes:
        n = int(rate * dur)
        for i in range(n):
            env = min(1.0, i / (0.01 * rate)) * (1 - i / n) ** 2
            frames += struct.pack("<h", int(0.25 * 32767 * env * math.sin(2 * math.pi * f * i / rate)))
    with wave.open(str(TONE), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def make_lead():
    """xero only: 0.8s of very faint noise (about -60 dB) played before every
    reply and tone. The Bluetooth speaker drops the first part of a sound
    after a quiet spell, which turned a 1.6s "Turned off the switch" into a
    blip (2026-11-18); this wakes it first. Noise, not digital silence, so a
    speaker that mutes on silence wakes too."""
    if LEAD.exists():
        return
    rate = 22050
    with wave.open(str(LEAD), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", random.randint(-30, 30)) for _ in range(int(rate * 0.8))))


# --- one play ---------------------------------------------------------------
def handle(job, client):
    req, arrived = job
    rid = req.get("id")
    why = None
    url, sound, volume = req.get("url"), req.get("sound"), req.get("volume")
    if url and not (url.startswith(URL_PREFIX) and url.endswith(".mp3")):
        why = f"bad url {url[:60]!r}"
    elif not url and sound != "tone":
        why = f"bad sound {sound!r}"
    elif time.monotonic() - arrived > MAX_QUEUE_AGE:
        why = "waited too long in the queue"
    elif white_noise_busy():
        why = "white noise is on"
    elif not speaker_ready():
        why = "Bluetooth speaker not connected"
    if why is None:
        try:
            how = play(url, volume)
            log(f"played {rid} ({'tone' if not url else 'reply'}{f', at {volume}%' if volume is not None else ''}): {how}")
        except Exception as e:  # noqa: BLE001 - never leave HA waiting
            log(f"play {rid} failed: {e!r}")
            restore_saved()
    else:
        log(f"dropped {rid}: {why}")
    if jobs.empty():
        restore_saved()  # after the last queued play, dropped or not
    left = MIN_DONE_AFTER - (time.monotonic() - arrived)
    if left > 0:
        time.sleep(left)
    client.publish(f"{TOPIC}/done", json.dumps({"id": rid}))


def play(url, volume):
    if url:
        path = RUN / "voice-reply.mp3"
        with urllib.request.urlopen(url, timeout=5) as r:
            data = r.read()
        if hashlib.sha256(data).hexdigest() in ACK_SHA256 and DONE.exists():
            data = DONE.read_bytes()
        path.write_bytes(data)
    else:
        path = TONE
    if volume is not None:
        if not SAVED.exists():  # a queued second play keeps the first saved level
            SAVED.write_text(json.dumps(mixer_get()))
        mixer_set(volume, True)
    with vlc_lock:
        vlc.cmd("clear")
        if HOST == "xero":
            vlc.cmd(f"add {LEAD}")
            vlc.cmd(f"enqueue {path}")
        else:
            vlc.cmd(f"add {path}")
        t = time.monotonic()
        while not vlc.playing() and time.monotonic() - t < 3:
            time.sleep(0.02)
        started = time.monotonic() - t
        t = time.monotonic()
        # stopped = not playing for 0.4s in a row: VLC reports "not playing"
        # for a moment between the lead-in and the sound
        quiet_since = None
        while time.monotonic() - t < 20:
            if vlc.playing():
                quiet_since = None
            elif quiet_since is None:
                quiet_since = time.monotonic()
            elif time.monotonic() - quiet_since >= 0.4:
                break
            time.sleep(0.05)
        heard = (quiet_since or time.monotonic()) - t
        vlc.cmd("stop")
    if HOST == "xero":
        time.sleep(0.3)  # Bluetooth plays ~0.2s behind
    return f"started after {started:.2f}s, played {heard:.1f}s"


def worker(client):
    while True:
        handle(jobs.get(), client)


# --- MQTT -----------------------------------------------------------------
def publish_available(client, force=False):
    up = vlc.alive()
    if force or up != online["value"]:
        client.publish(f"{TOPIC}/available", "online" if up else "offline", retain=True)
        if not up or online["value"] is not None:
            log(f"VLC {'answering' if up else 'NOT answering'} -> {'online' if up else 'offline'}")
        online["value"] = up


def on_connect(client, userdata, flags, reason_code, properties=None):
    if reason_code.is_failure:
        log(f"MQTT connect failed: {reason_code}")
        return
    room = {"pi": "Bedroom", "xero": "Living room"}.get(HOST, HOST)
    client.publish(f"homeassistant/binary_sensor/{UID}/config", json.dumps({
        "name": f"{room} voice replies",
        "unique_id": UID,
        "object_id": UID,
        "device_class": "connectivity",
        "entity_category": "diagnostic",
        "state_topic": f"{TOPIC}/available",
        "payload_on": "online",
        "payload_off": "offline",
    }), retain=True)
    with vlc_lock:
        publish_available(client, force=True)
    client.subscribe(f"{TOPIC}/play", qos=0)


def on_message(client, userdata, msg):
    try:
        req = json.loads(msg.payload)
    except ValueError:
        log(f"ignored non-JSON play: {msg.payload[:80]!r}")
        return
    jobs.put((req, time.monotonic()))


def main():
    STATE.mkdir(parents=True, exist_ok=True)
    make_tone()
    if HOST == "xero":
        make_lead()
    restore_saved()  # a crash or reboot mid-reply
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"voice-reply-{HOST}",
                         clean_session=True)
    client.username_pw_set(os.environ["MQTT_USERNAME"], os.environ["MQTT_PASSWORD"])
    client.will_set(f"{TOPIC}/available", "offline", retain=True)
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(BROKER, 1883)
    threading.Thread(target=worker, args=(client,), daemon=True).start()

    def health():
        time.sleep(5)  # VLC starts slower than this on the Pi
        while True:
            with vlc_lock:
                publish_available(client)
            time.sleep(30)
    threading.Thread(target=health, daemon=True).start()
    log(f"voice-reply {HOST}: {TOPIC}/play, mixer {' '.join(AMIXER[1:])} {CONTROL}")
    client.loop_forever()


if __name__ == "__main__":
    main()
