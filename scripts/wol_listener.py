#!/usr/bin/env python3
"""Standalone WoL magic-packet listener/validator - lets us confirm
wol-xero.service (running on the Pi) is actually sending a valid packet
that reaches xero's LAN segment, without needing to shut xero down for a
full wake test. Run on xero (needs sudo/root - UDP port 9 is privileged):

    sudo python3 scripts/wol_listener.py
"""
import socket

TARGET_MAC = "68:1D:EF:38:8C:72"
PORT = 9


def mac_to_bytes(mac):
    return bytes.fromhex(mac.replace(":", ""))


def is_magic_packet(data, target_mac_bytes):
    if len(data) < 102 or data[:6] != b"\xff" * 6:
        return False
    return all(
        data[6 + i * 6 : 6 + i * 6 + 6] == target_mac_bytes for i in range(16)
    )


def main():
    target = mac_to_bytes(TARGET_MAC)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", PORT))

    print(f"Listening for WoL magic packets on UDP:{PORT}, targeting {TARGET_MAC}...")
    print("Reboot the Pi now - Ctrl+C to stop.\n")

    while True:
        data, addr = sock.recvfrom(1024)
        if is_magic_packet(data, target):
            print(f"VALID magic packet for {TARGET_MAC} received from {addr[0]}")
        else:
            print(f"Got {len(data)} bytes from {addr[0]} - not a valid magic packet (ignoring)")


if __name__ == "__main__":
    main()
