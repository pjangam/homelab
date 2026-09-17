#!/usr/bin/env bash
# Tests the idle blackout added on 2026-09-18: with nothing classified for
# IDLE_TIMEOUT_S the strip must reach *actual black*, and any sound must relight
# it immediately.
#
# Worth a test rather than an eyeball because both halves are easy to get
# subtly wrong and neither shows up as an error. A floor that fades to 0.004
# instead of 0 still lights every pixel at 1/255 - invisible on the bench, a
# dim glow across a dark room, which is the exact complaint this fixes. And a
# wake path that reads the floor instead of the event would stay dark through
# the aarti. Neither needs the board: the renderer's frame maths is pure, so
# this runs anywhere and touches no hardware, no WLED, no mic.
#
#   projects/aarti-lights/test_aarti_idle_blackout.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0
fail=0

check() {
  local name="$1"; shift
  if out="$("$@" 2>&1)"; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name"
    echo "$out" | sed 's/^/        /'
    fail=$((fail + 1))
  fi
}

py() {
  python3 - "$HERE" <<'PY'
import importlib.util, sys, time
spec = importlib.util.spec_from_file_location("render", sys.argv[1] + "/aarti-render.py")
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)          # guarded by __main__, so nothing runs

IDLE, T, F = r.IDLE, r.IDLE_TIMEOUT_S, r.IDLE_FADE_S

def body(buf):
    """The pixel bytes of a packed frame, dropping the 2-byte DRGB header."""
    return r.pack(buf)[2:]

# --- the floor's shape over a silence ---------------------------------------
assert r.idle_floor(0.0) == IDLE, "lit while sound is happening"
assert r.idle_floor(T - 0.1) == IDLE, "still lit just before the timeout"
assert r.idle_floor(T) == IDLE, "the timeout itself is not yet dark"
mid = r.idle_floor(T + F / 2)
assert 0.0 < mid < IDLE, f"mid-fade should be partial, got {mid}"
assert r.idle_floor(T + F) == 0.0, "fully faded at timeout+fade"
assert r.idle_floor(T + F + 600) == 0.0, "stays at zero, never negative"
assert r.idle_floor(9999, timeout=0) == IDLE, "--idle-timeout 0 opts out"

# --- zero floor must mean every byte zero, not merely dim -------------------
now = time.time()
layers = r.Layers(r.N_LEDS)
dark = body(layers.frame(now, 1 / r.FPS, floor=0.0))
assert len(dark) == r.N_LEDS * 3, f"payload length {len(dark)}"
assert max(dark) == 0, f"silent strip still lit, brightest byte {max(dark)}"

lit = body(r.Layers(r.N_LEDS).frame(now, 1 / r.FPS, floor=IDLE))
assert max(lit) > 0, "resting glow should still light the strip before timeout"

# zones mode shares the floor
zdark = r.render([0.0, 0.0, 0.0], 0.0, floor=0.0)[2:]
assert max(zdark) == 0, f"zones mode still lit, brightest byte {max(zdark)}"

# --- a sound relights it even while the floor is zero ----------------------
woken = r.Layers(r.N_LEDS)
woken.on_clap(1.0)
clap = body(woken.frame(now, 1 / r.FPS, floor=0.0))
assert max(clap) > 40, f"a clap must be bright from black, got {max(clap)}"

voiced = r.Layers(r.N_LEDS)
voiced.voice = 0.8
assert max(body(voiced.frame(now, 1 / r.FPS, floor=0.0))) > 40, "voice from black"

ringing = r.Layers(r.N_LEDS)
ringing.ghanta = 1.0
assert max(body(ringing.frame(now, 1 / r.FPS, floor=0.0))) > 40, "ghanta from black"
print("ok")
PY
}

check "idle floor fades to true black and a sound relights it" py

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
