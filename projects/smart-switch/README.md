# smart-switch - in-house replacement for the Tinxy switches

A wall switch we build ourselves: an ESP32 dev board driving one relay, running
ESPHome and talking to Home Assistant over the **LAN only** (ESPHome native API).
It replaces the Tinxy modules, which route every click through `mqtt.tinxy.in`
and so stop working in an ISP outage and leak usage to a vendor cloud. The story
and decisions are in `PROJECTS.md` under "In-house smart switch to replace Tinxy".
Decided 2026-11-05: build from scratch instead of reflashing the Tinxy units.

**Stage now: bench prototype, one switch.** Nothing is in a wall yet.

| | |
|---|---|
| Runs on | ESP32 classic dev board (`esp32dev`), static `192.168.1.128`, mDNS `smart-switch-bench.local` |
| Relay | SONGLE SRD-05VDC-SL-C from the stash: 5V coil, contacts 10A 250VAC / 10A 30VDC |
| Talks to | HA's ESPHome integration, API `:6053` (encrypted, key `api_key` in `esphome/secrets.yaml`), OTA `:3232` |
| Secrets | `esphome/secrets.yaml`, **gitignored**: WiFi/OTA/AP copied from the voice satellites, its own `api_key` |
| Build | `esphome/esphome.sh` - ESPHome in docker, same wrapper as `projects/voice-assistant/esphome/` |

| File | What |
|---|---|
| `esphome/smart-switch-bench.yaml` | the firmware: relay on GPIO26, switch input on GPIO27, blue LED (GPIO2) mirrors the relay, restores its last state after a power cut |
| `esphome/esphome.sh` | `config` / `compile` / `run` / `logs` / `flash-bin` |

## Bench wiring (no mains yet)

- **Relay module** (blue board with IN/VCC/GND): VCC -> ESP32 `VIN` (5V from USB),
  GND -> `GND`, IN -> `GPIO26`.
- **Bare relay** (just the cube): it cannot hang off a GPIO, the coil wants ~70mA.
  Drive it through an NPN (BC547/2N2222): GPIO26 -> 1k -> base, emitter -> GND,
  collector -> one coil pin, other coil pin -> 5V, and a **1N4007 across the coil**
  (stripe to 5V) to eat the kick when it switches off. Set `relay_inverted: "false"`.
- **Switch input:** any switch or a jumper wire between `GPIO27` and `GND`.
  Low voltage only.

## Run it, in order

```bash
cd ~/code/homelab/projects/smart-switch/esphome
./esphome.sh config                              # check the YAML (cheap)
./esphome.sh run --device /dev/ttyUSB0           # first flash over USB, then live logs
# later changes go over WiFi:
./esphome.sh run --device 192.168.1.128
```

Then in HA: Settings -> Devices -> Add integration -> ESPHome, host `192.168.1.128`,
key = `api_key` from `esphome/secrets.yaml`. Entities: `Relay`, `Wall switch`,
`WiFi signal`, `Uptime`.

Bench checks, before any mains:
1. Toggle `Relay` in HA: it clicks, the blue LED follows, a multimeter shows
   COM-NO closed when on and open when off.
2. Flip the switch on GPIO27: the relay toggles, and HA updates.
3. Unplug the router (or block the board's WiFi): the switch still toggles it.
4. Pull USB power while on, plug back: it comes back on.

Only then: a mains test with a lamp on a plug, all terminals inside a closed box.

## Traps

- **Low-trigger module + 3.3V GPIO.** Many blue modules switch on when IN is pulled
  low, through an optocoupler fed from VCC. With VCC at 5V, the ESP32's "high" is
  only 3.3V, which can leave enough current through the opto that the relay never
  lets go, or chatters. If it sticks on: use the module's `JD-VCC` jumper
  (VCC to 3.3V, JD-VCC to 5V), a high-trigger module, or the bare relay + NPN above.
- **10A on the cube is not 10A on a cheap module.** The traces and screw terminals on
  hobby boards are the weak point. Fine for lights and a ceiling fan; nothing
  heavy (geyser, AC, heater).
- **A relay cannot do fan speed.** If a Tinxy node regulates a fan, this design only
  replaces it as on/off.
- **In the wall, the switch stops carrying mains.** The plan is to rewire the existing
  rocker as a low-voltage input to the ESP32; it must be fully disconnected from
  mains. The in-wall build (HLK-PM01-class 5V supply, fuse, enclosure, wiring
  diagram) is the next design step, not done here.
