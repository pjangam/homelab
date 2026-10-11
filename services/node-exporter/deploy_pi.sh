#!/usr/bin/env bash
# Run this ON XERO. (Re)creates the node_exporter container on the wol Pi,
# which xero's Prometheus scrapes every 5s for the Grafana dashboards
# (services/grafana/README.md). xero's own node_exporter is in
# docker-compose.yml; the Pi has no compose file, so it is one docker run,
# the same way services/pihole-secondary/run_containers.sh does its two.
#
# Listens on the Pi's LAN address only (not the tailnet): read-only host
# metrics, and Prometheus on xero is the only reader. No sudo: the Pi's
# user is in the docker group. Idempotent - re-run to change version or flags.
set -euo pipefail

PI="pramod@192.168.1.124"
IMAGE="prom/node-exporter:v1.12.1"

ssh "$PI" bash -s -- "$IMAGE" <<'REMOTE'
set -euo pipefail
image=$1
docker pull -q "$image"
docker rm -f node-exporter >/dev/null 2>&1 || true
docker run -d --name node-exporter --restart unless-stopped \
  --net host --pid host -v /:/host:ro,rslave \
  "$image" \
  --path.rootfs=/host \
  --web.listen-address=192.168.1.124:9100 \
  '--collector.filesystem.mount-points-exclude=^/(dev|proc|run|sys|var/lib/docker/.+|host/var/lib/docker/.+)($|/)' >/dev/null
sleep 3
docker ps --filter name=node-exporter --format '{{.Names}} {{.Image}} {{.Status}}'
REMOTE
curl -s -m 5 http://192.168.1.124:9100/metrics | grep -c '^node_' | sed 's/^/node_ metric lines from xero: /'
