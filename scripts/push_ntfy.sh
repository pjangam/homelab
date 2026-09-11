#!/usr/bin/env bash
# Shared self-hosted ntfy alert sender. Source this, then call:
#   push_ntfy "title" "body" [priority] [tags]
# Priority defaults to 4 (high), tags to "warning".
#
# Publishes to the `homelab-health` topic, kept separate from `clawlight` so
# infrastructure alerts and agent-status pings don't share one stream: you
# want to be able to mute "an agent needs input" while you work without also
# muting "ZFS is degraded". clawlight/server.py still publishes to its own
# topic with its own token.
#
# Requires NTFY_HEALTH_TOKEN in the environment (from .env.ntfy, created by
# scripts/setup_ntfy_users.sh). If it is unset the call is a silent no-op, so
# scripts that also run on machines without ntfy configured keep working
# unchanged. Note the token is write-only on this one topic, so it cannot
# read your history or post to clawlight.
#
# Publishes over loopback rather than the tailnet URL: no TLS dependency, the
# token never leaves the host, and it still works if the tailnet is degraded.
# Always returns success - an alert that cannot be sent must never take down
# the watchdog or healthcheck that was trying to send it.
#
# Companion to scripts/send_email.sh; callers generally send both, since email
# is easy to miss on a phone and push is easy to miss in an inbox.
push_ntfy() {
  [ -n "${NTFY_HEALTH_TOKEN:-}" ] || return 0
  curl -sS -m 10 -o /dev/null \
    -H "Authorization: Bearer $NTFY_HEALTH_TOKEN" \
    -H "Title: $1" \
    -H "Priority: ${3:-4}" \
    -H "Tags: ${4:-warning}" \
    -d "$2" \
    "http://127.0.0.1:8127/homelab-health" || true
}
