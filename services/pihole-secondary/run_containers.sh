#!/usr/bin/env bash
# Runs ON THE WOL PI (copied to ~/homelab/services/pihole-secondary/ by
# deploy_pi.sh, which is what you normally run - from xero). (Re)creates the
# two containers of the secondary Pi-hole:
#
#   pihole       - DNS on :53, admin UI on :8081, host networking (real client
#                  IPs in the query log, no port mapping to get wrong)
#   nebula-sync  - copies xero's Pi-hole config to this one and re-runs
#                  gravity, at start and every 6h
#
# Idempotent: pulls the current images and replaces both containers. Pi-hole's
# data lives in ~/pihole-secondary/etc-pihole, so a re-run keeps it.
#
# Secrets come from ~/pihole-secondary.env (mode 600, never in git), written by
# deploy_pi.sh:
#   FTLCONF_webserver_api_password=<pw>
#   PRIMARY=http://192.168.1.123:8081|<pw>
#   REPLICAS=http://127.0.0.1:8081|<pw>
# Both containers get the whole file; each ignores the other's variables.
set -euo pipefail

ENV_FILE="$HOME/pihole-secondary.env"
DATA="$HOME/pihole-secondary/etc-pihole"
SYNC_CRON="${SYNC_CRON:-0 */6 * * *}"

[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE - run deploy_pi.sh from xero" >&2; exit 1; }
mkdir -p "$DATA"

docker pull -q pihole/pihole:latest
docker pull -q ghcr.io/lovelaze/nebula-sync:latest
docker rm -f nebula-sync pihole >/dev/null 2>&1 || true

# Settings forced by FTLCONF_ variables are read-only in Pi-hole v6, so the
# Teleporter import from xero cannot override them. They are the ones that
# must differ from xero's:
#   webserver.port  - 8081 here; xero's container uses 80 behind a port map
#   listeningMode   - LOCAL: on host networking ALL would answer anyone who
#                     can reach the Pi; LOCAL answers the LAN subnet only
#   ntp.*           - off: xero's config has Pi-hole's NTP server on, which on
#                     host networking would grab :123 on the Pi
#   dhcp.active     - off, belt and braces; the router does DHCP
# --dns 1.1.1.1: the Pi's own resolv.conf points at xero, and gravity has to
# download lists while xero is down too.
docker run -d --name pihole \
  --network host \
  --restart unless-stopped \
  --dns 1.1.1.1 \
  --env-file "$ENV_FILE" \
  -e TZ=Asia/Kolkata \
  -e 'FTLCONF_webserver_port=8081o,[::]:8081o' \
  -e FTLCONF_dns_listeningMode=LOCAL \
  -e FTLCONF_ntp_ipv4_active=false \
  -e FTLCONF_ntp_ipv6_active=false \
  -e FTLCONF_ntp_sync_active=false \
  -e FTLCONF_dhcp_active=false \
  -v "$DATA:/etc/pihole" \
  pihole/pihole:latest >/dev/null

# Host networking so the replica is simply 127.0.0.1:8081.
#
# Selective sync, not FULL_SYNC. A full sync PATCHes every config section, and
# Pi-hole answers 400 ("Config items set via environment variables cannot be
# changed via the API") for the dns, ntp and webserver sections because of the
# FTLCONF_ overrides above - the whole sync then fails (seen 2026-10-06). So:
# every gravity table (adlists, allow/deny domains, groups, clients), and the
# config sections that matter for answering DNS, minus listeningMode. Not
# synced: ntp, dhcp and webserver (forced above), debug.
docker run -d --name nebula-sync \
  --network host \
  --restart unless-stopped \
  --env-file "$ENV_FILE" \
  -e TZ=Asia/Kolkata \
  -e FULL_SYNC=false \
  -e SYNC_CONFIG_DNS=true \
  -e SYNC_CONFIG_DNS_EXCLUDE=listeningMode \
  -e SYNC_CONFIG_RESOLVER=true \
  -e SYNC_CONFIG_DATABASE=true \
  -e SYNC_CONFIG_MISC=true \
  -e SYNC_GRAVITY_GROUP=true \
  -e SYNC_GRAVITY_AD_LIST=true \
  -e SYNC_GRAVITY_AD_LIST_BY_GROUP=true \
  -e SYNC_GRAVITY_DOMAIN_LIST=true \
  -e SYNC_GRAVITY_DOMAIN_LIST_BY_GROUP=true \
  -e SYNC_GRAVITY_CLIENT=true \
  -e SYNC_GRAVITY_CLIENT_BY_GROUP=true \
  -e RUN_GRAVITY=true \
  -e "CRON=$SYNC_CRON" \
  -e CLIENT_RETRY_DELAY_SECONDS=10 \
  ghcr.io/lovelaze/nebula-sync:latest >/dev/null

docker image prune -f >/dev/null
docker ps --filter name=pihole --filter name=nebula-sync --format '{{.Names}}\t{{.Status}}'
