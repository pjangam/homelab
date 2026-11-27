# Weather forecast cloud (WLED in a fibre-fill cloud, colour from HA's forecast)
**Status:** Backlog
**Priority:** P3
**Cost:** ₹300-1,200
**Effort:** ~3 evenings (7-10h)

#### Open items
- [ ] **Pramod:** decide the strip: cut ~40-60 px off the Diwali strip's far end, or buy a new 1m (60 px) piece and keep the door strip whole
- [ ] **Pramod:** say where the cloud goes (which room, ceiling-hung or on the wall) and whether it should go dark at night
- [ ] **Pramod:** pick the colour scheme: the original's (tomorrow warmer/colder/same, pulse on rain) or the rain/storm-first one below - or your own colours
- [ ] **Pramod:** confirm the wled-diwali board can go to the cloud rather than to WoL, the analog clock or the wall display, which also count on it
- [ ] **Claude:** bench test before any crafting: check `weather.forecast_home`'s forecast fields, then push presets and the WLED nightlight timeout (stale = off) to the board on 30 px
- [ ] **Pramod:** buy the parts (lantern, fibre fill, glue; strip and charger only if not owned)

**Why:** Pramod saw keebie81's "Weather Forecast Cloud" on Instructables (Pinterest, 2026-11-27) and wants one, reusing the WLED strip we already have, in the same or different colours to suit us. A glanceable "what is tomorrow like" light, and a nice object.

**State:** idea, researched 2026-11-27. Nothing bought. The board, strip, mic and WLED software are all owned and spare since Diwali was packed away on 2026-11-26 ([diwali-lights.md](diwali-lights.md)).

**Assumptions** (made without asking; the Open items check them):
- "The WLED strip we already have" means the Diwali kit: the `wled-diwali` ESP32 at `192.168.1.127` (WLED 0.14.4 audioreactive, presets still on it) and the 284 px WS2812B door strip.
- Weather comes from HA's existing `weather.forecast_home`, not a new API key.
- The cloud hangs from the ceiling or a wall hook (wall/ceiling by default), on mains power through a USB charger.

#### Feasibility
**Yes - a well-known build, and easier here than in the original.**
- **The original** ([Instructables](https://www.instructables.com/Weather-Forecast-Cloud/) - the page renders by JavaScript and could not be read; the facts below are from the author's [GitHub repo](https://github.com/keebie81/Weather-Forecast-Cloud) it links, and [Embedded Lab, 2017](https://embedded-lab.com/blog/?p=13547)): a Raspberry Pi Zero, **19 NeoPixels** on GPIO18, a Python 2 script polling hourly.
- **Its colour logic** (`cloud_neopixel.py`): **red** if tomorrow's high is >10% above today's, else **gold** if tomorrow's low is >10% below today's, else **blue**. A slow brightness pulse (six steps, ~1.5s) if tomorrow's forecast code is anything but clear/cloudy - i.e. rain or snow.
- **Its weather source is dead.** It calls Yahoo's public YQL weather endpoint (`query.yahooapis.com`), which Yahoo shut down in early 2019 (from memory, not re-checked). Nothing of its code is worth reusing; the colour idea is.
- **Our version needs no new code on the device:** WLED does the effects, HA already has the forecast, and an HA automation picks the WLED preset. Others have done exactly this shape: [interactive WLED thunderstorm cloud](https://www.instructables.com/Interactive-LED-Cloud-With-Thunderstorm-Effects-an) (ESP32 + WLED + INMP441), [HA community weather cloud](https://community.home-assistant.io/t/iot-weather-cloud-light/142428), [Adafruit connected weather cloud](https://learn.adafruit.com/circuitpython-connected-weather-cloud.md?view=all).

#### Design notes
- **Board: the wled-diwali ESP32 (recommended).** Already on WLED, static .127, in HA as `light.diwali_lights` (rename it), and it comes with its own INMP441. Costs ₹0. Trap: `wol-to-esp32.md`, `wifi-analog-clock.md` and `hub75-wall-display.md` all count on this same spare board (`docs/hardware.md`), and Diwali 2027 will want it back for the door. Either the cloud lends it for the festival weeks, or Diwali 2027 buys a ~₹350 ESP32.
- **Pixels: 40-60 is plenty.** The original used 19. A 30-40cm cloud wants ~40-60 px coiled inside so the fill glows evenly, not in spots.
  - **Cut from the Diwali strip's far end** (piece B's pre-wired end, the one that already stops ~35-40cm short of the floor): ₹0, but the door outline loses another ~0.7-1m next Diwali. Ganapati 2027 ideas also eye this strip.
  - **Buy a new 1m (60 px) piece locally:** ~₹250-450 (estimate), keeps the door strip whole. Same 60/m GRB type, so WLED settings carry over.
- **Colour scheme - proposed, rain/storm first** (temperature swings of 10% matter less here than whether it rains; Pramod's call):

  | Forecast (next 12h or tomorrow - to decide) | Look | WLED |
  |---|---|---|
  | Thunderstorm | white flashes on dark blue | Lightning or PixelStorm effect |
  | Rain likely (precipitation chance >= ~50%) | blue, slow breathe | Breathe, blue (the original's pulse) |
  | Cloudy | soft white | Solid, low brightness |
  | Clear and hot (max >= 35°C) | orange-red | Solid |
  | Clear | warm gold | Solid |
  | No fresh forecast | **off** | nightlight timeout, below |

  The original's red/gold/blue on tomorrow vs today is the other option; both are just presets plus a template condition in HA, so switching later is cheap.
- **Never lie about state.** If HA or xero is down, the cloud would keep showing an old forecast. Fix: every time HA pushes a state, it also sets WLED's nightlight (`"nl": {"on": true, "dur": 120, "mode": 0, "tbri": 0}` in the JSON API), so the light fades to off if no refresh comes for 2h. Off reads as "unknown". To verify on the bench (the Claude item).
- **Power cuts:** mains-only, so it goes dark in a cut - acceptable for a decoration. On return, WLED's boot preset should be **off or a dim neutral**, not a weather colour, and the HA automation also triggers on the WLED entity becoming available (plus HA start and every forecast update), so the real state is pushed within a minute of power.
- **Power supply:** 40-60 px at a mood-light brightness is well under 1A; cap WLED at ~1500mA and run it off a 5V 2A USB charger through the Diwali build's USB-A breakout lead. The OnePlus 5V 4A works too but is overkill.
- **Night:** a coloured light in a bedroom at night is a problem; an HA schedule can dim it to ~5% or off after bedtime. Depends on the room.
- **Mic (optional bonus):** the board's INMP441 makes a sound-reactive "thunder" mode possible (claps or music trigger lightning), as in the interactive cloud above. Not needed for the forecast.
- **Shell:** a white paper lantern (30-40cm) or a light wire/cardboard frame, with polyester fibre fill (pillow stuffing) hot-glued on in tufts. Keep the ESP32 and the charger outside the fill, in the Diwali build's existing ABS box; fibre fill is flammable, the strip at low brightness is barely warm.
- **When built:** `docs/hardware.md` wled-diwali entry renamed and its Config updated; `projects/endpoints/endpoints.toml` entry for .127 un-marked as packed away; an HA tile in its room on the Home dashboard (ask which room) - CLAUDE.md rules.

#### Overlaps
- **Glanceable weather already exists in two places:** the Pi clock screensaver showed HA's weather and rain chance ([pi-clock-screensaver.md](pi-clock-screensaver.md), retired 2026-11-05), and [clawlight-small-display.md](clawlight-small-display.md) plans to bring clock/weather back. The cloud does the "will it rain" part without a screen.
- **Same spare board as** [wol-to-esp32.md](wol-to-esp32.md), [wifi-analog-clock.md](wifi-analog-clock.md) and [hub75-wall-display.md](hub75-wall-display.md); whichever is built first takes it.
- **Same strip as** [diwali-lights.md](diwali-lights.md) next year and the Ganapati 2027 ideas ([ganapati-2027-solar-system.md](ganapati-2027-solar-system.md)).
- **The same HA forecast fields** are read by the planned fixed-sentence answers in [voice-conversation.md](voice-conversation.md); one template sensor for "rain likely" can serve both.

#### Readymade alternatives
- **Cloud night lamps, India, ~₹430-900:** e.g. Nyrwana silicone cloud lamp (~₹430-490 on Amazon via [aggregator](https://www.dealsmagnet.com/deal/nyrwana-led-night-lamp-for-kids-multicolor-1bz1hauq), mid-2025), a [Flipkart cloud lamp](https://www.flipkart.com/nyrwana-delivering-smiles-inida-cloud-led-night-light-lamp-kids/p/itma4ea946a991e5) at ~₹807. Remote or touch only - **no forecast**, so they are decorations, not this project. One could be gutted as a ready-made shell for the strip, if the paper-lantern cloud looks wrong.
- **Designer smart clouds** (Richard Clarkson's "Cloud" lamps): imported, many thousands of rupees, effects only. Rejected.
- **Cloud-app RGB bulbs/strips (Wiz, Wipro, Tuya) in a cloud shell:** break in an ISP outage and cannot be pointed at xero - the Tinxy lesson. Rejected.
- **Honest note:** the phone and HA already tell the forecast; the value here is an ambient object at ₹0-1,000 that needs no screen and no unlock. No readymade does the forecast part.

#### Parts

```parts
qty | item | est | note
1 | ESP32 dev board on WLED | 0 | owned: wled-diwali (.127), with its INMP441 mic; spare since 2026-11-26
1 | White paper lantern, 30-40cm | 100-250 | local - gift/festival shop; estimate. Or a cardboard/wire frame
1 | Polyester fibre fill (pillow stuffing), ~500g | 150-300 | local - mattress or tailoring shop; estimate. Buy a little extra, density decides the diffusion
1 | Hot glue sticks (pack) | 50-100 | local; skip if the drawer has some. Glue gun assumed owned - check
1 | Fishing line or clear nylon thread + ceiling hook | 30-60 | local hardware shop; for hanging
1 | ABS project box | 0 | owned: the Diwali controller box, with the 470R and 1000uF cap already in it
1 | USB-A breakout power lead | 0 | owned: the Diwali build's lead (2026-11-02)
# Strip - cut from the Diwali strip
50 | WS2812B pixels (~0.8m) | 0 | owned: off the far end of piece B; the door outline is shorter next Diwali
1 | USB charger 5V 2A | 0 | probably owned; else ~150-250 local. Or the OnePlus 5V 4A from the Diwali kit
# Strip - new piece, door strip kept whole
1 | WS2812B strip 60 LEDs/m, 1m, 5V | 250-450 | local electronics shop; estimate. Same GRB type as the reel
1 | USB charger 5V 2A | 150-250 | local; skip if a spare is found
```

**Cost detail:** the header ₹300-1,200 covers lantern, fill, glue and thread (~₹330-710) at the low end with everything else owned, up to a new 1m strip and a charger (+₹400-700) at the high end. All prices are estimates; no listing was fetched for the craft parts. The cheapest variant: cut the Diwali strip, use a spare charger - about ₹350.

**Effort detail** (~7-10h, cheapest and most decisive first):
1. **Bench (1-2h, mostly Claude):** board on USB with 30 px, read `weather.forecast_home`'s forecast fields, save the six presets, test the nightlight timeout really goes dark.
2. **HA (1-2h):** a template sensor for the state, one automation (on forecast change, WLED available, HA start, hourly), night dimming, rename the entity, dashboard tile.
3. **Strip (1h):** cut/solder ~50 px, leads into the Diwali box, set LED count and current cap.
4. **Cloud body (3-5h) - this is the phase that overruns:** getting the fill dense enough to hide hot spots but thin enough to glow, coiling the strip so it lights evenly, gluing tufts, and the hanging and cable route. On this repo's history the mechanical part always runs long; the code does not.

#### Log
- 2026-11-27: recorded from Pramod's Discord idea (Instructables link). Original researched via its GitHub repo; Yahoo API dead, so the build is WLED + HA forecast. Board and strip from the packed-away Diwali kit; colour scheme proposed, open for his preference.
