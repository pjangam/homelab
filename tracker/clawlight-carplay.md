# Clawlight in CarPlay (HA sensor)
**Status:** Done

**Why:** to see clawlight in the car. CarPlay has no browser, so neither the clawlight page nor the Pi's clock screen can go there. iOS 26 CarPlay widgets would have allowed a clock-style widget, but the user's iPhone is not on iOS 26 (2026-10-23), so it goes through the HA app's CarPlay support.
**Outcome:** done 2026-10-26, confirmed in the car by the user: the HA app's CarPlay Quick Access tile shows `sensor.clawlight_claude` ("Claude"), which `server.py` publishes over MQTT discovery (`clawlight/README.md`, "In the car").
- **Limitation: it tracks one session at a time.** The tile shows the sensor's one short line, so with more than one session only one is readable in the car. The sensor itself names every session in the aggregate's state, comma-separated, and has the full list in its `sessions` attribute, but CarPlay shows neither the full line nor attributes. Accepted as is. If more is ever needed: CarHA (third-party, buttons with values) or one HA sensor per session; neither tried.

#### Log
- 2026-10-23: sensor shipped and verified in HA. Considered and not pursued: a Scriptable widget like the clock's clawlight column (needs iOS 26 for CarPlay widgets, and widgets refresh only every 5-15 min anyway).
- 2026-10-26: seen working in the car; closed with the one-session limitation documented.
