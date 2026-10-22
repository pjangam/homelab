#!/bin/bash
# Download speed and ping from the wol Pi through the router vs through xero.
# Run on xero from a real terminal (asks for the Pi's sudo password once):
#   projects/lan-gateway/compare_gateways.sh [rounds]
# Alternates the Pi's default gateway each round so both see the same
# conditions (compare_gateways_remote.sh does the work there), and always
# leaves it on the router. Ping is p50/p95/max of 20 samples, not an average.
set -euo pipefail
rounds=${1:-3}
url=https://proof.ovh.net/files/10Mb.dat
b64=$(base64 -w0 "$(dirname "$0")/compare_gateways_remote.sh")
ssh -t wol-sender "echo $b64 | base64 -d > /tmp/compare_gateways_remote.sh && sudo bash /tmp/compare_gateways_remote.sh $rounds $url; rm -f /tmp/compare_gateways_remote.sh"
