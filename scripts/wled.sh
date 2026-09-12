#!/usr/bin/env bash
# Drive the aarti-lights WLED board from the command line.
#
# Written during Phase 1 of aarti_lights_setup.md, because bench-testing a
# strip while holding wires in both hands is a bad time to be clicking a web
# UI - and because these checks need repeating in Phase 3 (real length, real
# supply) and Phase 6 (tuning in the room).
#
#   ./scripts/wled.sh info                 # version, count, draw, fps
#   ./scripts/wled.sh count 30             # set LED count
#   ./scripts/wled.sh pin 4                # set the data GPIO
#   ./scripts/wled.sh cap 800              # set max current, mA
#   ./scripts/wled.sh solid red [bri]      # red|green|blue|white|off
#   ./scripts/wled.sh rainbow [bri]        # spatial rainbow
#   ./scripts/wled.sh groups               # 3 separated colour groups
#   ./scripts/wled.sh order grb|rgb        # colour order
#
# WLED_HOST overrides the address (default below).
#
# GOTCHA worth knowing: an open WLED web UI holds a websocket and will
# overwrite whatever this sets, silently. `info` prints the client count - if
# it is not 0, close the page before trusting anything you see on the strip.
# That cost real confusion on 2026-09-12, when a leftover amber from the UI
# looked like a colour-order bug.
set -euo pipefail

HOST="${WLED_HOST:-192.168.1.125}"
BASE="http://$HOST"

api() { curl -fsS -m 10 -X POST "$BASE/json/$1" -H 'Content-Type: application/json' -d "$2" >/dev/null; }
getj() { curl -fsS -m 10 "$BASE/json/$1"; }

# Reads the current bus config so a single field can change without wiping
# the rest - WLED wants the whole `ins` entry, not a patch.
led_cfg() { getj cfg | python3 -c "
import sys, json
print(json.dumps(json.load(sys.stdin)['hw']['led']))
"; }

set_led() { # set_led <python-expression-updating-dict-d>
  local expr="$1"
  local cur; cur="$(led_cfg)"
  local body
  body="$(python3 -c "
import json, sys
d = json.loads('''$cur''')
ins = d.get('ins') or [{}]
i = ins[0]
$expr
d['ins'] = [i]
print(json.dumps({'hw': {'led': d}}))
")"
  api cfg "$body"
}

case "${1:-info}" in
  info)
    getj info | python3 -c "
import sys, json
d = json.load(sys.stdin); l = d['leds']
print('host         :', '$HOST')
print('version      :', d.get('ver'))
print('LEDs driven  :', l.get('count'))
print('estimated mA :', l.get('pwr'), 'of', l.get('maxpwr'))
print('fps          :', l.get('fps'))
print('uptime       :', d.get('uptime'), 's')
ws = d.get('ws')
print('UI clients   :', ws, '(>0 will overwrite what you set here)' if ws else '')
u = d.get('u', {})
print('usermods     :', ', '.join(u.keys()) if u else 'none')
"
    getj state | python3 -c "
import sys, json
s = json.load(sys.stdin)
act = [g for g in s.get('seg', []) if g.get('stop', 0) > g.get('start', 0)]
print('on           :', s.get('on'), '| brightness:', s.get('bri'))
for g in act:
    print('  pixels %d-%d effect %s colour %s' % (g.get('start'), g.get('stop')-1, g.get('fx'), g.get('col', [[]])[0]))
"
    ;;
  count) set_led "d['total'] = $2; i['len'] = $2; i['start'] = 0"; echo "count -> $2" ;;
  pin)   set_led "i['pin'] = [$2]"; echo "data pin -> $2" ;;
  cap)   set_led "d['maxpwr'] = $2"; echo "max current -> ${2}mA" ;;
  order)
    case "$2" in
      grb) o=0 ;; rgb) o=1 ;;
      *) echo "order must be grb or rgb" >&2; exit 2 ;;
    esac
    set_led "i['order'] = $o"; echo "colour order -> $2" ;;
  solid)
    bri="${3:-110}"
    case "${2:-red}" in
      red)   c='[255,0,0]' ;;
      green) c='[0,255,0]' ;;
      blue)  c='[0,0,255]' ;;
      white) c='[255,255,255]' ;;
      off)   api state '{"on":false}'; echo "output off"; exit 0 ;;
      *) echo "colour must be red|green|blue|white|off" >&2; exit 2 ;;
    esac
    n="$(getj info | python3 -c "import sys,json; print(json.load(sys.stdin)['leds']['count'])")"
    api state "{\"on\":true,\"bri\":$bri,\"transition\":0,\"seg\":[{\"id\":0,\"start\":0,\"stop\":$n,\"fx\":0,\"pal\":0,\"col\":[$c,[0,0,0],[0,0,0]],\"on\":true},{\"id\":1,\"stop\":0},{\"id\":2,\"stop\":0}]}"
    echo "solid ${2} across $n pixels at brightness $bri" ;;
  rainbow)
    bri="${2:-90}"
    n="$(getj info | python3 -c "import sys,json; print(json.load(sys.stdin)['leds']['count'])")"
    idx="$(getj eff | python3 -c "
import sys, json
for i, name in enumerate(json.load(sys.stdin)):
    if name.strip().lower() == 'rainbow':
        print(i); break
else:
    print(9)
")"
    api state "{\"on\":true,\"bri\":$bri,\"transition\":0,\"seg\":[{\"id\":0,\"start\":0,\"stop\":$n,\"fx\":$idx,\"sx\":90,\"ix\":128,\"pal\":0,\"on\":true},{\"id\":1,\"stop\":0},{\"id\":2,\"stop\":0}]}"
    echo "rainbow (effect $idx) across $n pixels at brightness $bri" ;;
  groups)
    # Three separated colour groups with dark gaps. The unambiguous proof of
    # per-pixel addressing: a dumb strip physically cannot show this.
    n="$(getj info | python3 -c "import sys,json; print(json.load(sys.stdin)['leds']['count'])")"
    a=$(( n / 2 )); b=$(( n - 3 ))
    api state "{\"on\":true,\"bri\":110,\"transition\":0,\"seg\":[
      {\"id\":0,\"start\":0,\"stop\":3,\"fx\":0,\"pal\":0,\"col\":[[255,0,0],[0,0,0],[0,0,0]],\"on\":true},
      {\"id\":1,\"start\":$a,\"stop\":$((a+3)),\"fx\":0,\"pal\":0,\"col\":[[0,255,0],[0,0,0],[0,0,0]],\"on\":true},
      {\"id\":2,\"start\":$b,\"stop\":$n,\"fx\":0,\"pal\":0,\"col\":[[0,0,255],[0,0,0],[0,0,0]],\"on\":true}
    ]}"
    echo "red 0-2, green $a-$((a+2)), blue $b-$((n-1)), dark between" ;;
  *) sed -n '2,22p' "$0"; exit 0 ;;
esac
