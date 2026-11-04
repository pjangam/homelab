#!/usr/bin/env bash
# Nightly: regenerate "play <song>" from the Spotify liked songs and, only if
# the list changed, reload HA's automations and retrain Speech-to-Phrase
# (~30s, during which the satellites hear nothing - hence the night slot).
#   crontab: 30 4 * * * .../projects/voice-assistant/sync_spotify_songs.sh >> .../spotify-songs.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . ./.env.healthcheck; set +a
files=(projects/voice-assistant/custom_sentences/en/songs.yaml projects/voice-assistant/packages/spotify_songs.yaml)
before=$(cat "${files[@]}" 2>/dev/null | md5sum)
echo "$(date -Is) $(projects/voice-assistant/spotify_library.py)"
[ "$(cat "${files[@]}" | md5sum)" != "$before" ] || { echo "$(date -Is) unchanged"; exit 0; }
H=(-H "Authorization: Bearer $HA_TOKEN" -H 'Content-Type: application/json')
check=$(curl -sf -X POST "${H[@]}" http://localhost:8123/api/config/core/check_config)
case $check in *'"valid"'*) ;; *) echo "$(date -Is) HA config check failed: $check"; exit 1;; esac
curl -sf -o /dev/null -X POST "${H[@]}" -d '{}' http://localhost:8123/api/services/automation/reload
docker restart speech-to-phrase >/dev/null
echo "$(date -Is) changed: automations reloaded, speech-to-phrase retraining"
