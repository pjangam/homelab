#!/usr/bin/env bash
# Boot memtest86+ once on xero, straight from the EFI system partition, with no
# USB stick and without GRUB.
#
# Why not GRUB: on 2026-10-06 `grub-reboot memtest86+` (Ubuntu's 7.00 package)
# left a blank screen and needed a full power drain to recover. This uses the
# upstream release instead and has the firmware load it directly, as a one-shot
# BootNext: the boot after memtest (power off/on, or Esc in memtest) goes back
# to Ubuntu by the normal BootOrder. Needs Secure Boot off (memtest86+ is
# unsigned) - checked below.
#
# Run from a real terminal on xero (sudo prompts):
#   tools/memtest/boot_memtest_once.sh            # install + arm, then reboot yourself
#   tools/memtest/boot_memtest_once.sh --remove   # delete the entry and the file afterwards
set -euo pipefail

VER=8.10
ESP=/boot/efi
FILE_REL='EFI\memtest\memtest64.efi'
LABEL="memtest86+ $VER"

esp_src=$(findmnt -n -o SOURCE "$ESP")
disk=/dev/$(lsblk -n -o PKNAME "$esp_src")
part=$(lsblk -n -o PARTN "$esp_src" | tr -d ' ')

entry_num() { sudo efibootmgr | awk -v l="$LABEL" 'index($0, l) {sub(/^Boot/,"",$1); sub(/\*$/,"",$1); print $1}'; }

if [[ ${1:-} == --remove ]]; then
  for n in $(entry_num); do sudo efibootmgr -q -b "$n" -B; done
  sudo rm -rf "$ESP/EFI/memtest"
  sudo efibootmgr
  exit 0
fi

if ! mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot disabled'; then
  echo "Secure Boot is not disabled; the firmware would refuse unsigned memtest86+." >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base=https://memtest.org/download/v$VER
curl -sSfL -o "$work/bin.zip" "$base/mt86plus_$VER.binaries.zip"
curl -sSfL -o "$work/sha256sum.txt" "$base/sha256sum.txt"
want=$(awk '/binaries\.zip/ {print $1}' "$work/sha256sum.txt")
echo "$want  $work/bin.zip" | sha256sum -c --quiet -
unzip -q "$work/bin.zip" -d "$work/bin"

sudo mkdir -p "$ESP/EFI/memtest"
sudo cp "$work/bin/mt86p_${VER//./}_x86_64" "$ESP/EFI/memtest/memtest64.efi"

# efibootmgr -c puts the new entry first in BootOrder; put the old order back
# so only BootNext (one boot) picks memtest.
order=$(sudo efibootmgr | awk '/^BootOrder:/ {print $2}')
for n in $(entry_num); do sudo efibootmgr -q -b "$n" -B; done
sudo efibootmgr -q -c -d "$disk" -p "$part" -L "$LABEL" -l "\\$FILE_REL"
sudo efibootmgr -q -o "$order"
n=$(entry_num)
sudo efibootmgr -q -n "$n"

sudo efibootmgr
echo
echo "Armed: next boot runs $LABEL (Boot$n) once. BootOrder unchanged ($order)."
echo "Reboot with: sudo reboot"
