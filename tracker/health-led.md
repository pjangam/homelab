# Homelab health LED (Pi GPIO) - the whole healthcheck as one light
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** decide - LED reads `homelab/healthcheck/overall` directly (nothing new server-side) or an HA-consolidated topic (more coverage, one more moving part)
- [ ] **Claude:** then build it from `scripts/clawlight/clawlight-led.py` + `deploy_clawlight_led_pi.sh` as templates

**Why:** `projects/healthcheck/healthcheck.sh` already knows whether the homelab is healthy, but the only way to find that out is to go looking - open the Stats dashboard, or wait for an email/ntfy push on a failure. The clawlight LED above proved the other shape works: a light on the desk that is simply *right*, with nothing to open. Same idea, different source of truth - green means every check passed, red means at least one did not, and the answer is visible from across the room.
**State:** idea only. Nothing built - but most of the pieces are already in place, which is the reason to write it down now. **The LED is bought, and it is RG (red/green bi-colour), not RGB** - same purchase and same caveats as the clawlight LED above (check leg count and polarity before wiring). The templates already have the MQTT-retained-state, stale-means-amber, systemd-unit shape worked out.

#### Design

**The consolidator largely exists already.** `projects/healthcheck/publish_healthcheck_mqtt.py` publishes `homelab/healthcheck/overall` **retained** every 15 minutes (cron), ON = at least one check is unhappy, alongside per-check tiles (docker, systemd, zfs, spotifyd, spotifyd_advertising, miraie_ac, power_watchdog) and a `last_check` timestamp. So the LED can subscribe to one retained topic and be correct the moment it powers on, exactly like `clawlight-led.py` does with `clawlight/state`. An HA template sensor is only needed if the light should also cover things `healthcheck.sh` does not compute - Tinxy entity health, HA's own liveness, the Pi itself - in which case the consolidation happens in HA and gets published back to its own MQTT topic for the LED to read.

**The hard part is staleness, not colour.** `publish_healthcheck_mqtt.py` is a one-shot cron publisher, not a daemon, so it cannot hold an MQTT last-will the way `server.py` does for clawlight. If `xero` dies, or cron stops, or the script starts erroring, the retained `overall` sits at its last value forever and the LED keeps confidently showing green - the precise failure the clawlight design was built to avoid ("anything other than a steady colour means don't believe me"). The fix is to read `last_check` as well and go to an amber pulse if it is older than ~2 intervals (35-40min), so a dead healthcheck looks different from a healthy one. That is the single decision this project stands or falls on.

**Colours (proposed):** green = all checks pass · red = at least one problem · amber pulse = healthcheck is stale or the broker connection dropped · dim white = never seen a result yet. Deliberately not off for any state, same as clawlight - "unplugged" must stay distinguishable. With the RG LED, green, red and amber all still work; **dim white does not**, so "never seen a result" needs another colour - probably whatever clawlight settles on for idle, so the two lights mean the same thing.

**One LED, not a bar.** The ask is "overall", and a single worst-of light is what gets read from across the room; *which* check failed is what the Stats dashboard and the ntfy push already answer well. A per-subsystem LED bar is the obvious escalation if the single light turns out to send you to the dashboard every time anyway.

#### Wiring

GPIO13/19 are taken by the clawlight LED (GPIO26 was planned for its blue and is free again), so this needs its own block - GPIO16 + GPIO20 + GPIO21 (pins 36/38/40) with GND on pin 34 is free and leaves every button-reserved pin alone. The RG LED needs only two of those (GPIO16 red, GPIO20 green), leaving GPIO21 free. Update `docs/gpio_pinout.md` when it gets wired.

**Known trap:** this would be the **fourth** GPIO process on that Pi - it needs its own lgpio notify directory or it will silently break one of the existing ones, see `docs/incidents/2026-09-04-lgpio-notify-fifo-collision.md`. That incident is exactly how the white-noise buttons died last time.

#### Parts

```parts
qty | item | est | note
2 | 220R resistor | 5 | local - one per colour leg (RG LED: 2 legs)
10 | 330R + 100R resistors | 20 | local - to balance red against green, see below
1 | Female-female dupont jumpers (40-pin strip) | 120 | local - 3 wires needed: 2 colour legs + GND
1 | Perfboard 5x7cm | 30 | local - shared with the clawlight LED build, one board holds both
1 | Ping-pong ball or diffuser | 20 | household - optional, turns a point of light into a beacon
```

**Buy it at the shop with the clawlight LED's parts - everything here is loose stock.** Both LED builds together are one counter purchase of roughly **₹150-250**: ~30 resistors across a few values, a jumper strip and a perfboard (the LEDs are already bought). Nothing in this project needs ordering, so it is not gated on any delivery - it can be built the same day the shop is visited.

The LEDs themselves are bought (RG, not RGB - see State). One thing still worth asking for specifically:
- **Resistors in three values, not one.** 220R is the textbook number but it is sized for 5V logic; on the Pi's 3.3V pins the red die gets ~6mA while green gets ~1.5mA, so the LED ends up dimmer and redder than it needs to be. Ask for ~10 each of **100R, 220R and 330R** (₹20-ish for the lot) and the colour balance becomes something to tune on the bench rather than re-order for. If it turns out to glare on a desk at night, 1k in the same handful fixes that too.

A soldering iron is assumed - it is already on the aarti lights list (₹500-800) and is the one real cost if not owned. Ping-pong ball for diffusion is household, not a purchase.

#### Log
- 2026-09-11: idea noted.
- 2026-09-15: LED bought - RG, not RGB.
