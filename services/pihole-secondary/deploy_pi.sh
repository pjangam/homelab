#!/usr/bin/env bash
# Run this ON XERO. Deploys the secondary Pi-hole (and nebula-sync) to the wol
# Pi. See README.md in this folder.
#
#   deploy_pi.sh            first deploy, or update to the latest images
#   deploy_pi.sh --rekey    also rewrite ~/pihole-secondary.env on the Pi from
#                           PIHOLE_PASSWORD in xero's .env (after changing it)
#
# The Pi has no repo clone, so run_containers.sh is copied to
# ~/homelab/services/pihole-secondary/ there and run over ssh. No sudo needed:
# pramod is in the Pi's docker group.
set -euo pipefail

PI="pramod@192.168.1.124"
PRIMARY_URL="http://192.168.1.123:8081"
REPLICA_URL="http://127.0.0.1:8081"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PI_DIR="homelab/services/pihole-secondary"

rekey=0
[[ "${1:-}" == "--rekey" ]] && rekey=1

if (( rekey )) || ! ssh -o BatchMode=yes "$PI" test -s pihole-secondary.env; then
  pw=$(grep '^PIHOLE_PASSWORD=' "$REPO/.env" | cut -d= -f2-)
  [[ -n "$pw" ]] || { echo "PIHOLE_PASSWORD not found in $REPO/.env" >&2; exit 1; }
  case "$pw" in *'|'*|*','*) echo "password contains | or , which nebula-sync's PRIMARY/REPLICAS cannot carry" >&2; exit 1;; esac
  # Over stdin, so the password never appears on a command line or in output.
  printf 'FTLCONF_webserver_api_password=%s\nPRIMARY=%s|%s\nREPLICAS=%s|%s\n' \
      "$pw" "$PRIMARY_URL" "$pw" "$REPLICA_URL" "$pw" |
    ssh -o BatchMode=yes "$PI" 'umask 077 && cat > pihole-secondary.env && chmod 600 pihole-secondary.env'
  echo "wrote ~/pihole-secondary.env on the Pi"
fi

ssh -o BatchMode=yes "$PI" "mkdir -p $PI_DIR"
scp -q "$REPO/services/pihole-secondary/run_containers.sh" "$PI:$PI_DIR/"
ssh -o BatchMode=yes "$PI" "bash $PI_DIR/run_containers.sh"
