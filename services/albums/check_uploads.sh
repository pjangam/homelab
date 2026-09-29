#!/usr/bin/env bash
# Checks the review-first upload path over the PUBLIC route (public DNS ->
# Funnel relays), the way a relative's phone reaches it. Creates a throwaway
# login, runs the checks, then removes the login and everything it uploaded.
# Restarts albums-gallery twice (add + remove login). Companion to
# check_public.sh, which covers the read-only side.
#
# Usage: services/albums/check_uploads.sh
set -uo pipefail
cd "$(dirname "$0")/../.."

host="albums.$(grep -E '^TAILNET_SUFFIX=' .env | cut -d= -f2-)"
secret=$(grep -E '^OJASWI_ALBUM_PATH=' .env | cut -d= -f2-)
inbox=/datapool/albums/_inbox/ojaswi-1st-birthday
album=/datapool/albums/ojaswi-1st-birthday
user=zz-selftest
base="https://$host/$secret"

ip=$(dig +short @8.8.8.8 "$host" A | grep -E '^[0-9.]+$' | head -1)
[[ -n "$ip" ]] || { echo "FAIL: no public A record for $host"; exit 1; }
curl_() { curl -s --max-time 60 --resolve "$host:443:$ip" "$@"; }
code() { curl_ -o /dev/null -w '%{http_code}' "$@"; }

fails=0
expect() {
    if [[ "$3" == "$2" ]]; then echo "ok   $1: $3"; else echo "FAIL $1: got $3, want $2"; fails=$((fails+1)); fi
}

tmp=$(mktemp -d -p "$(dirname "$0")" .selftest.XXXX)
cleanup() {
    services/albums/uploader.sh remove "$user" >/dev/null 2>&1
    rm -f "$inbox"/selftest-* "$album"/selftest-*
    [[ -f $inbox/.upload-log.tsv ]] && sed -i "/\t$user\t/d" "$inbox/.upload-log.tsv"
    rm -rf "$tmp"
}
trap cleanup EXIT

pw=$(services/albums/uploader.sh add "$user" 2>/dev/null | awk '/password:/ {print $2}')
[[ -n $pw ]] || { echo "FAIL: could not create test login"; exit 1; }
sleep 5  # gallery restart
jpg=$(find "$album" -maxdepth 1 -name '*.JPG' | head -1)
printf 'MZ\x90\x00%02000d' 0 > "$tmp/fake.jpg"   # an .exe header, named .jpg, >1k
printf 'just text %02000d' 0 > "$tmp/note.txt"
P="PW: $pw"

expect "anon: upload page"              403 "$(code "$base/upload/")"
expect "anon: upload"                   401 "$(code -X PUT --data-binary @"$jpg" "$base/upload/selftest-anon.jpg")"
expect "wrong password: upload"         403 "$(code -H 'PW: aaaa-bbbb-cccc' -X PUT --data-binary @"$jpg" "$base/upload/selftest-bad.jpg")"
expect "login: upload real photo"       201 "$(code -H "$P" -X PUT --data-binary @"$jpg" "$base/upload/selftest-ok.jpg")"
code -H "$P" -X PUT --data-binary @"$tmp/note.txt" "$base/upload/selftest-note.txt" >/dev/null  # refused as 400 or 403
expect "login: .exe renamed .jpg"       500 "$(code -H "$P" -X PUT --data-binary @"$tmp/fake.jpg" "$base/upload/selftest-fake.jpg")"
expect "login: write into album"        403 "$(code -H "$P" -X PUT --data-binary @"$jpg" "$base/selftest-album.jpg")"
expect "login: delete from inbox"       403 "$(code -H "$P" -X POST "$base/upload/selftest-ok.jpg?delete")"
expect "login: list inbox (no files)"   0   "$(curl_ -H "$P" "$base/upload/?ls" | grep -c selftest-ok)"
expect "anon: read inbox file"          403 "$(code "$base/upload/selftest-ok.jpg")"
expect "anon: /?tree hides upload"      0   "$(curl_ "$base/?tree" | grep -c upload)"
expect "album: photo not published"     0   "$(curl_ "$base/?ls" | grep -c selftest)"

expect "disk: real photo in inbox"      yes "$([[ -f $inbox/selftest-ok.jpg ]] && echo yes || echo no)"
expect "disk: .txt refused"             no  "$([[ -f $inbox/selftest-note.txt ]] && echo yes || echo no)"
expect "disk: fake deleted"             no  "$([[ -f $inbox/selftest-fake.jpg ]] && echo yes || echo no)"
logged_ip=$(awk -F'\t' -v u="$user" '$2==u && $4=="selftest-ok.jpg" {print $3}' "$inbox/.upload-log.tsv" | tail -1)
echo "info logged client IP: $logged_ip (xero's public IP is $(curl -s --max-time 10 ifconfig.me))"
[[ $logged_ip == 172.* || -z $logged_ip ]] && { echo "FAIL client IP is the sidecar's - wrong-password bans would hit everyone"; fails=$((fails+1)); }

exit $fails
