# Which board for a hardware project

Reference for picking the controller when a new hardware idea comes up, so
the same comparison isn't re-derived each time. Written 2026-09-18 out of the
question "the Pi is more powerful than an ESP32, so why keep reaching for the
ESP32?".

Prices are rough local-shop estimates in rupees, same convention as
`PROJECTS.md` parts blocks: loose stock, bought by value. ESP32 and Arduino
clones are normally stocked locally; Pi Zero and Pico are usually online-only
here and marked up - worth confirming at the shop rather than assuming.

## The rule of thumb

**Does the job need an OS, a filesystem, containers, or Python libraries?**
Use a Pi.

**Is it one job that must start instantly and survive power being yanked?**
Use a microcontroller.

"More powerful" is rarely the axis that decides. Reliability across power
cuts, timing precision, idle draw and maintenance cost are.

## The options

| Board | ~Price | What it is | Where it fits here |
|---|---|---|---|
| **ESP8266** | 150-250 | 1 core 80MHz, WiFi, fewer pins, no BT | Enough for a WoL sender or a clock |
| **ESP32** (the default here) | 400-600 | 2 cores 240MHz, WiFi+BT, I2S, ADC, hardware LED timing | Anything with audio, many pixels, or several sensors |
| **ESP32-C3** | 300-500 | Cheap RISC-V single core, WiFi+BLE | A cheaper ESP32 when I2S and spare pins aren't needed |
| **ESP32-C6** | 600-900 | Adds Zigbee and Thread radios | Could be the Zigbee coordinator that the curtain, smart-switch and door-sensor ideas are all parked on |
| **ESP32-S3** | 600-900 | More RAM, USB-OTG, camera support | Only if RAM or a camera is the constraint |
| **ESP32-CAM** | 400-700 | ESP32 + OV2640, no USB port (needs a programmer) | Already the pick for the UPS LED monitor |
| **Arduino Uno / Nano (AVR)** | 200-500 | 16MHz, 2KB RAM, **no networking**, 5V logic | Wrong for almost everything here - nothing reaches MQTT or HA |
| **Arduino Uno R4 WiFi / Nano ESP32** | 900-2500 | An ESP32 in an Arduino shape | Same capability as an ESP32 at 2-4x the price |
| **Pi Pico / Pico W** | 350-800 | RP2040 microcontroller, WiFi on the W, PIO for exact timing | Excellent at LED timing; no ESPHome, no WLED |
| **Pi Zero 2 W** | 1500-2000 | Full Linux, WiFi, 4 cores | Only when Linux itself is the requirement |
| **Pi 3B / 4** | (owned) | Full Linux with Ethernet | What the wol-sender Pi already does |

## Why a Pi being more powerful is often the wrong trade

Every point below is something this homelab has already lived through:

- **Power cuts.** A Pi wants a clean shutdown, and its SD card is what
  corrupts. The `overlayroot` hang that made the Pi unbootable (2026-08-20)
  and it coming up 4.5min *after* xero during the 2026-09-06 outage are both
  this. A microcontroller has no filesystem to corrupt and boots in under a
  second, which is the whole argument for moving the WoL job off the Pi.
- **Idle draw.** The Pi 3B with its fan is ~2.5W continuous; an ESP32 is
  ~0.2-0.5W, and microamps in deep sleep. That difference is real on a UPS,
  see the home power audit.
- **Timing.** WS2812 strips need microsecond-accurate bit timing. The ESP32
  has dedicated hardware (RMT) for it; on a Pi it means DMA plus a PWM pin
  that clashes with the onboard audio output.
- **Maintenance.** A Pi is another Linux box to patch, back up and watch. An
  ESP32 runs the same firmware for years with nothing to update.
- **Boot time.** ~1s against ~30s, which matters for anything that has to act
  the moment mains returns.

The Pi wins whenever the job genuinely needs Linux: Docker (Node-RED), a real
filesystem, Python with libraries, ssh for debugging, or Ethernet.

## Arduino is a framework, not only a board

The ESP32 sketches in this repo (`esp32/wol_on_boot/wol_on_boot.ino`) are
already Arduino code - Arduino is the C++ framework and toolchain, and it
targets ESP32 as well as AVR. So "use Arduino instead" usually means an
**AVR** board (Uno, Nano), and that is the part to be careful about: no WiFi,
2KB of RAM, and 5V logic. Nothing on an AVR reaches MQTT or Home Assistant
without adding a network shield that costs more than an ESP32.

The one AVR advantage worth knowing: 5V logic drives a 5V WS2812 data line
inside spec, where 3.3V boards are technically under it (in practice they
work - the aarti ESP32 drives 180 pixels with no level shifter).

## The real reason ESP32 keeps winning here: ESPHome

For anything sensor- or switch-shaped, ESPHome means writing YAML instead of
firmware, and Home Assistant discovers the device by itself - MQTT topics,
entity names, availability and all. That is what turns the door sensors into
a weekend job instead of a firmware project. WLED (the aarti lights) is
likewise ESP-only.

Neither a Pi nor an AVR Arduino gets either ecosystem. On a Pi, every
integration is hand-built: a Python script, a systemd unit, an MQTT client,
discovery messages, a last-will. That is exactly what
`scripts/pi-buttons/*.py` and `scripts/clawlight/clawlight-led.py` are, and
it works, but each one is code to own.

## How this repo's projects actually landed

| Project | Board | Why |
|---|---|---|
| Aarti lights | ESP32 | I2S mic + audioreactive WLED; an ESP8266 cannot do it |
| WoL sender | Pi today, ESP32 planned | Needs mains-only power and a fast boot, not Linux |
| UPS LED monitor | ESP32-CAM | Camera reading 4 LEDs 5mm apart |
| Door sensors | ESP32 + ESPHome (or battery Zigbee) | Cheap wired inputs, HA discovery for free |
| Pegboard clawlight strip | The Pi already there | No new board needed; short data run |
| Homelab health LED | Pi GPIO | Same reason - the Pi is at the desk |
| Buttons (white noise, scenes) | Pi GPIO | Pi was already there and needed to be anyway |
| WiFi analog clock | Any MCU; ESP8266 is enough | One job, tight-ish timing, no OS wanted |

## Traps that apply to every board here

- **3.3V logic into a 5V WS2812 strip** is out of spec but works in practice
  at short runs. A 74AHCT125 is the fix if the first pixel flickers.
- **Strapping pins.** ESP32 GPIO0/2/12/15 and the Pi's GPIO0/2/12/15 can stop
  a board booting if something holds them at the wrong level at power-up. Use
  ordinary pins: see `docs/gpio_pinout.md` for the Pi, and the aarti setup doc
  for the ESP32.
- **ADC2 pins stop reading once WiFi is up** on an ESP32, which on an
  always-connected node means always. Analog sensors go on ADC1
  (GPIO32-39).
- **Publish an MQTT last-will** on anything that reports state. A dead node
  that leaves a retained "all fine" behind is worse than no node.
- **Never power a strip or motor from a board's own 5V pin,** especially not
  the wol-sender Pi's, which has undervoltage history.
