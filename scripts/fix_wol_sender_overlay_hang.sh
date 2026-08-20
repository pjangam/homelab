#!/bin/bash
# Enabling raspi-config's read-only overlay filesystem (cmdline.txt:
# overlayroot=tmpfs) on the wol-sender Pi (2026-08-05ish) left it hanging on
# boot - display showed normal kernel/USB logs then went blank, unresponsive
# to keyboard, red PWR LED eventually stable (not a power issue) but nothing
# further. Root ext4 fsck came back clean, so it wasn't corruption either.
# Pulling the SD card into a reader on xero and removing overlayroot=tmpfs
# from cmdline.txt let it boot normally again - this script automates that
# fix/rollback. Run with the wol-sender's SD card in a USB reader plugged
# into xero.
set -e

BOOT_MNT=/mnt/pi_boot
BOOT_DEV="$(readlink -f /dev/disk/by-label/bootfs)"

if [ -z "$BOOT_DEV" ]; then
    echo "Could not find a partition labeled 'bootfs' - is the SD card plugged in?" >&2
    exit 1
fi

echo "=== found boot partition at $BOOT_DEV ==="

echo "=== cleaning up any stale mounts first ==="
sudo umount "$BOOT_DEV" 2>/dev/null || true
sudo umount "$BOOT_MNT" 2>/dev/null || true

sudo mkdir -p "$BOOT_MNT"

echo "=== mounting boot partition read-write ==="
sudo mount -o rw "$BOOT_DEV" "$BOOT_MNT"

CMDLINE="$BOOT_MNT/cmdline.txt"
BACKUP="$BOOT_MNT/cmdline.txt.bak-$(date +%Y%m%d-%H%M%S)"

echo "=== current cmdline.txt ==="
sudo cat "$CMDLINE"

echo
echo "=== backing up to $BACKUP ==="
sudo cp "$CMDLINE" "$BACKUP"

echo "=== removing overlayroot=tmpfs ==="
sudo sed -i 's/\boverlayroot=tmpfs\b//g; s/[[:space:]]\+/ /g; s/^ //; s/ $//' "$CMDLINE"

echo
echo "=== new cmdline.txt ==="
sudo cat "$CMDLINE"

echo
echo "=== syncing and unmounting ==="
sync
sudo umount "$BOOT_MNT"

echo
echo "Done. Overlay disabled. Backup saved as $(basename "$BACKUP") on the boot partition itself."
echo "To restore later: mount the boot partition, then 'sudo cp <backup> cmdline.txt'."
echo "Now safely eject the SD card, put it back in the Pi, and power it on to test."
