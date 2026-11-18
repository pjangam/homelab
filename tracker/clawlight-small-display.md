# Clawlight small low-power display (reuse of the Pi clock screensaver)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** pick the small low-power display (and whether it hangs off the wol Pi or its own board)
- [ ] **Claude:** once it's chosen, trim `scripts/wol-sender/analog_clock.py` to the clawlight sessions (plus clock/weather if they fit) for that screen

**Why:** the clock screensaver's clawlight panel was the part worth keeping; the 27" 4K monitor it ran on was ~45W around the clock for it. A small screen showing clawlight state does the same job at a fraction of the power.
**State:** idea only. The renderer exists - `analog_clock.py` (GTK3, polls xero:8126 `/clawlight/api/status` and HA's weather) - so the work is picking the screen and sizing the layout for it, not plumbing. Overlaps "Big wall display (HUB75 LED matrix)" just below; decide them together.
