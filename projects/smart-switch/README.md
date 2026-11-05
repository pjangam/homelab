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
| Relay | SONGLE SRD-05VDC-SL-C on a KY-019-style module (S / + / -, NPN driver, high-trigger), from the stash: 5V coil, contacts 10A 250VAC |
| Talks to | HA's ESPHome integration, API `:6053` (encrypted, key `api_key` in `esphome/secrets.yaml`), OTA `:3232` |
| Secrets | `esphome/secrets.yaml`, **gitignored**: WiFi/OTA/AP copied from the voice satellites, its own `api_key` |
| Build | `esphome/esphome.sh` - ESPHome in docker, same wrapper as `projects/voice-assistant/esphome/` |

| File | What |
|---|---|
| `esphome/smart-switch-bench.yaml` | the firmware: relay on GPIO26, optional rocker on GPIO27 (Tinxy-style: flip on = on, flip off = off, app can override), blue LED (GPIO2) mirrors the relay, restores its last state after a power cut |
| `esphome/esphome.sh` | `config` / `compile` / `run` / `logs` / `flash-bin` |
| `wiring.md`, `wiring-svg/` | wiring drawings and bench guide |

## Wiring

**[`wiring.md`](wiring.md)** - the two drawings (`wiring-svg/`, ESP32 to the relay
module, and the kandil's mains side), the connection tables, the parts checklist and
the bench checks in order. In short: module **S -> `GPIO26`, + -> `VIN`, - -> `GND`**;
an optional rocker between `GPIO27` and `GND`; mains live through a T2A slow-blow fuse to
**COM** (middle terminal), **NO** (the end opposite the NC marking) to the bulb.

The drawings are standalone SVG files, edited directly. They render on GitHub; keep
literal colours and system fonts in them (see `.claude/agents/circuit-diagram.md`).

## Run it, in order

```bash
cd ~/code/homelab/projects/smart-switch/esphome
./esphome.sh config                              # check the YAML (cheap)
./esphome.sh run --device /dev/ttyUSB0           # first flash over USB, then live logs
# later changes go over WiFi:
./esphome.sh run --device 192.168.1.128
```

Then in HA: Settings -> Devices -> Add integration -> ESPHome, host `192.168.1.128`,
key = `api_key` from `esphome/secrets.yaml`. Entities: `Relay`, `Switch position`,
`WiFi signal`, `Uptime`.

Then run the checks in `wiring.md` section 5, in order. Mains only after step 6.

## Traps

- **10A on the cube is not 10A on a cheap module.** The traces and screw terminals on
  hobby boards are the weak point. Fine for lights and a ceiling fan; nothing
  heavy (geyser, AC, heater).
- **A relay cannot do fan speed.** If a Tinxy node regulates a fan, this design only
  replaces it as on/off.
- **In the wall, the switch stops carrying mains.** The plan is to rewire the existing
  rocker as a low-voltage input to the ESP32; it must be fully disconnected from
  mains. The in-wall build (HLK-PM01-class 5V supply, fuse, enclosure, wiring
  diagram) is the next design step, not done here.
