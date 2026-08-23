#!/bin/bash
# Run on wol-sender (the Pi) via SSH. Starts Node-RED as the Pi's copy of
# the service migrated off xero - see PROJECTS.md "Move some load to the
# Raspberry Pi". Data (flows, credentials, the Miraie AC config) was
# copied from xero's node-red-data Docker volume beforehand; node_modules
# was deleted from that copy first since it was built on xero's x86_64,
# not this Pi's arm64 - the container's own `npm install --prefix /data`
# below rebuilds it correctly for this architecture on first start.
#
# No sudo needed - pramod is in the docker group on this Pi.
set -euo pipefail

docker run -d \
  --name node-red \
  --restart unless-stopped \
  -p 1880:1880 \
  -e TZ=Asia/Kolkata \
  -v /home/pramod/node-red-data:/data \
  --entrypoint sh \
  nodered/node-red:latest \
  -c "until nslookup auth.miraie.in > /dev/null 2>&1; do echo 'waiting for DNS...'; sleep 5; done && npm install --prefix /data && node-red --userDir /data"

echo "Started. Tail logs with: docker logs -f node-red"
