# Door open/close and lock status (main, safety, balcony)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** take the strike plates off both entrance doors - measure the main door's strike box depth against the deadbolt's full throw, see what is behind the grill door's slot
- [ ] **Pramod:** check for a socket near the entrance and measure the grill door's closed gap
- [ ] **Together:** bench-test magnet + reed and magnet + hall sensor against the actual bolts, before chiselling or drilling anything

**Why:** nothing in HA currently knows whether any door in the house is shut. The everyday want is "was the balcony door left open with the AC running" and "is the main door still standing open" and "did anyone actually lock the front door"; the later want is an alert if the front door opens while nobody is home. Everything downstream already exists - Mosquitto, HA, and the self-hosted ntfy push path built for clawlight - so this project is only about getting three binary states into MQTT honestly.
**State:** idea only, nothing bought or built. Design is settled on paper: a door reed plus a bolt sensor in the keeper per door, giving **open / shut but unlocked / locked**, most likely on a wired ESP32/ESPHome node (option A). **The blocker is power and wiring, not the sensing.**

#### The three doors
Three doors, and they are deliberately listed separately because they are not the same problem:
- **Main door** - hinged wooden door, **mortise lock with deadbolt**. Leaf and frame meet flush, so a plain surface-mount reed contact on the hinge-opposite side is the textbook case. Easiest of the three.
- **Safety door** - hinged steel grill door outside it, also a **mortise lock with deadbolt**. **The metal is the complication.** A reed contact screwed straight onto a steel frame has its magnet's flux shunted by the surrounding metal and the effective operating gap collapses - a pair that works fine on the wooden door can sit there reading "open" while the grill is actually shut. Fix is either a wide-gap contact sold for metal doors (18-25mm rated) or packing both halves out on a few mm of non-ferrous spacer (plastic or wood shim). Grill doors also often close with a sloppier, less repeatable gap than a solid door, which is the second reason to buy gap headroom here rather than the cheapest pair.
- **Balcony door** - sliding, **single-point sliding latch** (a hook/lever on the panel engaging a keeper on the fixed frame). Reed on the fixed frame, magnet on the moving panel where it lands when fully closed. Mechanically the easiest fit of the three (the closed position is repeatable and the gap is fixed by the track), and it answers exactly the question worth asking, since this is the door most likely to be left a few cm ajar.

#### Lock state - sense the bolt inside the keeper (decided 2026-09-15)
**Sense the bolt inside the keeper, on the frame side.** A reed on the door only says shut, and shut-but-unlocked is the state actually worth an alert. All three locks push a bolt or hook into a keeper on the fixed frame, and that is where to sense it:
- **Why the keeper, not the lock body or the knob.** A bolt sitting in the keeper proves shut *and* locked in one reading - a deadbolt thrown while the door stands open sticks out into air and correctly reads unlocked. It also proves the bolt went fully in, which a sensor on the inside thumb-turn cannot (a single key turn, or a bolt jammed short on a swollen frame, both look locked from the knob). And the frame never moves, so no wire crosses a hinge and nothing on the leaf needs a battery.
- **Non-contact only.** A small neodymium disc magnet (~5x2mm) set into a shallow pocket drilled in the bolt's end face, with the sensor behind the keeper. Recessed, not stuck on the face: a disc proud of a retracted bolt sits in the few-mm gap between door edge and frame and can scrape as the door swings shut. Deliberately *not* a lever microswitch the bolt presses: one placed a millimetre too shallow stops the deadbolt throwing fully, and a sensor that can stop the front door locking is worse than no sensor.
- **Main door (wooden frame):** drill a small hole straight back from the back wall of the strike box and push a plastic-bodied reed into it, **its long axis along the bolt's travel** so the magnet points at its end - a reed lying crosswise with the magnet at its middle has a dead spot where both blade tips take the same pole and never close, however near the bolt gets. The reed must close only at *full* throw - these deadbolts throw in two key turns, and one turn must read unlocked - so the magnet's reach has to land between the full-throw gap and the one-turn gap. **Steel behind the magnet costs nothing; steel around it shortens reach** (a magnet recessed into a steel bolt loses more than one in brass), which moves that number but not the design. Check the bolt with a fridge magnet, then find the real reach with a multimeter on continuity before drilling anything.
- **Safety door (steel frame):** an **analog hall sensor** (SS49E class) instead of a reed. The steel frame surrounds the whole strike box and gives the field a short path home around the sensor, and an analog reading lets the threshold be calibrated in place (log bolt-in and bolt-out values in ESPHome, split the difference) where a reed would just fail or false-trigger. **Feasibility unknown until the strike is inspected:** grill door frames are often hollow steel section with the keeper as a bare slot or welded box - no wood to chisel. It may mean drilling a small hole into the back of the box, or mounting the hall sensor on the frame face beside the slot and living with a weaker signal.
- **Balcony door (aluminium frame):** magnet on the latch hook's tip, reed on the fixed frame beside the keeper. Aluminium is non-ferrous, so no shunting - the easy one. Sliding panels have a few mm of play in the track, so place the magnet with margin rather than at the edge of pull-in. Keep the separate panel reed as well (₹60): hook engaged implies shut, but "shut, unlatched" and "open a crack" are different answers for the AC case.

That gives every door three states - **open / shut but unlocked / locked** - from two sensors each.

#### Smart lock considered and rejected
**Tinxy door lock (₹4,699).** Its own listing describes its door sensor as "Opened/Closed", the same thing a ₹60 reed pair reports, not bolt state; it is mains-powered (a reviewer notes it falls back to the key without inverter backup); and it carries the same cloud/privacy concern as the rest of the Tinxy gear. The deeper reason holds for any smart lock, local ones included (Aqara, Nuki - and Nuki targets euro-profile cylinders that Indian mortise locks mostly are not, on top of doubtful India availability): **this project only needs to read.** A compromised sensor can lie, or leak when the house is empty; a compromised network-operable lock can open the front door. Sensing-only caps the worst case at privacy.

#### Power and wiring options
**The blocker is power and wiring, not the sensing** - same shape as most projects here. Three ways to do it:
- **(A) One wired ESP32/ESPHome node per location.** The main and safety doors share a doorway, so a single ESP32 at the entrance covers both with ~1m runs - four inputs (two door reeds, the main door bolt reed, the safety door hall sensor). The balcony door then needs either its own node or a long wire run across the flat. A reed is a dry contact, so cable length costs nothing electrically - it is purely about where wire can be run without it looking terrible. Cheapest per door, no batteries ever, and it matches the existing preference for WiFi-native devices that join the current infra directly.
- **(B) Battery Zigbee door sensors** (Aqara/Tuya class, ~₹700-1200 each). Zero wiring, coin-cell life measured in a year or more, and the only option that can go on a door with no power anywhere near it. Cost is a Zigbee coordinator (~₹1500-2500) that does not exist yet - but note the standing synergy: both "Remote controlled curtains" and "In-house smart switch to replace Tinxy" are already parked partly on the same missing coordinator. Three projects sharing one purchase changes that maths.
- **(C) Battery WiFi door sensor / deep-sleeping ESP32** - the tempting middle ground, and the one to avoid. Waking, associating to WiFi and publishing takes a second or more per event and costs far more energy than a Zigbee radio's burst, so a door that gets used all day eats cells in weeks. ESP-NOW fixes the energy side but then needs its own always-on gateway, which is a whole extra moving part for three binary sensors.
- **Lock sensing tips it firmly towards (A).** A bolt sensor lives inside a strike box, which suits a wired reed or hall sensor and not a coin-cell Zigbee puck. A few Zigbee contact sensors accept an external reed on terminals, but that is the wired build again with a battery added.

#### ESP32/ESPHome traps (option A)
**If it goes the ESP32/ESPHome route (A), the traps are known ones:**
- **Avoid the strapping pins.** A reed holding GPIO0/2/12/15 low at power-up can stop the board booting at all - and it would do it only when that door happens to be shut, which is a miserable thing to debug. Use GPIO25/26/32/33 for the reeds.
- Wire reed to GND against `INPUT_PULLUP`, no external resistor needed, and put `delayed_on`/`delayed_off` filters (~100ms) on every input - reeds bounce, and a long run to a door frame is a decent antenna.
- **The hall sensor goes on an ADC1 pin (GPIO34/35/36/39).** ADC2 pins stop reading once WiFi is up, which on an always-connected node means always. Power it from **3.3V, not 5V** - its output sits around half the supply, and at 5V it swings past what the ESP32's ADC can read. It needs three wires to the frame (3.3V, GND, signal) against a reed's two.
- Keep both halves of each sensor on non-moving surfaces (frame and leaf). Nothing should cross a hinge; that is the failure that shows up months later as an intermittent.
- **Publish with an MQTT last-will.** This is the same staleness lesson as the health LED project, and it bites harder here: a dead sensor node that leaves a retained "closed" behind is worse than no sensor, because it actively asserts the safe answer. ESPHome's MQTT availability topic handles this for free - HA shows *unavailable* instead of a confident lie.

#### Automations worth having
Once the three states exist: ntfy push if the main door stays open past a few minutes; **shut but unlocked** late at night, or when the last person leaves; balcony door open while the AC is on (the Miraie integration is already there); front door opening while everyone is out; and the open/closed tiles on the consolidated status dashboard.

#### Unknowns to settle before buying anything
- whether there is a power socket near the entrance at all (decides A vs B on its own)
- how far the balcony door is from that entrance node
- what the actual closed gap is on the grill door (measured with it shut - that number picks the contact)
- **how deep the main door's strike box is** against the deadbolt's full throw
- **what is behind the grill door's strike slot** - a cavity, a welded box, or solid steel

#### Parts
```parts
qty | item | est | note
3 | Surface-mount magnetic reed door contact (pair) | 150-250 | local - alarm/security shop; get a wide-gap/metal-door type for the grill door
2 | Reed switch, plastic-bodied | 30-60 | local - main door strike box + balcony latch keeper; bare glass ones crack when seated
2 | SS49E analog hall sensor | 30-60 | local - safety door strike; one spare, they are cheap
6 | Neodymium disc magnet ~5x2mm | 30-60 | local - one per deadbolt/hook plus spares; they chip and go missing
1 | Two-part epoxy (Araldite) | 80-150 | household/local - magnets onto bolt faces
1 | ESP32 dev board with USB | 400-600 | local - one at the entrance covers both doors, all four inputs
1 | ESP32 dev board with USB (balcony) | 400-600 | only if a wire run from the entrance node is not acceptable
15 | 4-core alarm/security cable, per metre | 225-375 | local - one run per door carries its door reed + bolt sensor; hall sensor needs 3 cores
2 | 5V USB charger + cable | 200-300 | household - likely already on hand, do not buy blind
1 | Small ABS project box | 60-100 | local - keeps the board off the floor by the door
```

Roughly **₹1600-2600** for both nodes with lock sensing, going the wired ESP32 way - all of it loose local stock with nothing to order ahead. The Zigbee path (B) is cheaper in effort and dearer in rupees, and only makes sense bought together with the curtain/switch projects.

#### Log
- 2026-09-12: noted.
- 2026-09-15: decided to sense lock state at the bolt inside the keeper, on the frame side.
