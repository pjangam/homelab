#!/usr/bin/env bash
# Moves Immich to a new pinned version, following README.md's "Upgrading".
#
#   services/immich/upgrade.sh --check          # preflight only, changes nothing
#   services/immich/upgrade.sh                  # upgrade to the latest release
#   services/immich/upgrade.sh v3.4.1           # upgrade to a given release
#
# Preflight (both modes):
#   - resolves "latest" from GitHub releases (skips prereleases)
#   - lists every release between the running and the new version, with links
#   - diffs upstream docker/docker-compose.yml and docker/example.env between
#     the two tags: anything there must be mirrored into our docker-compose.yml
#     / .env by hand first (our compose is not upstream's - see README)
#   - pulls the new server and ML images so Immich is down only for seconds
# Upgrade:
#   - asks for "yes" after the preflight
#   - stops server + ML, snapshots datapool/immich-db and immich-upload as
#     @pre-vX.Y.Z, sets IMMICH_VERSION in .env, starts server + ML + redis
#     (redis so a valkey digest bump in docker-compose.yml applies too)
#   - waits for immich_server to report healthy and prints the migration lines
#
# Run it from a real terminal: the snapshot needs sudo's password prompt.
# Diun posts to ntfy homelab-updates when a new release is out
# (services/container-updates/README.md).
set -euo pipefail

check_only=false
if [[ ${1:-} == --check ]]; then check_only=true; shift; fi
new=${1:-latest}

repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
api=https://api.github.com/repos/immich-app/immich
raw=https://raw.githubusercontent.com/immich-app/immich

old=$(sed -n 's/^IMMICH_VERSION=//p' .env)
[[ -n $old ]] || { echo "IMMICH_VERSION not found in .env" >&2; exit 1; }

if [[ $new == latest ]]; then
  new=$(curl -fsS --retry 3 --max-time 60 "$api/releases/latest" | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')
fi
[[ $new =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a version tag: $new" >&2; exit 1; }
if [[ $old == "$new" ]]; then echo "Already on $new."; exit 0; fi

echo "Immich: running $old, target $new"
echo
echo "== Releases after $old up to $new (read each for breaking changes):"
curl -fsS --retry 3 --max-time 60 "$api/releases?per_page=50" | python3 -c '
import sys, json
old, new = sys.argv[1], sys.argv[2]
v = lambda t: tuple(int(x) for x in t.lstrip("v").split("."))
for r in sorted(json.load(sys.stdin), key=lambda r: v(r["tag_name"]) if r["tag_name"].count(".") == 2 else (0,)):
    t = r["tag_name"]
    if r["prerelease"] or t.count(".") != 2 or not (v(old) < v(t) <= v(new)):
        continue
    body = r["body"] or ""
    flags = [w for w in ("breaking", "BREAKING", "migration", "deprecat") if w in body]
    line = "  %s  %s  %s" % (t, r["published_at"][:10], r["html_url"])
    print(line + ("   <- mentions: " + ", ".join(flags) if flags else ""))
' "$old" "$new"

echo
changed=false
for f in docker/docker-compose.yml docker/example.env; do
  d=$(diff <(curl -fsS --retry 3 --max-time 60 "$raw/$old/$f") <(curl -fsS --retry 3 --max-time 60 "$raw/$new/$f") || true)
  if [[ -n $d ]]; then
    changed=true
    echo "== Upstream $f changed $old -> $new:"
    echo "$d" | sed 's/^/    /'
  else
    echo "== Upstream $f: no change"
  fi
done
if $changed; then
  echo
  echo "   Mirror these into docker-compose.yml / .env before upgrading, where they"
  echo "   apply to us (a valkey digest bump: copy it to the redis service)."
fi

echo
echo "== Pulling images"
for img in immich-server immich-machine-learning; do
  docker pull -q "ghcr.io/immich-app/$img:$new"
done

if $check_only; then
  echo
  echo "Preflight done, nothing changed. Upgrade with: services/immich/upgrade.sh $new"
  exit 0
fi

echo
read -rp "Upgrade Immich $old -> $new now? Type yes: " ok
[[ $ok == yes ]] || { echo "Not upgraded."; exit 1; }

snap="pre-$new"
docker compose stop immich-server immich-machine-learning
sudo zfs snapshot "datapool/immich-db@$snap" "datapool/immich-upload@$snap"
sed -i "s/^IMMICH_VERSION=.*/IMMICH_VERSION=$new/" .env
docker compose up -d immich-server immich-machine-learning redis

echo "Waiting for immich_server to become healthy (up to 10 min)..."
for _ in $(seq 120); do
  st=$(docker inspect -f '{{.State.Health.Status}}' immich_server 2>/dev/null || echo missing)
  [[ $st == healthy ]] && break
  sleep 5
done
echo "immich_server: $st"
echo "== Migration log lines:"
docker logs immich_server 2>&1 | grep -i -E 'migrat|error' | tail -20 || true

echo
echo "Done: $old -> $new, snapshots @$snap."
echo "  Check the web UI and the phone app, then record it in services/immich/README.md."
echo "  Remote ML on the Mac, if in use: remote_ml_mac.sh $new"
echo "  Roll back: docker compose stop immich-server immich-machine-learning;"
echo "    sudo zfs rollback datapool/immich-db@$snap; sudo zfs rollback datapool/immich-upload@$snap;"
echo "    set IMMICH_VERSION=$old in .env; docker compose up -d immich-server immich-machine-learning"
echo "  Once happy, drop the previous snapshots: zfs list -t snapshot | grep immich"
