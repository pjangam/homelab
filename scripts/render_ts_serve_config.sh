#!/usr/bin/env bash
# Renders a tailscale-sidecar serve-config.json from ts-serve-config.template.json.
#
# Every tailscale sidecar in docker-compose.yml (ha-tailscale, ntfy-tailscale)
# wants the same shape: terminate HTTPS on :443 with a Tailscale-provisioned,
# auto-renewing cert, and proxy / to one upstream. The ONLY thing that differs
# between them is that upstream, so it is the only parameter here.
#
# Two different substitutions are in play, deliberately marked differently:
#   @@UPSTREAM@@      - replaced HERE, at render time, by this script.
#   ${TS_CERT_DOMAIN} - left INTACT in the output on purpose. The tailscale
#                       container (containerboot) substitutes it at runtime
#                       with the node's own cert domain. Do not expand it here.
#
# Usage:
#   scripts/render_ts_serve_config.sh http://ntfy:80 ts-ntfy-config/serve-config.json
set -euo pipefail
cd "$(dirname "$0")/.."

upstream="${1:?usage: render_ts_serve_config.sh <upstream-url> <output-file>}"
outfile="${2:?usage: render_ts_serve_config.sh <upstream-url> <output-file>}"

# Substitute with awk rather than sed so a URL containing / or & needs no escaping.
awk -v up="$upstream" '{ gsub(/@@UPSTREAM@@/, up); print }' \
    ts-serve-config.template.json > "$outfile.tmp"

python3 -m json.tool "$outfile.tmp" >/dev/null  # fail loudly on malformed JSON
mv "$outfile.tmp" "$outfile"
echo "rendered $outfile (upstream: $upstream)"
