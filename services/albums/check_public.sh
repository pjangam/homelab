#!/usr/bin/env bash
# Checks the album the way a relative on mobile data sees it: resolves the
# name through PUBLIC DNS (so the request goes via Tailscale's Funnel relays,
# not the tailnet) and verifies both halves - the album works, and nothing
# else is reachable or writable.
#
# Usage: services/albums/check_public.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

host="albums.$(grep -E '^TAILNET_SUFFIX=' .env | cut -d= -f2-)"
secret=$(grep -E '^OJASWI_ALBUM_PATH=' .env | cut -d= -f2-)
album=/datapool/albums/ojaswi-1st-birthday

ip=$(dig +short @8.8.8.8 "$host" A | grep -E '^[0-9.]+$' | head -1)
[[ -n "$ip" ]] || { echo "FAIL: $host has no public A record yet (new Funnel names take a few minutes)"; exit 1; }
echo "public A record: $ip"

code() { curl -s -o /dev/null -w '%{http_code}' --resolve "$host:443:$ip" "$@"; }
fails=0
expect() {  # expect <label> <want> <got>
    if [[ "$3" == "$2" ]]; then echo "ok   $1: $3"; else echo "FAIL $1: got $3, want $2"; fails=$((fails+1)); fi
}

probe=_public_check.png
cp /datapool/phone-uploads/gauri-invitation.png "$album/$probe"
trap 'rm -f "$album/$probe"' EXIT

expect "album page"      200 "$(code -A 'Mozilla/5.0 (iPhone) Safari' "https://$host/$secret/")"
expect "listing"         1   "$(curl -s --resolve "$host:443:$ip" "https://$host/$secret/?ls" | grep -c "$probe")"
expect "thumbnail"       200 "$(code "https://$host/$secret/$probe?th=w")"
expect "root /"          404 "$(code "https://$host/")"
expect "/?tree"          404 "$(code "https://$host/?tree")"
expect "guessed path"    404 "$(code "https://$host/ojaswi-1st-birthday/")"
expect "upload (PUT)"    401 "$(code -X PUT --data x "https://$host/$secret/x.txt")"
expect "delete"          403 "$(code -X POST "https://$host/$secret/$probe?delete")"
[[ -f "$album/$probe" ]] && echo "ok   probe file survived delete attempt" || { echo "FAIL probe file was deleted"; fails=$((fails+1)); }

exit $fails
