# USB fast-charge handshakes: can an ESP32 ask for more?

Reference for any future project that wants more than 5V from a phone charger
(a 12V LED strip, a motor, a battery charger, 5V at high current through a
buck converter). Written 2026-10-30, while choosing a supply for the Diwali
lights; nothing here has been built yet. Protocol details are from general
knowledge, not measured on these chargers, so check a library's schematic
and a meter before trusting a design.

## Summary

| Standard | Seen on | ESP32 alone? | How |
|---|---|---|---|
| **Qualcomm QC 2.0 / 3.0** | Motorola TurboPower, most USB-A fast chargers | **Yes** | Voltage levels on D+/D-, two GPIOs and resistor dividers |
| **USB-C PD** (incl. PPS) | GaN chargers, most USB-C chargers | **No - add a PD chip** | FUSB302 / STUSB4500 / CH224A over I2C |
| **Fixed PD trigger** | same | not needed | CH224K or IP2721 module, voltage set by resistor/jumper |
| **Samsung AFC** | Samsung chargers | possible | Single-wire, reverse-engineered, timing-sensitive; little reason to |
| **OnePlus Dash / Warp / SuperVOOC** | OnePlus | **No** | Proprietary, with authentication chips in phone and cable |

Rule of thumb: USB-A / QC charger -> ESP32 alone. USB-C charger -> ESP32 +
FUSB302 or STUSB4500 when software picks the voltage, CH224K when it is fixed.

## Qualcomm Quick Charge (QC 2.0 / 3.0)

The handshake is analogue levels on the USB data lines, so an ESP32 can do it
with GPIOs and resistors:

1. Hold **D+ at 0.6V** (D- low) for about **1.25s**. The charger then releases
   its D+/D- short and starts listening.
2. Set a pair to pick the voltage:

| D+ | D- | Output |
|---|---|---|
| 0.6V | 0V | 5V |
| 3.3V | 0.6V | 9V |
| 0.6V | 0.6V | 12V |
| 3.3V | 3.3V | 20V (Class B chargers only, rare) |
| 0.6V | 3.3V | QC3 continuous mode: pulse D+ to 3.3V for +200mV, D- to 0.6V for -200mV |

- The 0.6V levels come from a resistor divider off a GPIO (or two GPIOs per
  line so one line can be 0V / 0.6V / 3.3V). Existing Arduino libraries such as
  **QC3Control** show a working divider and port to the ESP32 easily (3.3V
  GPIOs are what the protocol wants).
- Current stays at what the charger is rated for at that voltage: the Motorola
  here is 5V 1.6A / 9V 1.6A / 12V 1.2A, so QC buys voltage, not 5V current.

## USB Power Delivery (USB-C)

PD runs over the CC wire as a 300kbps BMC-encoded protocol with tight timing
and CRCs - not something to bit-bang from ESP32 software. Use a controller:

- **FUSB302** - the ESP32 drives the whole negotiation over I2C; full control,
  including **PPS** (any voltage in 20mV steps with a current limit - useful for
  LED drivers and battery charging). ESP32/Arduino libraries exist.
- **STUSB4500** - sink controller with settings in its own NVM; works without
  the ESP32 after it is programmed, I2C to change them.
- **CH224A** - cheap, I2C-selectable fixed voltages.
- **CH224K / IP2721** - no MCU at all: a resistor or jumper picks 9/12/15/20V.
  Modules about Rs 100-200 (estimate).

Without any negotiation a USB-C charger still gives **5V up to 3A** to a sink
that presents **5.1k pull-downs on CC1 and CC2** (most cheap USB-C breakouts
have them). For 5V at more than 3A, request 20V and step down with a buck
converter: a 65W charger is ~20V x 3.25A -> roughly 5V at 10-12A after a good
buck. Full 100W (20V 5A) also needs a **5A e-marked cable**; otherwise 60W.

## Proprietary: OnePlus, and why not

Dash, Warp and SuperVOOC deliver high current at low voltage only after an
authenticated handshake between the charger, a chip in the cable and the
phone. It is only partly reverse-engineered and there are no off-the-shelf
trigger boards. To anything else they look like an ordinary charger, often
~5V 2A - which is why the Diwali lights load-test the OnePlus "5V 4A" brick
before trusting it. Newer OnePlus chargers often also speak PD; use that.

## Design rules

- **Everything downstream must survive the highest voltage you can ask for.**
  The ESP32 needs its own regulator rated for it (a 20V-tolerant buck, not an
  AMS1117 linear off 20V).
- **The safe state is 5V.** PD and QC fall back to 5V when the sink resets or
  the handshake stops; do not add anything that latches a high voltage.
- **Request, then verify** with an ADC divider on VBUS before switching the
  load on.

## Chargers on hand (2026-10-30)

| Charger | Ratings | Notes |
|---|---|---|
| OnePlus fast charger | label 5V 4A (Dash-style) | proprietary; full current unverified without a OnePlus phone |
| Motorola TurboPower | 5V 1.6A, 9V 1.6A, 12V 1.2A | QC-compatible: the easy ESP32 case |
| GaN, "100W" | 2x USB-C, 1x USB-A | per-port ratings not read yet; PD |
| GaN, "65W" | 2x USB-C, 2x USB-A | per-port ratings not read yet; PD |
