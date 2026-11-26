# In-house smart switch to replace Tinxy
**Status:** Done

#### Open items
(none - the in-wall version continues as "In-wall smart switch (Tinxy replacement, phase 2)")

**Why:** Tinxy relay switches are cloud-dependent (`mqtt.tinxy.in`) - two concrete problems: (1) a data-breach/privacy exposure since control routes through Tinxy's cloud rather than staying local, and (2) they stop working during an ISP outage even though the LAN itself stays up (confirmed elsewhere - the whole house doesn't lose network, just internet), which defeats the point of switches that are physically on the same LAN as the HA server.
**State:** **building from scratch, decided 2026-11-05:** an ESP32 dev board + one relay per switch, ESPHome, LAN-only to HA - not a Tinxy reflash. Bench prototype in `projects/smart-switch/`: **working on the kandil since 2026-11-05** (`switch.smart_switch_bench_relay`, on the Diwali Lights schedule). **First job: the akash kandil for Diwali**, a plug-in load rather than a wall box, on the same schedule as the door lights. The in-wall version comes after.
#### Relay check
**Done 2026-11-05: SONGLE SRD-05VDC-SL-C** from the stash - 5V coil (runs off the ESP32 board's 5V), contacts 10A 250VAC / 10A 30VDC: plenty for lights and a fan, not for a geyser. Still unknown: bare cube or on a driver module (the README covers both, and the 3.3V low-trigger trap). Original brief:
Starts after "Diwali lights 2026" (user, 2026-10-30). Check the relays against this job: the coil voltage (5V suits an ESP32 board's 5V; 12V needs its own supply), the **contact rating on the AC side** (printed like `10A 250VAC`), comfortably above the load - fans and lights, and mind the inrush of LED drivers and fan motors - and whether they come on a module with a transistor/optocoupler driver, since an ESP32 GPIO cannot drive a bare relay coil.

#### Parts
Kandil build, from `projects/smart-switch/wiring.md` section 4. Kandil assumed to come with its own cable, B22 holder and plug.

```parts
qty | item | est | note
1 | ESP32 classic devkit (esp32dev, WROOM-32) | 0 | owned: the spare
1 | SONGLE SRD-05VDC-SL-C on a KY-019 relay module (S / + / -) | 0 | owned: from the stash
1 | USB data cable + 5V 1A charger | 0 | owned
3 | female-female jumper wires | 40-60 | local; the module and devkit pins are both male
1 | small latching rocker or toggle switch | 15-30 | local; optional, Tinxy-style manual on/off on the box (low voltage)
2 | lever connectors (WAGO 221, 2-way) or a 2-way cut of screw-terminal strip | 30-160 | local; joins neutral and earth in the box
1 | plastic junction box with screw lid | 60-150 | local; relay + mains joints on one side, ESP32 on the other
1 | 3-pin 6A plug | 40-80 | local; only if the kandil's plug is 2-pin (else the relay may switch neutral)
```

#### Options

- **Reflash existing Tinxy units with Tasmota/ESPHome** - *not taken (2026-11-05), but more viable than first thought:* ESPHome's device list has configs for the Tinxy 4N fan regulator (ESP8266 sending serial commands to a separate relay MCU; cut the W2/W3 link while flashing, web flasher fails at 115200) and the 1N 16A (ESP8266EX), and Tasmota runs on a 6-node. Newer Tuya-based boards may not flash. Original note: cheapest, reuses hardware already wired into the walls, would get fully local MQTT control with zero cloud dependency. Risk: Tinxy isn't a known-flashable brand like Sonoff, so it's a per-unit gamble (open one up, identify the chip, risk bricking it) before knowing if it's worth doing for the rest.
- **Replace with switches built for local control from the start** - Shelly (local HTTP/MQTT API) or Zigbee units behind a local Zigbee2MQTT coordinator. Zigbee in particular never touches the internet at all, only local HA, so it sidesteps the ISP-outage problem structurally rather than depending on a reflash succeeding. Real cost: these are wall-mounted and already installed, not a five-minute swap, and Shelly historically runs ~2x the bare-device price once wiring/casing is counted (see the cost note in the approach 1 findings under "Physical GPIO buttons" in ✅ Done).

#### Log
- 2026-10-30: moved to Active so it stays visible; work starts after the Diwali lights. Relay ratings check added as the first step.
- 2026-11-05: relay found (SONGLE SRD-05VDC-SL-C, 10A 250VAC). Chose a from-scratch ESP32 + relay build over reflashing Tinxy. Bench prototype in `projects/smart-switch/` (ESPHome, static .128, relay GPIO26, switch input GPIO27, restores state after power loss); config validated. First use: the akash kandil, on the Diwali Lights schedule.
- 2026-11-05: wiring diagram `projects/smart-switch/wiring.html` (https://claude.ai/artifact/LihsPvp3Lw9rA3HVgAu71v): module and bare-relay variants, kandil mains side. Kandil bulb is a 40-60W incandescent (B22): fine for the relay, T2A slow-blow fuse; LED bulb recommended for heat (declined: the kandil is jute, and the clear filament throws its weave as a shadow pattern an LED would wash out).
- 2026-11-05: wiring moved to Markdown + SVG so it renders on GitHub: `projects/smart-switch/wiring.md` with `wiring-svg/` (ESP32 to the KY-019 module, mains side). Only the build actually used is drawn; the other relay variants and the USB-string alternative were dropped (user: they add confusion). `wiring.html` removed.
- 2026-11-05: **flashed and in HA.** A fresh spare ESP32 (MAC `b0:3f:d3:51:77:ec`; the board first found on xero's USB was the living room voice satellite, left alone) flashed over USB, on 192.168.1.128, added to HA with `add_satellite_ha.py` (now takes `ESPHOME_SECRETS` for another project's board). WiFi prefers the bedroom AP `dlink_pramod_bed_room` (user; same password as the router), falls back to `dlink_pramod`; joined the bedroom AP at -67 dBm from xero's spot. New `WiFi network` / `WiFi access point` sensors show which. Relay came back on after the OTA reboot (restore works).
- 2026-11-05: **Done** (user) for the kandil prototype. The in-wall version moved to its own Backlog entry, "In-wall smart switch (Tinxy replacement, phase 2)"; the midnight-off check moved to "Diwali lights 2026".
- 2026-11-05: box on the wall, ESP32 back on its charger, rejoined the bedroom AP at -59 dBm, bulb on. Jute heat check dropped: same kandil and 60W bulb used safely for the past two Diwalis (user).
- 2026-11-05: **mains side built and working.** Plug pins metered: L-N open with relay off, 64 ohm on (60W cold filament), E open to both. Plugged into the fused strip: dark at plug-in, lit on HA's command. `switch.smart_switch_bench_relay` added to the three `diwali_lights_*` automations (HA backup `automations.yaml.bak-2026-11-05-kandil`); board added to `docs/hardware.md` and `endpoints.toml`.
- 2026-11-05: **low-voltage bench checks pass** (wiring.md section 5): LED follows HA (step 1, after an on_boot fix: a restored relay did not light the LED), module wired, one click per toggle with the module LED following (3), COM-NC beeps unpowered and COM-NO beeps on / silent off (4), relay restored on after a USB unplug (6). Rocker (2, 5) not fitted.
- 2026-11-05: the relay is on a KY-019-style module (S / + / -, NPN driver, no opto): high-trigger, works off 3.3V; firmware set to `relay_inverted: "false"`. Screw terminals unmarked, to be identified with a meter.
- 2026-11-26: kandil taken down (user). "Akash Kandil" tile removed from the Home dashboard; `switch.smart_switch_bench_relay` kept in HA - the board is free for another device, rename the entity then.
