#!/usr/bin/env bash
# A temporary Chromium on xero, viewed from another machine's browser, for
# downloading a Google Takeout straight to datapool when nobody is at xero.
#
#   services/immich/takeout_browser.sh start [folder-under-google-takeout]
#   services/immich/takeout_browser.sh status
#   services/immich/takeout_browser.sh stop      # also deletes the browser profile
#
# Why: Google will not accept exported cookies from another machine (tried
# 2026-11-08: takeout_download.sh is sent to the interactive sign-in page), so
# the sign-in has to happen in a browser on xero itself.
#
# View it from the Mac:
#   ssh -N -L 3001:127.0.0.1:3001 pramod@xero
#   then open https://localhost:3001 and accept the self-signed certificate.
#
# The port is bound to 127.0.0.1 only, so the SSH tunnel is the only way in.
# The profile holds a signed-in Google session: stop this when the download is
# done, which deletes it.
set -euo pipefail

NAME=takeout-browser
IMAGE=linuxserver/chromium:latest
PROFILE=$HOME/.cache/$NAME

case ${1:-} in
  start)
    out=/datapool/google-takeout/${2:-bhakti}
    mkdir -p "$out" "$PROFILE/Downloads"
    docker run -d --name "$NAME" --restart no \
      --security-opt seccomp=unconfined --shm-size 1g \
      -e PUID="$(id -u)" -e PGID="$(id -g)" -e TZ=Asia/Kolkata \
      -p 127.0.0.1:3001:3001 \
      -v "$PROFILE:/config" -v "$out:/config/Downloads" \
      "$IMAGE" >/dev/null
    echo "started; downloads go to $out"
    ;;
  status)
    docker ps -a --filter "name=^$NAME$" --format '{{.Names}}: {{.Status}}'
    ;;
  stop)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    rm -rf "$PROFILE"
    echo "stopped; browser profile deleted"
    ;;
  *)
    sed -n 2,6p "$0"; exit 1
    ;;
esac
