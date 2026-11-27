# Workbench stock: jumper wires and project boxes
**Status:** Backlog
**Priority:** P3
**Cost:** ₹4,800-7,000 (sum of the parts list; optional micro-USB pairs not included)
**Effort:** ~1 evening (one shop trip)

#### Open items
- [ ] **Pramod:** buy on the next shop trip (all loose local stock)

**Why:** general stock for ESP32/Pi builds, so a build doesn't stall on a missing wire or end up as a bare board on the floor. Separate from the per-project parts lists, which still list their own box or jumpers when they need one.
**State:** added to the shopping list 2026-10-28, not bought. **Current jumper stock is running out** (user, 2026-10-28), so the jumpers are doubled; the box quantity is a sensible default.

```parts
qty | item | est | note
2 | Male-male dupont jumpers (40-pin strip, 20cm) | 200-300 | local - breadboard to breadboard
2 | Male-female dupont jumpers (40-pin strip, 20cm) | 200-300 | local - Pi/ESP32 header pins to breadboard
2 | Female-female dupont jumpers (40-pin strip, 20cm) | 200-300 | local - header to module pins (sensors, LEDs)
1 | Female-female dupont jumpers (40-pin strip, 10cm) | 80-120 | local - short runs inside a project box, so the wiring doesn't bunch up
1 | Berg strip / dupont housings, 2.54mm, assorted 1-8 pin (single row) + a few 2x4/2x5 | 100-200 | local - group several jumpers into one plug (e.g. mic or amp to ESP32, one plug per module). Reuses the jumpers' crimped pins: lift the 1-pin shell's latch with a needle, push the pin into the multi-way housing until it clicks. No crimper needed
1 | Dupont crimp tool for 2.54mm pins (SN-28B or similar, AWG 28-18) | 800-1500 | local if stocked, else online - for making jumpers to exact length from bare wire. Must say "dupont"/"2.54mm": JST/terminal crimpers have the wrong die
100 | Dupont crimp pins, female, 2.54mm | 80-150 | local - loose pins for the crimp tool; usually sold per 100
100 | Dupont crimp pins, male, 2.54mm | 80-150 | local - loose pins for the crimp tool; usually sold per 100
2 | Small ABS project box (~85x55x30mm), spare | 120-200 | local - for the next ESP32 or sensor build; the voice satellite and Diwali boxes are on their own entries
1 | DS3231 RTC module (ZS-042) + CR2032 cell | 150-250 | local - keeps time through power cuts for an ESP32 or Pi (I2C, 4 wires). With a CR2032, remove the board's charging resistor/diode first (it is built for a rechargeable LIR2032)
3 | USB-A female breakout board | 9-25 | local - out of stock on Robu (2026-11-17), check the local shop. With the 2 male ones on hand, makes 3 USB-A pairs for inline builds (charger in, device's own cable out, nothing cut). Pick boards that bring out D+/D-, not power-only
1 | USB-A male breakout board | 9-25 | local - the third male for the 3 pairs
3 | USB-C male breakout (plug) board | 50-100 | local - USB-C pairs, with the female boards below
2 | USB-C female breakout, 6-pin with 5.1k CC resistors | 20-40 | local - with the 24-pin one on hand, makes 3 USB-C pairs. The 5.1k resistors make a USB-C charger give 5V; a board without them gets no power
1 | M3 black nylon standoff + screw + nut assortment, 500 pcs (M-F and F-F hex spacers, assorted lengths) | 1628 | Amazon.in https://www.amazon.in/gp/product/B0F297R23T ₹1,628 (user, 2026-11-27) - mounts ESP32 devkits, modules and PCBs into project boxes and onto panels. Nylon, so no shorts against the board
1 | M2.5 nylon standoff + screw + nut kit, small | 150-300 | local - the M3 kit does not fit Raspberry Pi mounting holes (Pi uses M2.5)
# Optional: micro-USB pairs
3 | Micro-USB female breakout board | 10-20 | local - for older devices with micro-USB cables
3 | Micro-USB male breakout (plug) board | 20-40 | local
```

#### Log
- 2026-10-28: entry created for jumper wires and project boxes. Boxes for the voice satellites and the Diwali WLED controller moved to those entries' parts lists; two spares stay here. Jumpers doubled and a 10cm set added: current stock is running out. Berg strip (dupont) housings added for multi-pin plugs, then a dupont crimp tool and 100 each male/female crimp pins.
- 2026-11-14: DS3231 RTC module + CR2032 added (user), general stock - not needed by the USB charge switch.
- 2026-11-17: USB breakout pairs added (user): 3 USB-A, 3 USB-C, micro-USB optional. Counts allow for the 2 USB-A male and 1 USB-C female (24-pin) already on hand (`docs/hardware.md`).
- 2026-11-27: nylon standoff/spacer + screw kit (M2.5 and M3) added (user).
- 2026-11-27: standoff kit priced from an Amazon.in listing at ₹1,628 (user); budget raised to match.
- 2026-11-27: the Amazon kit is M3 only (500 pcs), so a small local M2.5 kit added for Pi boards.
