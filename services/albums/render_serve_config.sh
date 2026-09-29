#!/usr/bin/env bash
# Renders services/tailscale/albums/serve-config.json for the albums-tailscale
# sidecar: HTTPS on :443, Funnel on (public internet, no Tailscale needed to
# view), and ONE handler - the secret album path - proxied to albums-gallery.
# Every other path, including /, is a Tailscale 404 and never reaches copyparty.
#
# Not tools/network/render_ts_serve_config.sh because that one mounts "/" and
# the output is committed; this one carries the secret path from .env, so the
# output is gitignored.
#
# ${TS_CERT_DOMAIN} is left intact on purpose - containerboot substitutes it.
# AllowFunnel is keyed by host:port, never a plain bool (a bare bool crash-loops
# the container - see PROJECTS.md, ntfy sidecar).
#
# Usage: services/albums/render_serve_config.sh && docker compose restart albums-tailscale
set -euo pipefail
cd "$(dirname "$0")/../.."

secret=$(grep -E '^OJASWI_ALBUM_PATH=' .env | cut -d= -f2-)
[[ -n "$secret" ]] || { echo "OJASWI_ALBUM_PATH missing from .env" >&2; exit 1; }

out=services/tailscale/albums/serve-config.json
mkdir -p "$(dirname "$out")"
cat > "$out.tmp" <<EOF
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "\${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/$secret/": {
          "Proxy": "http://albums-gallery:3923"
        }
      }
    }
  },
  "AllowFunnel": {
    "\${TS_CERT_DOMAIN}:443": true
  }
}
EOF
python3 -m json.tool "$out.tmp" >/dev/null
mv "$out.tmp" "$out"
echo "rendered $out"
echo "album URL: https://albums.$(grep -E '^TAILNET_SUFFIX=' .env | cut -d= -f2-)/$secret/"
