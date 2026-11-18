# Ganapati 2027: counter-rotating spiral discs (kinetic backdrop)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** measure a golden-snitch spinner bearing (bore / OD, likely 608 = 8mm / 22mm) and pick the axle to match
- [ ] **Pramod:** try the motor already owned on a cardboard disc; note its RPM (target 3-10 RPM at the disc)
- [ ] **Pramod:** card test of the belt drive: two cardboard discs, spinner bearing, rubber bands as belts, one crossed; judge speed and look
- [ ] **Pramod:** only if going the gear way: buy an assorted plastic gear kit (~₹200-300, Amazon) for the sun, idler and worm
- [ ] **Claude:** when asked, draw a printable sun / idler / ring-gear template (card test) with matching tooth size
- [ ] **Pramod:** watch the flat2form reel (Part 1, mechanism) and note how its three gears sit (bevel pinion between two facing gears, or flat gears)
- [ ] **Pramod:** find a local MDF laser-cutting shop for the discs, or settle on cardboard/cardstock discs
- [ ] **Together, mid-2027 (close to the festival):** pick one of the Ganapati 2027 ideas (this, solar system, or any added later); if this one, fix the disc diameter
- [ ] **Pramod:** bench test: a 5-10 RPM motor and two hand-cut cardboard spirals, held up behind the makhar, to judge the speed and the look before cutting anything
- [ ] **Claude:** once the size is fixed, draw both spirals plus the spur-and-idler gears and the motor plate as one SVG for the laser shop
- [ ] **Pramod, by 2027-07:** order the laser cutting before the makhar shops' pre-festival rush; finish it and run it for a week before 2027-09-04

**Why:** a decoration idea for next Ganapati (user, 2026-11-06): two wheels on the same axle turning in opposite directions, from a Pinterest reference (https://pin.it/2RDKE7ECj). Mechanism reference sent 2026-11-07: [flat2form reel](https://www.instagram.com/reel/DdRryVFNsgJ/).
**State:** idea only, researched 2026-11-06, nothing decided or bought. **Deadline: Ganesh Chaturthi is Saturday 2027-09-04** ([Drik Panchang](https://www.drikpanchang.com/festivals/ganesh-chaturthi/ganesh-chaturthi-date-time.html?year=2027); one Drik page shows the tithi starting 01:48 on 2027-09-03). It must be built and have run unattended for days before then.

#### The reference (what the pin shows)
- **The link opened, but only as a still.** `pin.it` redirects to Pinterest pin 1096767315540186871, a 50s user-uploaded video. Only its cover frame and caption could be fetched, not the video, so **the mechanism itself was not seen.**
- **The cover frame shows** a maker holding a laser-cut MDF disc of curved, sunburst-like spiral arms over a second spiral layer behind it, with a metal hub/bushing at the centre. The caption is generic ("woodworking ideas").
- **Mechanism reference: [flat2form, "Part 1 - Building the mechanism"](https://www.instagram.com/reel/DdRryVFNsgJ/)** (user, 2026-11-07). Only the cover image and caption could be fetched, not the video:
  - **It is a Ganesh decoration, in paper.** The cover shows a cardstock mandala ("two chakras"), red and gold, with spiral arms inside a fixed ring and a petal border. It stands on legs made of rolled paper tubes. Hashtags: GaneshDecoration, PaperMechanism.
  - **The caption gives the drive:** "Two independent shafts, three gears, and a single motor". Part 1 covers the mechanism and motor; Part 2 makes the chakras.
  - **The gear layout is not confirmed.** Three gears and two shafts is exactly the bevel layout (A below: a pinion between two facing gears), whereas the spur layout (B) needs four. But the video was not seen, so that is an inference.
- **Third reference: [Instructables, "Spinning Kinetic Sculpture Without Motor Only Spring"](https://www.instructables.com/Spinning-Kinetic-Sculpture-RGB)** (user, 2026-11-17). Only the title and search snippets could be read, not the steps:
  - **No motor: a wound spring drives it**, and an off-centre weight makes each wheel swing like a pendulum. Runs 30+ minutes at irregular, varying speeds; wall-mounted.
  - **Not a counter-rotation mechanism** as far as the snippets say: the wheels spin at different speeds, not locked equal and opposite.
  - **RGB is optional and separate:** a ~70mm addressable LED ring on an ATtiny, a switch and a battery or adapter. Only the LEDs need power.
  - **What it adds here:** a centre LED ring behind the hub is a cheap backlight that needs none of the claimed WS2812 strip. Spring drive suits a short show, not a decoration running all day for ten days.
- **Fourth reference: [Pinterest pin, "even simpler"](https://pin.it/6jDzqwmMv)** (user, 2026-11-17; the user sent a screenshot since Pinterest only gave the title, an ENGI 210 student mechanism model). Laser-cut plywood:
  - **The rear spiral disc has an internal (ring) gear** cut around its hub, ~40 teeth.
  - **A sun gear** (~20T) sits at the centre on the axle; **one small idler** (~10T) on a fixed pin meshes between them.
  - **Three flat gears, all in one plane**: sun and ring turn in opposite directions. This is very likely the reel's "two shafts, three gears" too.
- **Fifth reference: wall-mounted belt-driven piece** (user's photo, 2026-11-17, source not given; the user calls it the simplest found so far):
  - **No gears.** A motor on an aluminium rail at the bottom drives, through a shaft coupling, a short shaft with two small pulleys.
  - **Two clear round belts** (polyurethane) run up to the disc hubs, one to a pulley in front of the front disc, one to the rear disc's hub. Each belt takes a quarter twist, since the drive shaft lies parallel to the wall.
  - **Opposite directions come from routing**: one belt wraps its hub the mirror way (crossed) to the other. The photo does not show which side each strand enters, so that detail is inferred.
  - **Speed reduction** comes from small drive pulleys and large hub pulleys.
- **What it is:** the counter-rotating spiral illusion. Two open spirals of opposite hand, one in front of the other, turning in opposite directions. The crossings appear to flow inwards or outwards, which reads as far faster motion than either disc has.

#### Feasibility
- **Yes, it is a known build.** Counter-rotation on one axis is a standard mechanism (the contra-rotating propeller / differential layout). Kinetic spiral wall pieces are a common laser-cut maker project:
  - [Printables: kinetic sculpture, contra-rotating discs](https://www.printables.com/model/120260-kinetic-sculpture-contra-rotating-discs) - an angled (bevel) gear gives both rotations; 3D-printed (page blocks automated fetch, so this is from search snippets)
  - [Instructables: Kinetic Sculpture V1](https://instructables.com/Kinetic-Sculpture-V1) - a laser-cut spiral wheel on a geared DC motor, wall-mounted (one wheel only)
  - [Pololu: ORBIS](https://pololu.com/blog/357/orbis-wooden-kinetic-and-lighting-sculpture) - laser-cut plywood, two rings with their own speed and direction
- **The hard part is mechanical, not electrical.** One slow motor, one DC adapter, no firmware needed.

#### User's build plan (2026-11-11)
- **Bearings:** reuse the ones from the golden-snitch fidget spinners already owned. Disc 2 sits on a bearing around the axle; disc 1 is fixed to the axle.
- **Gears:** an assorted plastic gear kit from Amazon (~₹200-300) supplies the reversing gears, replacing the laser-cut MDF gears of option B.
- **Motor:** drives the first wheel directly (motor shaft = axle, or coupled to it). Try a motor already owned first; if it is too fast, buy a slower one, later reused in a toy car for Ojaswi.

| Way to reverse disc 2 with kit gears | Gears | Fixed pins | Notes |
|---|---|---|---|
| **Bevel/crown** (option A, matches the reel's "three gears") | 3: one on the axle (disc 1), one on disc 2's bearing hub, a pinion between them | 1, radial, between the discs | Needs a matching crown/bevel pair in the kit; equal speeds automatically; the pinion's support arm sits in the disc gap |
| **Spur only:** axle gear → idler → layshaft gear; second layshaft gear → hub gear on disc 2 | 4 + idler | 2 (idler pin, layshaft) | Works with any flat gears; all of it behind the rear disc; equal speeds if both layshaft ratios match |
| **Internal ring gear** (4th reference, simplest): sun on the axle (disc 1), ring gear cut into disc 2's hub, one idler on a fixed pin between them | 3, all flat, one plane | 1 | Gear kits rarely have a ring gear this size, so cut the ring into the disc (laser shop, or card for a test). Ring turns slower than the sun (ratio = sun teeth / ring teeth, e.g. 20/40 = half): fine for the illusion |

- **Trap: speed vs the toy car.** Direct drive needs a 3-10 RPM motor, which is far too slow for a car. A typical toy-car motor (yellow TT gearmotor, ~100-200 RPM) suits the car but needs ~20-40x reduction here. A **kit worm + worm wheel** gives that in one stage (single-start worm: ratio = wheel's tooth count), so one TT motor can serve both - but then the motor is not on the axle directly.
- **Trap: bore mismatch.** Kit gears have 2-3mm bores; the spinner bearing likely wants an 8mm axle. Glue gears to the disc face / a hub disc, or drill them out; don't count on press fits.
- **Trap: spinner bearings are made to free-spin**, with little or no grease. Fine at this speed, but a wobbly disc on one narrow bearing tilts - use two bearings spaced apart on disc 2's hub if it rocks.

#### Mechanism options

| | A. Bevel differential | B. Concentric shafts + spur gears with an idler (recommended) | C. Two motors, no gears |
|---|---|---|---|
| **How** | A pinion between two facing bevel gears; each bevel drives one disc, so they turn equal and opposite | Front disc on a solid rod, rear disc on a tube over it. One motor pinion drives gear A on the rod directly and gear B on the tube through an idler, so A and B turn opposite | Rear disc driven from behind; a second motor sits at the centre on a fixed tube, under a stationary medallion, and drives the front disc |
| **Parts** | 3 bevel gears, rod, tube, bearings, 1 motor | 4 flat spur gears, rod, tube, 2 bearings, 1 motor | 2 motors, fixed tube, bearing, 1 gear pair for the rear disc |
| **Build difficulty** | Hard to source: bevels cannot be laser-cut, and loose nylon bevels in India are imported (one listing ₹5,100 for a single gear, [cart2india](https://cart2india.com/bevel-gears/cylindrical-drive-1pcs-15m-30t-plastic-bevel-gear-15-module-30-teeth-conical-bevel-pinion-90-degree-miter-gear-1-to-1-transmission-rack-machinery10mm-bore/00000000004391728783)). Easy *if* a 3D printer is available | Medium: every gear is flat and cuts from the same MDF sheet as the discs. Alignment of two gear planes is the work | Easy mechanically, but front-motor weight sits cantilevered at the centre and its wires run down the fixed tube |
| **Noise** | Quiet at disc speed | Quiet at 3-10 RPM; MDF teeth tick slightly | Quietest (no gear train in front) |
| **Behind a decoration** | Bevels sit between or behind the discs; a fatter stack | All gears behind the backboard; only the hub shows | Needs a centre cap/medallion that does not turn (could be an Om or a modak) |
| **Speed locked?** | Yes, exactly equal | Yes, exactly equal | No: two cheap motors differ by ~10%, so the pattern drifts. Harmless to the look |

option D: single motor pully with 90 degree opposite drive 
reference https://youtu.be/C2TBQVUtv18

- **Simplest found (2026-11-17, user): two round belts, the 5th reference.** No gears at all:
  - **Parts:** one drive shaft with two small pulleys, two round belts (polyurethane round belt, or O-rings / rubber bands for the card test), a pulley groove on each disc hub. Pulleys can be spools, bottle caps or turned MDF.
  - **Reversal:** cross one belt (figure-8) or wrap it the mirror way, so its disc turns opposite. Equal pulley sizes give equal speeds.
  - **Fits the build plan:** front disc fixed on the axle, rear disc on a spinner bearing around it, each with its own pulley.
  - **Belts slip if something jams**, which is safer near kids and flowers than a gear train.
  - **Trap: reduction is limited.** A hub pulley 5-10x the drive pulley still leaves a 100-200 RPM toy-car motor at 10-40 RPM, too fast. Use a slow motor, or a worm stage before the belts.
  - **Trap: belts are in view.** The reference uses clear belts; or take the front disc's axle through to a pulley behind the rear disc, so both belts run behind.
  - **Trap: belt tension.** Too tight loads the spinner bearing sideways and tilts the disc; mount the motor rail so it can slide to set tension.
- **Gear alternative: the internal ring gear from the 4th reference.** Three flat gears in one plane, one fixed pin, nothing between the discs, no layshaft:
  - **Motor on the idler pin is an option:** driving the idler turns sun and ring opposite at once, so the motor sits off-axis and the axle only carries discs.
  - **Speeds are unequal** (ring = sun x sun teeth / ring teeth). The pattern still flows; pick the ratio by eye in the bench test.
  - **Disc 2 must stay centred:** a hub plate behind the ring riding on a spinner bearing around the axle, or the ring held by two or three rollers.
  - **Card test first:** sun, idler and ring are easy to print on paper and cut from thick card before paying for any cutting.
- **Previously recommended: B.** It is the only option where every special part comes off one laser-cut sheet, with the rest from a hardware shop. Equal tooth counts on A and B give equal and opposite speeds. Making A and B larger than the pinion slows the discs and multiplies torque: a 15T pinion on 45T gears turns a 10 RPM motor into 3.3 RPM.
- **A only if** - there is no 3D printer (user, 2026-11-07), so printed bevels are out - the flat2form reel shows hand-made gears that hold up. The Printables model is exactly this, and the reel's "three gears, two shafts" caption most likely is too. If watching it confirms paper or card bevel/crown gears driven by one motor, A becomes the recommendation and the sourcing objection goes away.
- **The reel also points to a cheaper build: cardstock instead of MDF.** A paper chakra is light enough for a small motor, needs no laser shop and is immune to the MDF warp trap, but not to humidity (paper softens in monsoon). It is a smaller, more fragile piece than a 50cm MDF backdrop.
- **C is the fallback** if the gear train will not run smoothly.
- **Rejected: friction drive.** A rubber wheel squeezed between the two discs is the cheapest differential, but it needs a solid track on spiral discs that are mostly holes, and it slips as MDF swells.

#### Design notes and traps
- **Motor: 12V DC centre-shaft gearmotor, 5-10 RPM, not a mains synchronous motor.** The 50KTYZ-type 230V incubator motors used in rotating displays are cheap (₹350-515 at 2.5 RPM per [search listings](https://www.theengineerstore.in/hi/collections/all/products/50ktyz-220v-2-5r-min-2-5-turn-per-minute-6w-6-watt-permanent-magnetic-electric-gear-motor-50hz-incubator-motor), 2026-11-06), but rejected for two reasons:
  - **Exposed 230V terminals** behind a murti with flowers, water and diyas.
  - **They start in a random direction (CW/CCW).** In B that is harmless, since both discs reverse together. In C it is fatal: half the time the discs turn the same way.
- **Low voltage only near the murti.** The 12V adapter plugs in away from the makhar, and only the 12V lead runs to it. Keep diyas off the front of the discs: a turning disc fans a flame, and MDF burns.
- **Monsoon warps MDF.** Ganapati falls in humid weather. Seal both faces of 50cm discs (paint or lacquer), or use 6mm rather than 3-4mm, or cut acrylic. A warped disc rubs its neighbour.
- **Disc gap:** set by a spacer on the rod, about 5-10mm. Closer gives a sharper illusion; too close and any warp makes them touch.
- **Balance:** spirals are symmetric, so a clean cut balances. Low-torque motors (~3 kg-cm) stall on an off-centre heavy disc. A 50cm 4mm MDF disc that is ~60% cut away is roughly 0.3-0.4kg (estimate).
- **Plain bearing between tube and rod** is fine at this speed with grease. 608 bearings (8mm bore) hold the rod in the backboard.
- **Pinch points:** gears behind a backboard or cover, out of a child's reach. At 3-10 RPM with ~3 kg-cm the discs themselves are not a hazard.
- **Power cuts:** mains-only is fine for a decoration. It stops in a cut and restarts when mains returns, with nothing to recover.
- **Backlighting (optional):** a spiral lit from behind with WS2812 is far stronger than bare MDF. But every pixel of the leftover strip is claimed by the Diwali door outline (`docs/hardware.md`, Parts on hand), so check that before counting on it.

#### Home Assistant (optional, not the core)
- **Cheapest: on/off by a smart plug, timed to the aarti.** The 12V adapter goes into a switched socket, and HA schedules it like the 2026 aarti lights (08:00-09:30, 17:45-23:00).
  - **Which plug is open.** The in-house kandil switch (`switch.smart_switch_bench_relay`) is already claimed after Diwali by "Charge-limit the baby monitor iPhone SE with the smart plug". It would need a second relay box from "In-wall smart switch (Tinxy replacement, phase 2)", or a Tinxy socket (cloud-dependent, works only with internet).
- **Speed control:** ESP32 + logic-level MOSFET PWM in ESPHome, speed as an HA number. Only worth it if the bench test shows one speed is wrong for both day and night. Every spare ESP32 is currently claimed (Diwali lights, smart-switch bench), so price one in if this is wanted.
- **If it gets an ESP32, it is a device:** add it to `docs/hardware.md`, the Home dashboard in a room the user names, and `endpoints.toml`.

#### Readymade alternatives
- **LED "chakra" backdrops** sold for Ganpati murtis give a spiral of motion with no mechanics: e.g. 128 LEDs, mains plug-in, ₹999 ([chronoslights](https://chronoslights.com/products/ganpati-chakra-led-decoration-light-multi-color-220v), 2026-11-06). Cheaper than the DIY build and zero effort, but it is a light show, not the physical counter-rotating illusion.
- **No readymade counter-rotating spiral piece was found for sale in India.** Kinetic spirals sold abroad are import-only. Buying one is not a real option, and DIY is.

#### Overlap with other entries
- **"Ganapati 2027: solar system / general relativity decoration"** is a separate, not-yet-researched idea for the same festival. Not combined with this one; which one gets built is decided mid-2027.
- **"Sound-reactive aarti lights (Ganapati decoration)"** is the precedent for schedule, HA scripts and lighting behind the makhar.

#### Parts
Option B (recommended). Laser cutting is an estimate from [IndiaMART per-sq-ft rates](https://m.indiamart.com/sigma-enterprisespune) (₹120-450/sq ft, 2026-11-06). Get a quote for the actual SVG.

```parts
qty | item | est | note
1 | 12V DC centre-shaft geared motor, 5-10 RPM, 6mm D shaft | 150-250 | local electronics shop; search listings 2026-11-06: Robodo 10 RPM ₹150, Robocraze 6 RPM ₹217
1 | 12V 1A DC adapter | 150-250 | local; skip if a spare 12V brick is in a drawer
1 | DC barrel jack + inline switch | 30-60 | local
1 | laser cutting: 2 spiral discs ~50cm, 4 spur gears, motor plate, 4-6mm MDF | 600-1500 | estimate; local MDF/makhar laser shop, order by 2027-07 (they are busiest before Ganapati)
1 | 8mm steel rod, ~30cm (inner shaft) | 50-100 | local hardware
1 | tube 10mm OD / 8mm ID, ~15cm (outer shaft) | 80-200 | local hardware; take the rod along and check it turns freely inside
2 | 608 bearings | 60-120 | local bearing/hardware shop
1 | M8 shaft collars, nuts, washers | 50-100 | local hardware
1 | 12mm ply/MDF backboard | 200-400 | local; skip if the makhar has a rigid back
1 | paint/sealer for both disc faces | 200-400 | local; needed against monsoon warp
```

**Cost: about ₹1,600-3,400 for option B.** A cardstock build per the flat2form reel is cheaper: the motor, adapter and craft supplies, roughly ₹500-1,000 (estimate). Option C swaps the gears and idler for a second motor, a fixed tube and a centre medallion, at roughly the same total. The ₹999 LED chakra is the cheaper alternative if the physical illusion is not the point.

#### Effort
About 11-18h, cheapest and most decisive first:

| Phase | Hours | Notes |
|---|---|---|
| Bench test: motor + cardboard spirals | 1-2 | Decides speed, direction feel and disc size before any money goes on cutting |
| SVG design: spirals, gears, motor plate | 2-3 | Claude can generate it; the gear centre distances must be exact |
| Laser-cut order and pickup | 1-2 | Long lead in July-August |
| Assembly: shafts, bearings, gear planes, disc gap, wobble | 5-8 | **This is the phase that overruns**, as alignment work always has on this repo |
| Finish, seal, mount on the makhar, week-long run | 2-3 | |
| Optional HA schedule on a smart plug | 0.5 | Only if a switched socket is free |

#### Log
- 2026-11-06: idea recorded (user), Backlog. Pin opened as a still frame only. Researched: option B recommended; mains synchronous motors and imported bevel gears rejected; overlap with the solar-system entry noted.
- 2026-11-07: user sent the flat2form reel as the mechanism reference. Only the cover and caption could be fetched: a paper Ganesh chakra, one motor, two shafts, three gears. That count fits the bevel layout (A); kept B as the recommendation until someone watches the video.
- 2026-11-07: no 3D printer (user). Both 2027 ideas stay candidates and more may be added; final pick deferred to mid-2027, close to the festival.
- 2026-11-11: user's build plan: golden-snitch spinner bearings, an assorted plastic gear kit (~₹200-300) for the reversal, motor direct on the first wheel; try an owned motor first, else buy one to reuse in a toy car for Ojaswi. Noted the slow-motor vs car-speed conflict (worm gear fixes it) and the gear-bore mismatch.
- 2026-11-17: user sent a third reference (Instructables spring-driven kinetic sculpture, optional RGB ring). Steps not readable; recorded as a backlight idea, spring drive not adopted.
- 2026-11-17: user sent a fourth reference (Pinterest, "even simpler"); only the title was readable (an ENGI 210 student mechanism model), so the mechanism is not recorded yet.
- 2026-11-17: user's screenshot of the 4th reference shows an internal ring gear in the rear disc, a sun on the axle and one idler: three flat gears in one plane. Made it the recommendation over B.
- 2026-11-17: user: this entry is only the counter-spinning wheels; the solar-system idea is separate and not researched. Dropped the "discs as orbit rings" combination.
- 2026-11-17: user's photo of a belt-driven wall piece (two round belts from one motor shaft, one routed the mirror way). User: simplest mechanism found so far. Made it the lead option; ring gear kept as the gear alternative.
