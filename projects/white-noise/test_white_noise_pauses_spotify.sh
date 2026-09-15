#!/usr/bin/env bash
# End-to-end check that starting white noise pauses Spotify playing on xero.
# PLAYS REAL AUDIO in the bedroom for ~20s - the track, then the start of the
# brown noise - so run it when that is fine.
#
#   projects/white-noise/test_white_noise_pauses_spotify.sh
#
# What it does: starts script.play_bedroom_track in HA (spotcast -> spotifyd on
# xero), waits for spotifyd's MPRIS player to report Playing, starts
# white-noise.service the same way the HA switch does, and checks the player
# went to Paused. Then stops white noise. Spotify is left paused - that is the
# behaviour under test.
#
# Why end-to-end: the unit's `ExecStartPre=-/usr/bin/playerctl -p spotifyd
# pause` is `-` prefixed, so it can fail every time without anything noticing,
# and "No players found" is also what it logs, legitimately, whenever spotifyd
# has no active Connect session. Only a real playing session tells the two
# apart.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
set -a; . ./.env.healthcheck; set +a
HA="${HA_URL:-http://192.168.1.123:8123}"

status() { playerctl -p spotifyd status 2>/dev/null || echo "none"; }
wait_for() {  # $1 = wanted status, $2 = timeout seconds
  local t=0
  while [ "$(status)" != "$1" ] && [ "$t" -lt "$2" ]; do sleep 1; t=$((t + 1)); done
  [ "$(status)" = "$1" ]
}
fail() { echo "FAIL: $*"; systemctl --user stop white-noise 2>/dev/null; exit 1; }

systemctl --user is-active -q white-noise && fail "white noise is already running - stop it first"

echo "starting a track on xero via HA (script.play_bedroom_track)..."
curl -sf -X POST -H "Authorization: Bearer $HA_TOKEN" -H "Content-Type: application/json" \
  "$HA/api/services/script/play_bedroom_track" -d '{}' >/dev/null || fail "HA script call failed"
wait_for Playing 45 || fail "spotifyd never reported Playing (status: $(status))"
echo "ok   spotifyd is Playing"
sleep 5  # let it actually be audible

since="$(date '+%Y-%m-%d %H:%M:%S')"
echo "starting white-noise.service..."
systemctl --user start white-noise || fail "white-noise.service did not start"
if wait_for Paused 10; then
  echo "ok   spotifyd went to Paused when white noise started"
  rc=0
else
  echo "FAIL spotifyd is '$(status)' after white noise started"
  rc=1
fi
journalctl --user -u white-noise --since "$since" --no-pager | grep -i playerctl | sed 's/^/     journal: /'

sleep 3
systemctl --user stop white-noise
echo "stopped white noise; Spotify left paused"
exit "$rc"
