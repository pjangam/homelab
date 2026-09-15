#!/usr/bin/env bash
# Is spotifyd actually advertising itself as a Spotify Connect device?
#
# This is the signal that matters, and the one nothing was watching. spotifyd
# can be authenticated, connected, and `active (running)` while advertising
# nothing at all - that exact state lasted five days in Sept 2026 and only
# surfaced when an HA script failed. See
# incidents/2026-09-11-spotifyd-zeroconf-lost-to-boot-race.md.
#
# Checking the advertisement rather than a log line is deliberate: it's the
# end state the rest of the chain (Spotify device list -> spotcast entity ->
# HA scripts) depends on, so it catches any cause, including whatever breaks
# libmdns next. Both known causes so far - an orphaned Docker network
# (2026-09-02) and a boot race (2026-09-11) - produced the same invisible
# result and would both be caught here.
#
# Exit codes are three-way on purpose, because "not advertising" and "not
# supposed to be advertising" deserve different treatment from a caller:
#   0 - advertising (healthy)
#   1 - NOT advertising while spotifyd is running (the actual fault)
#   2 - can't tell / not applicable: spotifyd isn't running, or avahi-daemon
#       isn't available to ask. Callers must not alert on this - a stopped
#       spotifyd is already covered by the failed-unit check, and blaming
#       spotifyd for a dead avahi would point at the wrong service.
set -uo pipefail

TIMEOUT="${1:-8}"
SERVICE_NAME="${2:-$(hostname)}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# Only meaningful if spotifyd is meant to be up right now.
if ! systemctl --user is-active --quiet spotifyd.service 2>/dev/null; then
  echo "spotifyd is not running - advertisement check not applicable" >&2
  exit 2
fi

command -v avahi-browse >/dev/null 2>&1 || { echo "avahi-browse not installed" >&2; exit 2; }
systemctl is-active --quiet avahi-daemon 2>/dev/null || { echo "avahi-daemon not running - can't verify" >&2; exit 2; }

# -p parseable, -t terminate after the existing cache is dumped. Fields are
# ;iface;proto;NAME;type;domain - match NAME exactly so a neighbour called
# e.g. "xero-speaker" can't stand in for us.
if timeout "$TIMEOUT" avahi-browse -pt _spotify-connect._tcp 2>/dev/null \
     | awk -F';' -v want="$SERVICE_NAME" '$1 == "+" && $4 == want {found=1} END {exit !found}'; then
  exit 0
fi

echo "spotifyd is running but not advertising _spotify-connect._tcp as '$SERVICE_NAME'" >&2
exit 1
