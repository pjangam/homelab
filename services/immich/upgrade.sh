#!/usr/bin/env bash
# Moves Immich to a new pinned version, following README.md's "Upgrading":
# stop the server and ML containers, snapshot the library and database,
# change IMMICH_VERSION in .env, start them again. Postgres and Redis keep
# running. Read the release notes and compare the upstream compose file
# and example.env first - this script does not do that part.
#
#   services/immich/upgrade.sh v3.3.4
#
# Run it from a real terminal: the snapshot needs sudo's password prompt.
# Pull the images first (docker pull ghcr.io/immich-app/immich-server:vX.Y.Z
# and immich-machine-learning) so Immich is down only for seconds.
set -euo pipefail

new=${1:?usage: $0 vX.Y.Z}
[[ $new =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a version tag: $new" >&2; exit 1; }

repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"

old=$(sed -n 's/^IMMICH_VERSION=//p' .env)
[[ -n $old ]] || { echo "IMMICH_VERSION not found in .env" >&2; exit 1; }
[[ $old != "$new" ]] || { echo "already on $new" >&2; exit 1; }

for img in immich-server immich-machine-learning; do
  docker image inspect "ghcr.io/immich-app/$img:$new" >/dev/null 2>&1 \
    || echo "note: $img:$new not pulled yet; up -d will pull it while Immich is down"
done

snap="pre-$new"
echo "Upgrading Immich $old -> $new (snapshot @$snap)"

docker compose stop immich-server immich-machine-learning
sudo zfs snapshot "datapool/immich-db@$snap" "datapool/immich-upload@$snap"
sed -i "s/^IMMICH_VERSION=.*/IMMICH_VERSION=$new/" .env
docker compose up -d immich-server immich-machine-learning

echo "Started. Watch the migration with: docker logs -f immich_server"
echo "Roll back: stop both, sudo zfs rollback datapool/immich-db@$snap, set IMMICH_VERSION=$old, up -d"
