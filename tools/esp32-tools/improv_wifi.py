#!/usr/bin/env python3
"""Give an ESP32 its WiFi over the USB cable (Improv serial), no AP needed.

Written 2026-10-30 for the Diwali WLED board: the usual path is to join the
board's WLED-AP network, and xero's WiFi card needs sudo to do that. WLED (and
ESPHome) speak Improv over serial, so a board still on the USB cable after
flashing can be handed the house WiFi directly. Prints the board's address
once it has joined (DHCP - set a static one afterwards over its JSON API).

Needs pyserial; the esptool venv has it:
    ~/.cache/wled-esptool-venv/bin/python tools/esp32-tools/improv_wifi.py \
        --ssid NAME --password PASS [--port /dev/ttyUSB0]

Opening the port leaves DTR/RTS low, so the board is not reset into the
bootloader. Protocol: https://www.improv-wifi.com/serial/
"""
import argparse
import sys
import time

import serial

HEADER = b"IMPROV"
VERSION = 1
TYPE_STATE, TYPE_ERROR, TYPE_RPC, TYPE_RESULT = 0x01, 0x02, 0x03, 0x04
CMD_WIFI = 0x01
STATES = {0x02: "ready", 0x03: "provisioning", 0x04: "provisioned"}
ERRORS = {0x01: "invalid packet", 0x02: "unknown command",
          0x03: "unable to connect (wrong password, or out of range)", 0xFF: "unknown"}


def packet(ptype, data):
    body = HEADER + bytes([VERSION, ptype, len(data)]) + data
    return body + bytes([sum(body) & 0xFF]) + b"\n"


def wifi_rpc(ssid, password):
    s, p = ssid.encode(), password.encode()
    payload = bytes([len(s)]) + s + bytes([len(p)]) + p
    return packet(TYPE_RPC, bytes([CMD_WIFI, len(payload)]) + payload)


def read_packets(port, deadline, tick=lambda: None):
    """Yield (type, data) for each Improv packet seen before the deadline,
    calling tick() between reads."""
    buf = b""
    while time.time() < deadline:
        tick()
        buf += port.read(256)
        while True:
            i = buf.find(HEADER)
            if i < 0 or len(buf) < i + 9:
                buf = buf[-16:] if i < 0 else buf[i:]
                break
            ptype, length = buf[i + 7], buf[i + 8]
            end = i + 9 + length + 1
            if len(buf) < end:
                buf = buf[i:]
                break
            yield ptype, buf[i + 9:end - 1]
            buf = buf[end:]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", default="/dev/ttyUSB0")
    ap.add_argument("--ssid", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--timeout", type=int, default=45)
    ap.add_argument("--boot-wait", type=float, default=8, help="seconds to let the board boot after the port opens")
    a = ap.parse_args()

    port = serial.Serial()
    port.port, port.baudrate, port.timeout = a.port, 115200, 0.2
    port.dtr = port.rts = False  # do not reset the board on open
    port.open()
    # Some boards (this CP2102 one, 2026-10-30) still power-on-reset when the
    # port opens, so a packet sent at once lands mid-boot and is lost: let
    # the firmware come up, then resend until it answers.
    time.sleep(a.boot_wait)
    port.reset_input_buffer()
    print(f"sending WiFi '{a.ssid}' to {a.port}; waiting up to {a.timeout}s...")

    sent = 0.0
    def resend():
        nonlocal sent
        if time.time() - sent >= 5:
            port.write(wifi_rpc(a.ssid, a.password))
            sent = time.time()

    for ptype, data in read_packets(port, time.time() + a.timeout, resend):
        if ptype == TYPE_STATE and data:
            print("state:", STATES.get(data[0], hex(data[0])))
        elif ptype == TYPE_ERROR and data and data[0]:
            sys.exit("error: " + ERRORS.get(data[0], hex(data[0])))
        elif ptype == TYPE_RESULT and len(data) >= 2:
            # [command, total length, (len, string)...] - the strings are URLs
            urls, i = [], 2
            while i < len(data):
                n = data[i]
                urls.append(data[i + 1:i + 1 + n].decode(errors="replace"))
                i += 1 + n
            for u in urls:
                print("url:", u)
            return
    sys.exit("no answer - is the board running WLED/ESPHome, and nothing else holding the port?")


if __name__ == "__main__":
    main()
