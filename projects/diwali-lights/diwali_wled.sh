#!/usr/bin/env bash
# Set up the Diwali door-outline WLED board and load-test its supply.
# Written 2026-10-30. Run after tools/esp32-tools/flash-wled-audioreactive.sh
# --flash; wiring and layout in projects/diwali-lights/wiring.html.
#
#   diwali_wled.sh wifi-usb   # 1. board on xero's USB: house WiFi over serial + static IP
#   diwali_wled.sh wifi       #    or, joined to the board's WLED-AP: the same over the AP
#   diwali_wled.sh static IP  #    or, already on the house WiFi at IP: move it to static
#   diwali_wled.sh setup      # 2. on the house WiFi: count, pin, order, cap, name
#   diwali_wled.sh loadtest   # 3. full white at rising caps - does the charger hold?
#   diwali_wled.sh warm       # 4. warm diya effect, saved as boot preset 1
#
# Why a load test: the supply is a OnePlus fast charger labelled 5V 4A, and
# proprietary fast chargers may only give the full current after a handshake
# with a OnePlus phone - to a plain load perhaps ~2A. Ganapati's 180 px never
# found out. `loadtest` runs the whole strip at full white with WLED's current
# cap raised step by step (STEPS, default 2000 2800 3400 mA, STEP_SEC 60 each),
# watching for the ESP32 rebooting (a brownout) or dropping off WiFi. Watch the
# strip too: flicker, or white going pink/orange at the far end, is the supply
# sagging even if the board survives. It ends with the cap at the highest step
# that passed; if you saw sag at a step the script passed, set it one lower:
#   WLED_HOST=192.168.1.127 projects/aarti-lights/wled.sh cap <mA>
# Unroll the strip first - a coiled reel at 3A+ of full white gets hot.
#
# HOST (default 192.168.1.127) overrides the board address; the WiFi details
# come from the voice satellites' gitignored esphome/secrets.yaml, or from
# WIFI_SSID / WIFI_PASSWORD (needed on the Mac, whose clone lacks secrets).
# Close any open WLED web page first: its websocket overwrites what this sets
# (the gotcha in wled.sh).
set -euo pipefail

HOST=${HOST:-192.168.1.127}
GATEWAY=192.168.1.1          # same as the voice satellites
LEDS=${LEDS:-284}            # 180 px aarti strip + ~104 px offcut; count the offcut
CAP=${CAP:-1700}             # safe for a 2A-limited charger; raise after loadtest
STEPS=${STEPS:-2000 2800 3400}
STEP_SEC=${STEP_SEC:-60}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
WLED="$REPO/projects/aarti-lights/wled.sh"

w() { WLED_HOST=$HOST "$WLED" "$@"; }
post() { curl -fsS -m 10 -X POST "http://$1/json/$2" -H 'Content-Type: application/json' -d "$3" >/dev/null; }
info() { curl -fsS -m 5 "http://$HOST/json/info"; }
# field <python-expr over d> from /json/info, or empty when unreachable
field() { info 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" 2>/dev/null || true; }
# WLED restarts itself after LED hardware changes (count, pin, order); wait for it
wait_up() { sleep 2; for _ in $(seq 30); do [ -n "$(field 'd["ver"]')" ] && return; sleep 2; done; echo "$HOST did not come back" >&2; exit 1; }

wifi_details() {
  local secrets="$REPO/projects/voice-assistant/esphome/secrets.yaml"
  ssid=${WIFI_SSID:-$(sed -n 's/^wifi_ssid: *"\(.*\)"/\1/p' "$secrets" 2>/dev/null)}
  pass=${WIFI_PASSWORD:-$(sed -n 's/^wifi_password: *"\(.*\)"/\1/p' "$secrets" 2>/dev/null)}
  [ -n "$ssid" ] && [ -n "$pass" ] || { echo "no WiFi details: set WIFI_SSID and WIFI_PASSWORD" >&2; exit 1; }
}

# static_cfg <wled address to post to> - static IP, gateway, mDNS name, then reboot
static_cfg() {
  local body
  body=$(python3 -c '
import json, sys
ssid, psk, host, gw = sys.argv[1:]
ip = lambda s: [int(x) for x in s.split(".")]
print(json.dumps({"nw": {"ins": [{"ssid": ssid, "psk": psk, "ip": ip(host),
                                   "gw": ip(gw), "sn": [255, 255, 255, 0]}]},
                  "id": {"mdns": "wled-diwali", "name": "Diwali Lights"}}))' "$ssid" "$pass" "$HOST" "$GATEWAY")
  post "$1" cfg "$body"
  post "$1" state '{"rb":true}' || true
}

case "${1:-}" in
  wifi-usb)
    # Board still on xero's USB after flashing: WiFi over serial (Improv), no AP.
    wifi_details
    out=$("$HOME/.cache/wled-esptool-venv/bin/python" "$REPO/tools/esp32-tools/improv_wifi.py" \
            --port "${PORT:-/dev/ttyUSB0}" --ssid "$ssid" --password "$pass") || { echo "$out" >&2; exit 1; }
    echo "$out"
    dhcp=$(sed -n 's|^url: *https\?://\([0-9.]*\).*|\1|p' <<< "$out" | head -1)
    [ -n "$dhcp" ] || { echo "joined, but no address reported - find it in the router and run: $0 static <ip>" >&2; exit 1; }
    for _ in $(seq 10); do curl -fsS -m 3 "http://$dhcp/json/info" >/dev/null 2>&1 && break; sleep 2; done
    static_cfg "$dhcp"
    echo "on WiFi at $dhcp (DHCP); static $HOST set, rebooting. Next: $0 setup"
    ;;
  static)
    # The board is on the house WiFi at a DHCP address ($2): move it to $HOST.
    wifi_details
    static_cfg "${2:?usage: $0 static <current ip>}"
    echo "static $HOST set, rebooting. Next: $0 setup"
    ;;
  wifi)
    wifi_details
    curl -fsS -m 5 http://4.3.2.1/json/info >/dev/null \
      || { echo "4.3.2.1 not reachable - join the WLED-AP network (password wled1234) first" >&2; exit 1; }
    static_cfg 4.3.2.1
    echo "sent WiFi '$ssid' and static $HOST; the board is rebooting onto the house WiFi."
    echo "Rejoin your own WiFi, then: $0 setup"
    echo "If $HOST never answers, it did not join: WLED-AP comes back after ~1 min, retry."
    ;;
  setup)
    [ -n "$(field 'd["ver"]')" ] || { echo "$HOST not answering - did 'wifi' work?" >&2; exit 1; }
    w count "$LEDS"; wait_up
    w pin 4; wait_up
    w order grb; wait_up
    w cap "$CAP"; wait_up
    w info
    echo
    echo "Check the colour order: '$WLED solid red' must look red (WLED_HOST=$HOST)."
    echo "Mic (only when the borrowed INMP441 is fitted): Config -> Usermods -> AudioReactive,"
    echo "digital mic, generic I2S, SD 32 / WS 25 / SCK 33 - the aarti pins."
    ;;
  loadtest)
    [ -n "$(field 'd["ver"]')" ] || { echo "$HOST not answering" >&2; exit 1; }
    n=$(field 'd["leds"]["count"]')
    echo "Full white on all $n LEDs, cap steps: $STEPS mA, ${STEP_SEC}s each."
    echo "Strip unrolled, supply connected at both ends? Ctrl-C now if not; starting in 10s."
    sleep 10
    passed=
    for cap in $STEPS; do
      w cap "$cap" >/dev/null
      w solid white 255 >/dev/null
      up0=$(field 'd["uptime"]')
      fail=
      for _ in $(seq $(( STEP_SEC / 3 ))); do
        sleep 3
        up=$(field 'd["uptime"]')
        if [ -z "$up" ]; then fail="board stopped answering (WiFi dropped or rebooting)"; break; fi
        if [ "$up" -lt "$up0" ]; then fail="board rebooted (uptime $up0 -> $up s): brownout"; break; fi
      done
      pwr=$(field 'd["leds"]["pwr"]')
      if [ -n "$fail" ]; then
        echo "$cap mA: FAIL - $fail"
        break
      fi
      echo "$cap mA: ok (WLED estimates ${pwr:-?} mA)"
      passed=$cap
    done
    # wait for a rebooted board before restoring anything
    for _ in $(seq 20); do [ -n "$(field 'd["ver"]')" ] && break; sleep 3; done
    w solid off >/dev/null || true
    if [ -n "$passed" ]; then
      w cap "$passed" >/dev/null
      echo "cap left at $passed mA, the highest step that held. If the strip flickered or"
      echo "turned pink at the far end at that step, set it one step lower (see header)."
    else
      w cap "$CAP" >/dev/null || true
      echo "no step held: cap back at $CAP mA. Fine for warm effects; a plain 5V 4-5A adapter for more."
    fi
    ;;
  warm)
    fx=$(curl -fsS -m 10 "http://$HOST/json/eff" | python3 -c '
import json, sys
names = [n.strip().lower() for n in json.load(sys.stdin)]
print(names.index("candle multi") if "candle multi" in names else names.index("candle"))')
    post "$HOST" state "{\"on\":true,\"bri\":120,\"transition\":7,\"seg\":[{\"id\":0,\"start\":0,\"stop\":$LEDS,\"fx\":$fx,\"sx\":96,\"ix\":200,\"pal\":0,\"col\":[[255,120,20],[255,60,0],[0,0,0]],\"on\":true},{\"id\":1,\"stop\":0},{\"id\":2,\"stop\":0}]}"
    sleep 1
    post "$HOST" state '{"psave":1,"n":"Diwali warm","ib":true,"sb":true}'
    post "$HOST" cfg '{"def":{"ps":1,"on":true,"bri":120}}'
    echo "Candle Multi (effect $fx), amber, saved as preset 1 and set as the boot preset:"
    echo "the strip comes back like this after a power cut, without HA or xero."
    ;;
  *) sed -n '2,31p' "$0"; exit 1 ;;
esac
