# Clawlight physical LED (Pi GPIO)
**Status:** Done

**Why:** the software clawlight (see below) only shows status while its browser tab or PiP window is actually visible. A LED on the wol-sender Pi's GPIO gives the always-visible physical light the parked ESP32 "Claw Light" idea was for, at ~₹20 of parts, because that Pi happens to sit next to the desk. Anywhere else this would still need the ESP32 version.
**Outcome:** shipped - software 2026-09-07, wired and deployed 2026-09-16. A red/green LED on the Pi's GPIO13/19, driven by `clawlight-led.service` from retained MQTT state, showing green active · red waiting · dim steady amber idle · amber pulse = state unknown. Verified 2026-09-16. No further work planned.

#### What shipped
- **Part:** 3-leg common-cathode **red/green** bi-colour LED - bought as RGB, turned out RG. Long leg to GND (pin 39), red through 220R to GPIO13 (pin 33), green through 220R to GPIO19 (pin 35). Diagram, leg test and bench checks: `clawlight/led_wiring.html` (https://claude.ai/artifact/UDgsMP8uYK5FkHFydLMwP9).
- **`clawlight-led.service`** on the Pi (system unit, `systemd/wol-sender/`), driven by `scripts/clawlight/clawlight-led.py` through gpiozero `LEDBoard` with PWM. Deployed from xero by `scripts/clawlight/deploy_clawlight_led_pi.sh`, which asks for the Pi's sudo password.
- **Colours:** green active · red waiting · dim steady amber idle · amber pulse = state unknown. `AMBER = (0.5, 1.0)`, `IDLE_BRIGHTNESS = 0.3`, both picked by eye on the real LED.
- **Bench tools:** `scripts/clawlight/tune_led.sh amber|idle` steps through values printed as ready-made code lines; `scripts/clawlight/show_led_states.sh` shows the pulse and idle on demand (stops the server, then hand-publishes idle, then restores); `scripts/clawlight/test_clawlight_led.py` checks pin output on gpiozero mock pins.

#### Design decisions
- **State reaches the Pi over retained MQTT, not the SSE endpoint the web page uses.** A hardware light must be correct the moment it powers on, and clawlight only emits on hook events - a subscriber starting cold during a quiet stretch would sit wrong for as long as the quiet lasted. `server.py` publishes the aggregate to `clawlight/state` retained, so the broker replays it on connect. Reuses the house MQTT pattern, and makes the state available to HA for free.
- **An MQTT last-will means the light never lies.** If `server.py` dies the broker publishes `offline` on `clawlight/availability` and the LED pulses amber rather than holding a stale colour. Directly informed by the 2026-09-07 MirAIe outage, where something that looked healthy while reporting nothing went unnoticed for 29 hours.
- **Idle is dim, not off** - so "nothing running" is distinguishable from "unplugged". Planned as dim white, which needs blue; on the RG LED it is dim steady amber (chosen over dim green). What keeps it apart from "unknown" is motion, not hue: only the unknown state ever pulses.
- **GPIO13/19 (pins 33/35, GND on 39)** - a tidy corner block that leaves every pin `docs/gpio_pinout.md` lists as free-for-a-button untouched. GPIO26 (pin 37), planned for blue, stays free. Third GPIO process on this Pi, so it gets its own lgpio notify directory (see `docs/incidents/2026-09-04-lgpio-notify-fifo-collision.md`).

#### Notes worth keeping
- **gpiozero `LEDBoard` orders keyword pins alphabetically.** `LEDBoard(red=13, green=19)` takes values as (green, red), which would have swapped every colour. Pins are passed positionally; the mock-pin test caught it before any wiring.
- **gpiozero's `pulse()` fades each pin from 0 to full,** which turns a red/green mix into yellow. The amber pulse scales both channels by one shared brightness instead.
- **Tune colours only after checking plain red and green.** The legs were first wired to each other's pins, and the resulting "yellow" amber sent one retune the wrong way.
- **Hue is the ratio, not the levels.** The green die is weak on 220R - even green at full with red at full read red-orange - so amber came from lowering red to 0.5 rather than swapping the green resistor to 100R. A 100R on green would still brighten green and amber if either ever looks weak; re-run `tune_led.sh amber` afterwards, since the ratio would move.
- **The deploy script's install step had never run for real.** It ran sudo inside a heredoc over a terminal-less ssh, which cannot prompt for the Pi's password; only `--dry-run` had ever worked. Fixed with `ssh -t`, and it restarts rather than `enable --now` so a redeploy picks up new code.
- **A plain `systemctl --user stop clawlight-server` trips the last-will** - the LED logged `offline` in the same second - so a clean stop is not mistaken for "still online".

#### Log
- 2026-09-07: software shipped.
- 2026-09-16: wired and deployed. Verified: the service starts at boot (survived a Pi reboot mid-bench with no redeploy) and shows the real aggregate within a second of starting; red, green, the amber pulse and dim amber idle each confirmed by eye, with the matching state transitions in the Pi's journal.
