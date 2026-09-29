#!/usr/bin/env bash
# Manages the per-person upload logins for the album inbox.
#
#   services/albums/uploader.sh add <name>      create a login, print its password
#   services/albums/uploader.sh remove <name>   revoke one person
#   services/albums/uploader.sh list            who has a login
#
# Logins live in services/albums/accounts.conf (gitignored - it holds the
# passwords), which copyparty.conf includes. copyparty logs in by password
# alone, so each person only types their password; the name is for us (it is
# what .upload-log.tsv records). Every login can only add files to the hidden
# inbox - see review.sh for getting them into the album.
set -euo pipefail
cd "$(dirname "$0")"

conf=accounts.conf
[[ -f $conf ]] || printf '[accounts]\n' > "$conf"
chmod 600 "$conf"

restart() { (cd ../.. && docker compose restart albums-gallery >/dev/null) && echo "albums-gallery restarted"; }

case "${1:-}" in
add)
    name="${2:?usage: uploader.sh add <name>}"
    [[ $name =~ ^[a-z0-9-]+$ ]] || { echo "name: lowercase letters, digits, - only" >&2; exit 1; }
    grep -qE "^  $name:" "$conf" && { echo "$name already has a login (remove it first to reset)" >&2; exit 1; }
    # 3x4 lowercase letters: ~56 bits, easy to type on a phone, and copyparty
    # bans an IP after 9 wrong passwords in an hour.
    pw=$(python3 -c "import secrets,string as s; print('-'.join(''.join(secrets.choice(s.ascii_lowercase) for _ in range(4)) for _ in range(3)))")
    printf '  %s: %s\n' "$name" "$pw" >> "$conf"
    restart
    secret=$(grep -E '^OJASWI_ALBUM_PATH=' ../../.env | cut -d= -f2-)
    tailnet=$(grep -E '^TAILNET_SUFFIX=' ../../.env | cut -d= -f2-)
    echo "login for $name:"
    echo "  upload page: https://albums.$tailnet/$secret/upload/"
    echo "  password:    $pw"
    ;;
remove)
    name="${2:?usage: uploader.sh remove <name>}"
    grep -qE "^  $name:" "$conf" || { echo "no login named $name" >&2; exit 1; }
    sed -i -E "/^  $name:/d" "$conf"
    restart
    echo "removed $name"
    ;;
list)
    grep -E '^  [a-z0-9-]+:' "$conf" | cut -d: -f1 | sed 's/^ *//' || echo "(no logins)"
    ;;
*)
    sed -n '2,12p' "$0"; exit 1 ;;
esac
