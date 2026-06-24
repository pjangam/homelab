#!/usr/bin/env bash
set -euo pipefail

HOMELAB_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Step 1: Unmount sda if mounted ==="
sudo umount /tmp/sda2-check 2>/dev/null || true

echo "=== Step 2: Install ZFS userspace tools (no DKMS) ==="
if ! command -v zfs &>/dev/null; then
  sudo apt install -y zfsutils-linux
else
  echo "ZFS already installed, skipping."
fi

echo "=== Step 3: Wipe sda and create ZFS pool ==="
if zpool list datapool &>/dev/null; then
  echo "Pool 'datapool' already exists, skipping."
else
  sudo wipefs -a /dev/sda
  sudo zpool create -f datapool /dev/sda
fi

echo "=== Step 4: Create ZFS datasets ==="
sudo zfs create -p datapool/immich-upload
sudo zfs create -p datapool/immich-db
sudo chown -R pramod:pramod /datapool/immich-upload /datapool/immich-db

echo "=== Step 5: Add Immich env vars ==="
if grep -q "UPLOAD_LOCATION" "$HOMELAB_DIR/.env"; then
  echo "Immich env vars already present, skipping."
else
  DB_PASS=$(openssl rand -base64 24)
  cat >> "$HOMELAB_DIR/.env" <<EOF
UPLOAD_LOCATION=/datapool/immich-upload
DB_DATA_LOCATION=/datapool/immich-db
DB_PASSWORD=${DB_PASS}
DB_USERNAME=immich
DB_DATABASE_NAME=immich
IMMICH_VERSION=release
EOF
  echo "Added Immich env vars (DB password generated)."
fi

echo "=== Step 6: Uncomment Immich services in docker-compose.yml ==="
cd "$HOMELAB_DIR"
sed -i '/^  #  immich-server:/,/^  #### photos servers end/s/^  #//' docker-compose.yml
sed -i '/^  #immich-machine-learning:/,/^  #$/s/^  #//' docker-compose.yml

echo "=== Step 7: Start services ==="
sudo docker compose up -d

echo "=== Step 8: Verify ==="
echo "ZFS pool:"
zpool status datapool
echo ""
echo "ZFS datasets:"
zfs list
echo ""
echo "Waiting for containers to start..."
sleep 10
sudo docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "immich|redis|postgres"
echo ""
echo "Immich should be available at http://192.168.1.123:2283"
