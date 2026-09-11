#!/usr/bin/env bash
# Creates the ntfy users, ACLs and publish tokens for the notification topics.
#
# ntfy has no web UI for user management (the known friction point noted in
# PROJECTS.md), so this is the CLI equivalent, made idempotent and repeatable
# rather than a one-off session of docker exec commands.
#
# Two topics, deliberately separate so agent-status pings and infrastructure
# alerts don't share one stream - they want different attention and different
# mute settings. clawlight can be noisy and is safe to silence while you work;
# a health alert is the opposite:
#   clawlight       - agent needs input (clawlight/server.py)
#   homelab-health  - healthcheck.sh / watchdog alerts (scripts/push_ntfy.sh)
#   homelab-updates - Watchtower container updates. Its own topic because it
#                     is informational, not a fault: you want to be able to
#                     mute "a container was updated" without muting "ZFS is
#                     degraded". Published at low priority for the same reason.
#
# Three principals, split so a leaked publisher token cannot read your
# notification history, and so neither publisher can write to the other's
# topic:
#   pramod      - read-write on both topics. This is what the phone app logs
#                 in as, so one login sees everything.
#   clawlight   - write-only on clawlight, used via a token not a password.
#   healthcheck - write-only on homelab-health, likewise.
#   watchtower  - write-only on homelab-updates, likewise. Unlike the other
#                 two this token is consumed by a CONTAINER, so it also has
#                 to reach docker-compose.yml - see the .env upsert below.
#
# NOTE on the -e flags below: `docker exec` does NOT forward the host's
# environment into the container, so NTFY_PASSWORD has to be handed over
# explicitly. Setting it only on the host side leaves ntfy prompting for a
# password on stdin and the script hangs.
#
# Secrets are written to .env.ntfy (gitignored, mode 600). Re-running reuses the
# credentials already in that file rather than churning them, so it is safe to
# run repeatedly.
set -euo pipefail
cd "$(dirname "$0")/.."

ENVFILE=".env.ntfy"
TOPIC="clawlight"
HEALTH_TOPIC="homelab-health"
UPDATES_TOPIC="homelab-updates"

nt() { docker exec -i ntfy ntfy "$@" </dev/null; }

docker ps --format '{{.Names}}' | grep -qx ntfy || { echo "ntfy container is not running" >&2; exit 1; }

# shellcheck disable=SC1090
[ -f "$ENVFILE" ] && . "$ENVFILE"

GENERATED_PASSWORD=0
if [ -z "${NTFY_ADMIN_PASSWORD:-}" ]; then
  NTFY_ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24)"
  GENERATED_PASSWORD=1
  echo "generated a new password for user 'pramod'"
fi

# --- users (--ignore-exists makes these no-ops on re-run) -------------------
docker exec -i -e NTFY_PASSWORD="$NTFY_ADMIN_PASSWORD" ntfy \
  ntfy user add --ignore-exists pramod </dev/null

# The clawlight account authenticates by token only, so its password is a
# throwaway that is generated and immediately discarded.
docker exec -i -e NTFY_PASSWORD="$(head -c 32 /dev/urandom | base64)" ntfy \
  ntfy user add --ignore-exists clawlight </dev/null

# Same deal for the healthcheck publisher - token-only, throwaway password.
docker exec -i -e NTFY_PASSWORD="$(head -c 32 /dev/urandom | base64)" ntfy \
  ntfy user add --ignore-exists healthcheck </dev/null

# And for Watchtower's container-update notices.
docker exec -i -e NTFY_PASSWORD="$(head -c 32 /dev/urandom | base64)" ntfy \
  ntfy user add --ignore-exists watchtower </dev/null

# If we generated a password this run but the user already existed (e.g. a
# previous run created the account and then failed before writing .env.ntfy),
# the stored password and the one we are about to record would disagree. There
# is no way to read the old one back, so force it to match what gets written.
if [ "$GENERATED_PASSWORD" = 1 ]; then
  docker exec -i -e NTFY_PASSWORD="$NTFY_ADMIN_PASSWORD" ntfy \
    ntfy user change-pass pramod </dev/null
fi

# --- ACLs (ntfy access overwrites the rule for that user+topic, so idempotent) --
nt access pramod    "$TOPIC"        rw
nt access clawlight "$TOPIC"        write-only
nt access pramod    "$HEALTH_TOPIC" rw
nt access healthcheck "$HEALTH_TOPIC" write-only
nt access pramod     "$UPDATES_TOPIC" rw
nt access watchtower "$UPDATES_TOPIC" write-only
# Neither publisher gets any access to the other's topic - no rule is denial
# under `auth-default-access: deny-all`, so there is nothing to revoke.

# --- publish token ----------------------------------------------------------
if [ -z "${NTFY_CLAWLIGHT_TOKEN:-}" ]; then
  # No --expires flag at all is the never-expiring form ("--expires=never" is
  # not a thing - it fails with "unable to parse duration"). The token inherits
  # the clawlight user's permissions, so it stays write-only.
  NTFY_CLAWLIGHT_TOKEN="$(nt token add --label='clawlight publisher' clawlight \
                          | grep -oE 'tk_[A-Za-z0-9]+' | head -1)"
  [ -n "$NTFY_CLAWLIGHT_TOKEN" ] || { echo "failed to create publish token" >&2; exit 1; }
  echo "created publish token for user 'clawlight'"
fi

if [ -z "${NTFY_HEALTH_TOKEN:-}" ]; then
  NTFY_HEALTH_TOKEN="$(nt token add --label='healthcheck publisher' healthcheck \
                       | grep -oE 'tk_[A-Za-z0-9]+' | head -1)"
  [ -n "$NTFY_HEALTH_TOKEN" ] || { echo "failed to create health publish token" >&2; exit 1; }
  echo "created publish token for user 'healthcheck'"
fi

if [ -z "${NTFY_UPDATES_TOKEN:-}" ]; then
  NTFY_UPDATES_TOKEN="$(nt token add --label='watchtower publisher' watchtower \
                        | grep -oE 'tk_[A-Za-z0-9]+' | head -1)"
  [ -n "$NTFY_UPDATES_TOKEN" ] || { echo "failed to create updates publish token" >&2; exit 1; }
  echo "created publish token for user 'watchtower'"
fi

# Tapping the notification should open the clawlight page. Kept here rather
# than in the committed systemd unit so the tailnet name stays out of git,
# same reasoning as the Caddyfile's {$TAILNET_SUFFIX}.
if [ -z "${CLAWLIGHT_PUBLIC_URL:-}" ]; then
  # shellcheck disable=SC1091
  [ -f .env ] && . ./.env
  CLAWLIGHT_PUBLIC_URL="https://xero.${TAILNET_SUFFIX}/clawlight/"
fi

umask 077
cat > "$ENVFILE" <<ENVEOF
# ntfy credentials - generated by scripts/setup_ntfy_users.sh. Gitignored.
# Loaded by clawlight-server.service via EnvironmentFile.
# NTFY_ADMIN_PASSWORD  : log in as user 'pramod' in the mobile app / web UI.
# NTFY_CLAWLIGHT_TOKEN : write-only publish token used by clawlight/server.py.
# NTFY_HEALTH_TOKEN    : write-only publish token used by scripts/push_ntfy.sh
#                        for the separate homelab-health topic.
# NTFY_UPDATES_TOKEN   : write-only publish token used by watchtower (via
#                        docker-compose.yml) for the homelab-updates topic.
#                        Also mirrored into .env, which is where compose
#                        reads it from.
# CLAWLIGHT_PUBLIC_URL : where tapping the notification takes you.
#
# Subscribe the phone app to ALL THREE topics (clawlight, homelab-health,
# homelab-updates) - logging in as 'pramod' grants access but does not
# subscribe you.
NTFY_ADMIN_PASSWORD=$NTFY_ADMIN_PASSWORD
NTFY_CLAWLIGHT_TOKEN=$NTFY_CLAWLIGHT_TOKEN
NTFY_HEALTH_TOKEN=$NTFY_HEALTH_TOKEN
NTFY_UPDATES_TOKEN=$NTFY_UPDATES_TOKEN
CLAWLIGHT_PUBLIC_URL=$CLAWLIGHT_PUBLIC_URL
ENVEOF
chmod 600 "$ENVFILE"

# Watchtower publishes from inside a container, so its token has to be
# available to docker-compose.yml, which only auto-loads `.env` - not this
# file. Mirror it there rather than hardcoding a secret into the committed
# compose file, the same way PIHOLE_PASSWORD and TS_AUTHKEY_HA already work.
# Upsert in place so the rest of .env is untouched.
if [ -f .env ] && grep -q '^NTFY_UPDATES_TOKEN=' .env; then
  sed -i "s|^NTFY_UPDATES_TOKEN=.*|NTFY_UPDATES_TOKEN=$NTFY_UPDATES_TOKEN|" .env
  echo "updated NTFY_UPDATES_TOKEN in .env"
else
  printf '\n# Read by docker-compose.yml for watchtower ntfy alerts (see .env.ntfy).\nNTFY_UPDATES_TOKEN=%s\n' \
    "$NTFY_UPDATES_TOKEN" >> .env
  echo "added NTFY_UPDATES_TOKEN to .env"
fi

echo
echo "--- users and ACLs ---"
nt access
echo
echo "credentials written to $ENVFILE (mode 600)"
