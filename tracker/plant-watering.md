# Automatic plant watering (balcony)
**Status:** Backlog
**Priority:** P1
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** revisit if the wall/pipe work happens for another reason, or if a balcony-sited reservoir becomes acceptable

**Why:** long-standing idea (predates this list) - water the balcony plants automatically instead of by hand.
**State:** not started. **Blocked on plumbing, not electronics** - which is why it never got built despite being wanted from the start. The actuation half is mostly solved with hardware on hand; the blocker is getting water to the balcony at all. Parked on the wall/pipe work; nothing planned until then.

#### The blocker
- **The actuation half is already mostly solved with hardware on hand:** a spare Tinxy valve can be opened/closed from its electric switch or Tinxy's remote API, and a reservoir already exists in the bathroom.
- **The blocker is getting water to the balcony at all** - the supply is in the bathroom, so any version needs a pipe run through a wall, i.e. drilling and laying pipe. That is construction work, not a weekend electronics build.
- **The bathroom reservoir does not sidestep this** - it is on the wrong side of the same wall. The only variant that avoids drilling is a reservoir physically sited on the balcony (manual refilling, plus somewhere to put it) with a small submersible pump instead of a valve.
- **Caveat on using the Tinxy valve:** it is cloud-dependent like the rest of the Tinxy gear (see "In-house smart switch to replace Tinxy" below) - watering would stop working during an ISP outage, and it inherits the same privacy concern. Fine for a first pass; an ESP32/ESPHome + solenoid valve would be the local-only version.

#### Design notes (captured 2026-09-04)
For whenever this unblocks - nothing built, but these are the decisions that usually decide whether such a build survives:
- Use **capacitive** soil moisture sensors, not resistive - resistive probes pass current through wet soil and corrode through in weeks. Most common failure of this project.
- **Water on a schedule with moisture as a veto**, rather than triggering on the sensor - a drifted or dead sensor then cannot flood the plants or starve them, it only loses the skip-if-already-wet optimisation.
- Put a **hard max-runtime cutoff on the device itself** (ESPHome `on_turn_on` -> delay -> `turn_off`), not only in an HA automation. Given the bridge-flapping history here (Node-RED MQTT drops, the `white-noise-mqtt.py` reconnect loop), a valve that only closes when HA tells it to is a flood waiting for the next hiccup. Prefer a normally-closed valve so a power cut means no water.

#### Log
- 2026-09-04: noted; design notes captured.
