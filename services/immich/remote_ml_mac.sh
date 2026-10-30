#!/usr/bin/env bash
# Runs Immich's machine-learning container on the personal 2019 MacBook, so
# xero's server can send it the ML backlog (remote machine learning: the Mac
# gets preview images over HTTP and never sees the library). Written
# 2026-10-30 for the ~12.5k-photo face detection / smart search backlog; the
# i7-9750H is roughly 4-6x xero's N5105. Run it ON THE MAC, then on xero:
#   services/immich/remote_ml.sh on
#
#   services/immich/remote_ml_mac.sh v3.3.5   # start, then keep the Mac awake
#   services/immich/remote_ml_mac.sh stop     # when the backlog is done
#
# The version must match xero's IMMICH_VERSION (in xero's .env). Needs Docker
# (Docker Desktop or OrbStack) running. Capped at 6 of the 12 threads: the
# 16" 2019 runs hot under sustained load. Keep the lid open, on a stand,
# plugged in. Ctrl-C ends the keep-awake only; the container keeps running
# until `stop`, and xero falls back to its own ML whenever the Mac is away.
set -euo pipefail

NAME=immich_ml_remote
CPUS=${CPUS:-6}

if [ "${1:-}" = stop ]; then
  docker rm -f "$NAME" && echo "stopped; on xero: services/immich/remote_ml.sh off"
  exit 0
fi
ver=${1:?usage: $0 vX.Y.Z | stop   (vX.Y.Z = IMMICH_VERSION in xero .env)}
[[ $ver =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a version tag: $ver" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is not running - start Docker Desktop / OrbStack first" >&2; exit 1; }

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped --cpus "$CPUS" \
  -p 3003:3003 -v immich-ml-cache:/cache \
  "ghcr.io/immich-app/immich-machine-learning:$ver" >/dev/null
echo "started $NAME ($ver, $CPUS CPUs); waiting for it to answer..."
for _ in $(seq 60); do
  [ "$(curl -s -m 2 http://localhost:3003/ping)" = pong ] && break
  sleep 2
done
[ "$(curl -s -m 2 http://localhost:3003/ping)" = pong ] || { echo "no pong after 2 min: docker logs $NAME" >&2; exit 1; }
echo "answering on :3003. Now on xero: services/immich/remote_ml.sh on"
echo "If xero cannot reach it, allow incoming connections for Docker in macOS's firewall."
echo "Keeping the Mac awake (Ctrl-C to stop keeping it awake; the container keeps running)."
exec caffeinate -dis
