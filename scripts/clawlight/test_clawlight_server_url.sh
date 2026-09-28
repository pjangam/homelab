#!/usr/bin/env bash
# Exercises clawlight/server-url.sh - which server URL a report goes to, and
# therefore whether a machine off the home LAN posts its session ids and
# project paths to a stranger who happens to hold 192.168.1.123.
#
# Needs no clawlight server: it stands up a one-shot HTTP listener and points
# the URL that SHOULD win at it, while the loser points at a dead port. If the
# listener is hit, the right URL was chosen - which is stronger than asserting
# on the helper's return value, because it goes through set-status.sh's real
# curl call.
#
# Usage: scripts/clawlight/test_clawlight_server_url.sh
set -u

repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
set_status="$repo_dir/clawlight/set-status.sh"
helper="$repo_dir/clawlight/server-url.sh"
tmp="$(mktemp -d)"
fails=0

trap 'rm -rf "$tmp"' EXIT
# shellcheck source=/dev/null
. "$helper"

check() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected $3, got $2)"
    fails=$((fails + 1))
  fi
}

# --- 1. MAC normalisation ----------------------------------------------------
# macOS `arp` prints an octet below 0x10 as a single digit while `ip neigh` and
# router labels pad it, so comparing raw strings would silently never match.
check "pads and lower-cases" "$(clawlight_norm_mac '8:0:20:A:b:C')" "08:00:20:0a:0b:0c"
check "leaves a full MAC alone" "$(clawlight_norm_mac 'f8:c4:f3:e0:82:3f')" "f8:c4:f3:e0:82:3f"
check "rejects a short MAC" "$(clawlight_norm_mac 'f8:c4:f3')" ""
check "rejects junk" "$(clawlight_norm_mac 'not-a-mac')" ""
check "rejects empty" "$(clawlight_norm_mac '')" ""

# --- 2. the decision, with the gateway stubbed -------------------------------
# Stubbed so the answers are the same on any network this runs on.
real_gateway_mac="$(clawlight_gateway_mac)"
clawlight_gateway_mac() { printf '%s' "${STUB_GW:-}"; }

pick() (
  export CLAWLIGHT_SERVER_URL="tailnet" CLAWLIGHT_LAN_URL="${1:-}" \
         CLAWLIGHT_HOME_GATEWAY_MAC="${2:-}" STUB_GW="${3:-}"
  clawlight_server_url
)

check "no LAN vars at all -> fallback"        "$(pick '' '' 'aa:bb:cc:dd:ee:ff')" "tailnet"
check "LAN URL but no MAC -> fallback"        "$(pick 'lan' '' 'aa:bb:cc:dd:ee:ff')" "tailnet"
check "MAC but no LAN URL -> fallback"        "$(pick '' 'aa:bb:cc:dd:ee:ff' 'aa:bb:cc:dd:ee:ff')" "tailnet"
check "gateway matches -> LAN"                "$(pick 'lan' 'aa:bb:cc:dd:ee:ff' 'aa:bb:cc:dd:ee:ff')" "lan"
check "gateway matches, odd spelling -> LAN"  "$(pick 'lan' 'AA:B:CC:D:EE:F' 'aa:0b:cc:0d:ee:0f')" "lan"
check "gateway differs -> fallback"           "$(pick 'lan' 'aa:bb:cc:dd:ee:ff' 'de:ad:be:ef:00:01')" "tailnet"
check "no gateway (cold ARP) -> fallback"     "$(pick 'lan' 'aa:bb:cc:dd:ee:ff' '')" "tailnet"
check "unparseable configured MAC -> fallback" "$(pick 'lan' 'garbage' 'garbage')" "tailnet"

# --- 3. end to end through set-status.sh -------------------------------------
# A one-shot listener stands in for the clawlight server. The URL expected to
# lose points at a port nothing listens on, so a wrong choice cannot pass.
listen() {
  python3 - "$1" "$2" <<'PY' &
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
port, out = int(sys.argv[1]), sys.argv[2]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        with open(out, "w") as f:
            f.write(self.path + "\n" + self.rfile.read(n).decode())
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{}")

srv = HTTPServer(("127.0.0.1", port), H)
# Announce the bind before blocking. Without this the shell raced ahead and
# POSTed into a closed port - which looks exactly like "the wrong URL was
# chosen", and did, on the busier of the two machines this runs on.
open(out + ".ready", "w").close()
# Bounded, so a wrong URL choice fails the test instead of hanging it forever.
srv.timeout = 15
srv.handle_request()
PY
}

free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }

# $1 = label, $2 = which URL should win (lan|fallback), $3 = configured MAC,
# $4 = what the gateway really is (via a fake `arp`, see below)
run_e2e() {
  local label="$1" winner="$2" cfg_mac="$3" gw_mac="$4"
  local port dead out lan_url fb_url
  port="$(free_port)"; dead="$(free_port)"
  out="$tmp/hit-$port"
  listen "$port" "$out"
  local w=0
  while [ $w -lt 100 ] && [ ! -e "$out.ready" ]; do sleep 0.1; w=$((w + 1)); done
  [ -e "$out.ready" ] || { check "$label (listener never bound)" "no" "yes"; return; }

  if [ "$winner" = "lan" ]; then
    lan_url="http://127.0.0.1:$port"; fb_url="http://127.0.0.1:$dead"
  else
    lan_url="http://127.0.0.1:$dead"; fb_url="http://127.0.0.1:$port"
  fi

  # A fake gateway, injected by putting stub `ip`/`route`/`arp` on PATH ahead
  # of the real ones - the same surface server-url.sh reads, so the stub proves
  # the real lookup path rather than bypassing it.
  mkdir -p "$tmp/bin"
  printf '#!/bin/sh\nexit 127\n' > "$tmp/bin/ip"
  printf '#!/bin/sh\necho "   gateway: 10.0.0.1"\n' > "$tmp/bin/route"
  printf '#!/bin/sh\necho "? (10.0.0.1) at %s on en0 ifscope [ethernet]"\n' "$gw_mac" > "$tmp/bin/arp"
  chmod +x "$tmp/bin/ip" "$tmp/bin/route" "$tmp/bin/arp"

  printf '{"session_id":"test-server-url-%s","cwd":"/tmp/serverurltest"}' "$$" \
    | PATH="$tmp/bin:$PATH" \
      CLAWLIGHT_SERVER_URL="$fb_url" CLAWLIGHT_LAN_URL="$lan_url" \
      CLAWLIGHT_HOME_GATEWAY_MAC="$cfg_mac" CLAWLIGHT_HOST_NAME="test" \
      CLAWLIGHT_BACKGROUND_SHELLS=0 \
      bash "$set_status" active >/dev/null 2>&1

  # The listener exits after one request; give it a moment either way.
  local i=0
  while [ $i -lt 20 ] && [ ! -s "$out" ]; do sleep 0.1; i=$((i + 1)); done

  if [ -s "$out" ] && head -1 "$out" | grep -q '^/clawlight/api/report$'; then
    check "$label" "hit" "hit"
  else
    check "$label" "no report arrived" "hit"
  fi
  wait 2>/dev/null || true
}

run_e2e "report goes to the LAN URL when the gateway matches" \
        lan "aa:bb:cc:dd:ee:ff" "aa:bb:cc:dd:ee:ff"
run_e2e "report goes to the fallback when the gateway differs" \
        fallback "aa:bb:cc:dd:ee:ff" "de:ad:be:ef:00:01"

# --- 4. this machine, for information ----------------------------------------
echo
if [ -n "$real_gateway_mac" ]; then
  echo "note - this machine's default gateway is $real_gateway_mac"
  echo "       (that is the value --gateway-mac defaults to when run at home)"
else
  echo "note - no default gateway in the ARP cache here, so the LAN shortcut"
  echo "       would fall back to the tailnet URL on this machine right now"
fi

echo
[ "$fails" -eq 0 ] && { echo "all checks passed"; exit 0; }
echo "$fails check(s) failed"
exit 1
