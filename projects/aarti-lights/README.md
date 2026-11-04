# Sound-reactive aarti lights

A 3m WS2812B strip behind the makhar that reacts to the aarti live - the
ghanta, the claps and the singing each light it differently. An ESP32 running
WLED with the AudioReactive usermod does the listening; everything stays on the
LAN.

**[`aarti_lights_setup.md`](aarti_lights_setup.md) is the reference** for what
exists and how it is wired ([`wiring.svg`](wiring.svg) for the picture). The
decision history is `PROJECTS.md` under "Sound-reactive aarti lights". This
file is only the index.

| | |
|---|---|
| `wled.sh` | drive the board from the command line (bench tests, tuning) |
| `wled-audio-monitor.py` | read WLED's AudioReactive UDP broadcast - "does the mic work", numerically |
| `ambient-energy.py` | what FFT energy a resting room produces, to place the floor |
| `aarti-sound-lab.py` | record labelled samples of each sound |
| `aarti_audio.py` | the one place the measured thresholds live - both scripts below import it |
| `aarti-classify.py` | ghanta / clap / voice, live, from WLED's stream |
| `aarti-render.py` | drive the strip from the classification |
| `aarti-lights.service` | the renderer as a unit |
| `aarti-sound/` | the labelled recordings the thresholds came from |
| `make_wiring_svg.py` | regenerate `wiring.svg` from `wiring.html` |
| `test_aarti_idle_blackout.sh` | the idle strip stays dark |

Thresholds are **measured, not guessed** - from this bell, this mic and this
room on 2026-09-14. If any of those change, re-record with `aarti-sound-lab.py`
and edit the numbers in `aarti_audio.py` only.
