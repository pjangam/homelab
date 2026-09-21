#!/usr/bin/env bash
# Add a Samba user with read-write access to a share on xero.
#
# The user has to go into docker-compose.yml, not into the running
# container: dperson/samba recreates its users from the `-u` flags on every
# start, so anything added with `docker exec ... smbpasswd` disappears the
# next time the container is recreated. This script:
#   1. generates a password and appends SAMBA_PASSWORD_<NAME> to .env
#   2. adds a `-u "<name>;${SAMBA_PASSWORD_<NAME>}"` pair to the samba
#      service's command, and appends <name> to the share's user list
#   3. recreates the container and checks the new login with smbclient
#   4. prints the password once, for Vaultwarden
#
# Usage: services/samba/add_user.sh <name> [share]    (share: phone-uploads)
#   NO_APPLY=1  edit the files and show the diff, but do not restart samba
#   COMPOSE_FILE / ENV_FILE override the paths (used to test on copies)
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
compose=${COMPOSE_FILE:-$repo/docker-compose.yml}
envfile=${ENV_FILE:-$repo/.env}
name=${1:?usage: $0 <name> [share]}
share=${2:-phone-uploads}

[[ $name =~ ^[a-z][a-z0-9_]{0,30}$ ]] ||
    { echo "name must be lowercase letters, digits or _, starting with a letter" >&2; exit 1; }
var="SAMBA_PASSWORD_${name^^}"
grep -q "^$var=" "$envfile" && { echo "$var is already in $envfile" >&2; exit 1; }

# No ; (the flag's field separator) and nothing shell- or yaml-special.
pass=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)

cp "$compose" "$compose.bak"
python3 - "$compose" "$name" "$var" "$share" <<'PY'
import re, sys
path, name, var, share = sys.argv[1:]
lines = open(path).read().split("\n")

# Find the samba service block: from "  samba:" to the next 2-space key.
start = next(i for i, l in enumerate(lines) if l.rstrip() == "  samba:")
end = next((i for i in range(start + 1, len(lines))
            if re.match(r"^  \S|^\S", lines[i])), len(lines))
block = range(start, end)

if any(re.search(rf'"{re.escape(name)};', lines[i]) for i in block):
    sys.exit(f"{name} already has a -u flag in {path}")

# The share's -s value: "<share>;path;browse;ro;guest;users;admins;write;comment"
share_i = next((i for i in block if re.match(rf'^\s*- "{re.escape(share)};', lines[i])), None)
if share_i is None:
    sys.exit(f"no -s flag for share {share!r} in the samba service")
indent = re.match(r"^(\s*)", lines[share_i]).group(1)
value = lines[share_i].strip()[3:-1]           # strip '- "' and '"'
fields = value.split(";")
users = [u for u in fields[5].split(",") if u]
fields[5] = ",".join(users + [name])
lines[share_i] = f'{indent}- "{";".join(fields)}"'

# Insert the -u pair just before the '-s' that precedes the share value.
s_flag = share_i - 1
assert lines[s_flag].strip() == '- "-s"', "expected - \"-s\" right before the share"
lines[s_flag:s_flag] = [f'{indent}- "-u"', f'{indent}- "{name};${{{var}}}"']
open(path, "w").write("\n".join(lines))
PY

printf '%s=%s\n' "$var" "$pass" >> "$envfile"
echo "--- docker-compose.yml changes:"
diff "$compose.bak" "$compose" || true
rm -f "$compose.bak"

if [ -n "${NO_APPLY:-}" ]; then
    echo "NO_APPLY set: files edited, samba not restarted."
    exit 0
fi

cd "$repo"
docker compose up -d samba
sleep 3
docker exec samba pdbedit -L | grep -q "^$name:" ||
    { echo "samba does not list $name - check docker logs samba" >&2; exit 1; }
docker run --rm --network host --entrypoint smbclient dperson/samba \
    "//127.0.0.1/$share" -U "$name%$pass" -c ls > /dev/null ||
    { echo "login as $name failed" >&2; exit 1; }

echo
echo "Added $name to $share; login checked."
echo "Password (store it in Vaultwarden now - it is also in .env as $var):"
echo "  $pass"
echo "Commit docker-compose.yml. .env stays out of git."
