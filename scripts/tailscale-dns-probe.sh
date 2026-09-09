#!/usr/bin/env bash
# Diagnose "Tailscale can't reach configured DNS server" warnings on tailnet peers.
#
# The tailnet's global nameserver is xero's tailscale IP (100.70.215.25), which
# DNATs into the pihole container. This captures what actually arrives on the
# tailscale0 interface for port 53, so we can tell a client-side problem
# (no packets arrive) from a server-side one (queries arrive, no replies).
#
# Usage: scripts/tailscale-dns-probe.sh [seconds]   (default 60)

set -euo pipefail
DURATION="${1:-60}"

echo "== Capturing DNS on tailscale0 for ${DURATION}s =="
echo "(queries from 100.x peers should appear here if they reach xero at all)"
echo

docker run --rm --net=host --privileged alpine:latest sh -c "
  apk add -q tcpdump >/dev/null 2>&1
  timeout ${DURATION} tcpdump -ni tailscale0 -l 'port 53' 2>/dev/null || true
"
