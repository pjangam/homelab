#!/usr/bin/env bash
# Tests takeout_download.sh against a local fake Takeout: a cookie-checked
# /download?i=N that redirects to a signed /blob/N, which serves byte ranges,
# cuts the first transfer of each part off halfway, and can be made to expire.
# Checks: parts arrive whole after a broken transfer, each part costs exactly
# one Takeout ask, a re-run asks nothing, bad cookies stop before any ask is
# wasted on a download, and a corrupt zip is caught.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'kill $srv 2>/dev/null; rm -rf "$t"' EXIT
port=$((20000 + RANDOM % 20000))

mkdir "$t/src"
for n in 0 1; do
  head -c 3000000 /dev/urandom > "$t/src/photo$n.jpg"
  (cd "$t/src" && zip -q "../blob$n.zip" "photo$n.jpg")
done

cat > "$t/server.py" <<'PY'
import http.server, os, sys
root, port = sys.argv[1], int(sys.argv[2])
cut = set()          # parts whose first transfer was already cut off
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith('/download'):
            open(f'{root}/asks', 'a').write(self.path + '\n')
            if 'auth=ok' not in self.headers.get('Cookie', ''):
                self.send_response(302); self.send_header('Location', 'https://accounts.google.com/x'); self.end_headers(); return
            i = self.path.split('i=')[1].split('&')[0]
            self.send_response(302); self.send_header('Location', f'http://127.0.0.1:{port}/blob/{i}?sig=1'); self.end_headers(); return
        i = self.path.split('/blob/')[1].split('?')[0]
        data = open(f'{root}/blob{i}.zip', 'rb').read()
        start = 0
        r = self.headers.get('Range')
        if r: start = int(r.split('=')[1].split('-')[0])
        end = len(data)
        if r and r.endswith('-0'): end = 1
        self.send_response(206 if r else 200)
        self.send_header('Content-Length', str(len(data) - start if end == len(data) else end - start))
        if r: self.send_header('Content-Range', f'bytes {start}-{end-1}/{len(data)}')
        self.end_headers()
        if i not in cut and not r:
            cut.add(i); self.wfile.write(data[:len(data)//2]); self.wfile.flush()
            self.connection.shutdown(2); return
        self.wfile.write(data[start:end])
http.server.ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
PY
python3 "$t/server.py" "$t" "$port" & srv=$!
sleep 1

printf '127.0.0.1\tFALSE\t/\tFALSE\t0\tauth\tok\n' > "$t/good.txt"
printf '127.0.0.1\tFALSE\t/\tFALSE\t0\tauth\tstale\n' > "$t/bad.txt"
url="http://127.0.0.1:$port/download?j=x&i=0&user=y"
fail() { echo "FAIL: $*"; exit 1; }

# Stale cookies: stops at the first ask, downloads nothing.
if "$here/takeout_download.sh" "$t/bad.txt" "$url" 2 "$t/out" 2>/dev/null; then fail "ran with stale cookies"; fi
[[ $(wc -l < "$t/asks") == 1 ]] || fail "stale cookies made $(wc -l < "$t/asks") asks"
[[ -z $(ls "$t/out" | grep zip) ]] || fail "stale cookies left a file"
: > "$t/asks"

# Good cookies: both parts arrive whole despite the cut transfer, one ask each.
"$here/takeout_download.sh" "$t/good.txt" "$url" 2 "$t/out" >/dev/null 2>&1 || fail "download failed"
for n in 0 1; do cmp -s "$t/blob$n.zip" "$t/out/takeout-00$((n + 1)).zip" || fail "part $n differs"; done
[[ $(wc -l < "$t/asks") == 2 ]] || fail "expected 2 asks, got $(wc -l < "$t/asks")"

# Re-run: everything is there, so no asks at all.
: > "$t/asks"
"$here/takeout_download.sh" "$t/good.txt" "$url" 2 "$t/out" >/dev/null
[[ ! -s "$t/asks" ]] || fail "re-run asked Takeout"

# A corrupt part on disk is fetched again, and only that part.
printf 'garbage' > "$t/out/takeout-002.zip"
"$here/takeout_download.sh" "$t/good.txt" "$url" 2 "$t/out" >/dev/null 2>&1 || fail "refetch failed"
cmp -s "$t/blob1.zip" "$t/out/takeout-002.zip" || fail "corrupt part not replaced"
[[ $(wc -l < "$t/asks") == 1 ]] || fail "refetch made $(wc -l < "$t/asks") asks"

echo "PASS: takeout_download.sh"
