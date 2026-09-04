#!/usr/bin/env bash
# Shared self-hosted ntfy alert sender. Source this, then call:
#   push_ntfy "title" "body" [priority] [tags]
# Priority defaults to 4 (high), tags to "warning".
#
# Requires NTFY_CLAWLIGHT_TOKEN in the environment (from .env.ntfy). If it is
# unset the call is a silent no-op, so scripts that also run on machines
# without ntfy configured keep working unchanged.
#
# Publishes over loopback rather than the tailnet URL: no TLS dependency, the
# token never leaves the host, and it still works if the tailnet is degraded.
# Always returns success - an alert that cannot be sent must never take down
# the watchdog or healthcheck that was trying to send it.
#
# Companion to scripts/send_email.sh; callers generally send both, since email
# is easy to miss on a phone and push is easy to miss in an inbox.
push_ntfy() {
  [ -n "${NTFY_CLAWLIGHT_TOKEN:-}" ] || return 0
  curl -sS -m 10 -o /dev/null \
    -H "Authorization: Bearer $NTFY_CLAWLIGHT_TOKEN" \
    -H "Title: $1" \
    -H "Priority: ${3:-4}" \
    -H "Tags: ${4:-warning}" \
    -d "$2" \
    "http://127.0.0.1:8127/clawlight" || true
}
