#!/usr/bin/env bash
# Backs up system state, then applies pending 24.04 point-release updates
# (apt full-upgrade). Must run as root - crontab/systemd-run entries invoke
# it directly as root rather than shelling out to sudo, since sudo requires
# an interactive password on this box.
#
# Not for the 24.04 -> 26.04 release upgrade: Canonical's meta-release feed
# still flags resolute as Supported: 0, so do-release-upgrade refuses to
# offer it. This script only covers noble point-release updates.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Must run as root (this script runs apt/dpkg and reads root-only files)." >&2
  exit 1
fi

LOG_DIR="/home/pramod/code/homelab"
LOG_FILE="$LOG_DIR/os-update.log"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="/datapool/system-backups"
BACKUP_DIR="$BACKUP_ROOT/pre-update-$STAMP"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== [$(date)] Starting backup + apt update ====="

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Recording package state..."
dpkg --get-selections > "$BACKUP_DIR/dpkg-selections.txt"
apt-mark showmanual > "$BACKUP_DIR/manual-packages.txt"
apt list --installed > "$BACKUP_DIR/installed-packages.txt" 2>/dev/null

echo "[$(date)] Backing up /etc..."
cp -a /etc "$BACKUP_DIR/etc"

echo "[$(date)] Saving crontabs..."
crontab -l -u pramod > "$BACKUP_DIR/pramod-crontab.txt" 2>/dev/null || true
crontab -l -u root > "$BACKUP_DIR/root-crontab.txt" 2>/dev/null || true

echo "[$(date)] Saving systemd unit state..."
systemctl list-unit-files --state=enabled > "$BACKUP_DIR/enabled-units.txt"

echo "[$(date)] Saving Docker state (if present)..."
if command -v docker >/dev/null 2>&1; then
  docker ps -a > "$BACKUP_DIR/docker-containers.txt" 2>/dev/null || true
  docker images > "$BACKUP_DIR/docker-images.txt" 2>/dev/null || true
fi

echo "[$(date)] Saving partition table..."
sfdisk -d /dev/sdb > "$BACKUP_DIR/sdb-partition-table.txt" 2>/dev/null || true

echo "[$(date)] Compressing backup to $BACKUP_DIR.tar.gz..."
tar czf "$BACKUP_DIR.tar.gz" -C "$BACKUP_ROOT" "$(basename "$BACKUP_DIR")"
rm -rf "$BACKUP_DIR"
echo "[$(date)] Backup complete: $BACKUP_DIR.tar.gz"

echo "[$(date)] Running apt update..."
apt-get update

echo "[$(date)] Running apt full-upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  full-upgrade

echo "[$(date)] Running apt autoremove..."
DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge

if [[ -f /var/run/reboot-required ]]; then
  echo "[$(date)] REBOOT REQUIRED after this update:"
  cat /var/run/reboot-required.pkgs 2>/dev/null || true
  echo "[$(date)] Not rebooting automatically - reboot manually when convenient."
else
  echo "[$(date)] No reboot required."
fi

echo "===== [$(date)] Done ====="
