#!/usr/bin/env bash
# Blocks until the host has a routable (global-scope, non-loopback) IPv4
# address, or until TIMEOUT seconds pass.
#
# Exists because `systemd --user` units cannot order themselves against the
# network. `After=network-online.target` in a user unit is silently a no-op:
# that target only exists in the *system* manager, so the user manager
# resolves it to "not-found" and ignores the ordering entirely. The user
# manager starts a second or two after boot, well before NetworkManager has
# finished bringing enp1s0 up.
#
# For most daemons that's harmless - they retry. For spotifyd it is not:
# its libmdns zeroconf server enumerates interfaces exactly once at startup,
# and if none are usable it logs
#   [ERROR] libmdns error: Setting up dns-sd failed: No such device (os error 19)
# and then runs forever, healthy in every other respect, never advertising
# itself as a Spotify Connect device. See
# incidents/2026-09-11-spotifyd-zeroconf-lost-to-boot-race.md.
#
# Used as an ExecStartPre guard. Prefixed with `-` in the unit so a timeout
# degrades to "start anyway" rather than refusing to start the service.
set -uo pipefail

TIMEOUT="${1:-45}"
deadline=$(( $(date +%s) + TIMEOUT ))

while [ "$(date +%s)" -lt "$deadline" ]; do
  # `scope global` excludes loopback and link-local (169.254/fe80) addresses,
  # which are present but useless for advertising a reachable service.
  if ip -4 -brief addr show scope global up 2>/dev/null | grep -q .; then
    exit 0
  fi
  sleep 1
done

echo "wait_for_network: no global-scope IPv4 address after ${TIMEOUT}s" >&2
exit 1
