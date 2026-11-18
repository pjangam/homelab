# wol Pi clock screensaver (analog clock + weather + clawlight sessions)
**Status:** Done

**Why:** a desk clock on the Pi's monitor, with HA's weather, the rain chance and the clawlight sessions beside it.
**Outcome:** ran 2026-09-19 to 2026-11-05, then retired at the user's ask (2026-11-05): it held the LG 27UK650 (~45W) on 24/7 for a clock. Removed from the Pi with `scripts/wol-sender/undeploy_clock_screensaver.sh` (stopped, login autostart and the Pi's HA token copy deleted; `kanshi-config` left). **The code stays in `scripts/wol-sender/`** - `analog_clock.py` is the starting point for "Clawlight small low-power display" below, and `deploy_clock_screensaver.sh` would put it all back.
- Its swayidle was the Pi's only idle handler, so retiring it left the monitor on all day. Replaced the same day by `scripts/wol-sender/screen_blank.sh`: HDMI off after 10 idle minutes, on at any input (`deploy_screen_blank.sh`; tested `wlopm` off/on on the LG).
