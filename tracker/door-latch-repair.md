# Door latch that sticks inside its housing after springing back
**Status:** Backlog
**Priority:** P3
**Cost:** ₹100-1,500
**Effort:** ~1 evening (1-3h)

#### Open items
- [ ] **Pramod:** with the door **open**, pull the handle and let go 10 times - does the bolt stick there too, or only when the door is shut? This one test picks the branch below
- [ ] **Pramod:** note which door, and send a photo of the bolt, faceplate and strike plate (the plate on the frame)
- [ ] **Pramod:** note the lock type: mortise (rectangular box inside the door edge, lever handles) or tubular/cylindrical (round bore through the door, knob or lever), and the brand if stamped on the faceplate
- [ ] **Pramod:** say which hand tools are already at home (screwdrivers, flat file, chisel, drill) - none are recorded in `docs/hardware.md`
- [ ] **Pramod:** buy the parts the diagnosis calls for, at the local hardware shop (only the replacement latch needs the old one taken in to match)

**Why:** the door's latch bolt is pulled back by the handle and springs out again, but on the way out it catches in the housing because the cut-out is misaligned, so the door does not latch reliably (user, 2026-11-26). Purely mechanical: no electronics, no code.
**State:** idea only. Which door, which lock type and which part is misaligned are not known yet (Open items above).

#### Feasibility
**Yes, a routine fix.** Most cases are solved by tightening hinge screws, lubricating, filing a cut-out or moving the strike plate; replacing the latch is the fallback and is cheap. A locksmith is only worth calling if the latch body itself is broken inside.
- [Bob Vila - 4 fixes for a door that won't latch](https://www.bobvila.com/articles/door-wont-latch/) - long screw into the top hinge lifts a sagging door, bottom hinge pulls it down
- [This Old House - lipstick trick for aligning hardware](https://www.thisoldhouse.com/doors/lipstick-trick-for-aligning-hardware)
- [Family Handyman - adjusting a door strike plate](https://www.familyhandyman.com/project/adjusting-a-door-strike-plate/) - file small offsets; past ~3mm (1/8") move the plate
- [iFixit - fix the hole for a misaligned door latch](https://www.ifixit.com/Guide/How+to+Fix+The+Hole+For+a+Misaligned+Door+Latch/172443)

#### Overlap
- **[`door-status.md`](door-status.md)** plans a bolt sensor inside the keeper of the main and safety doors. If this latch is on one of those doors, fix the alignment **first**: a bolt that does not throw fully would read "unlocked" for ever, and that entry already asks for the strike plates to come off - do both in one go.

#### Which part is at fault - the first fork
The user's words, "gets stuck inside housing", fit two different faults. The door-open test in Open items separates them:

| Bolt sticks... | Fault is in | Hinges / strike matter? |
|---|---|---|
| **with the door open** too | the lock itself: latch body crooked in its bore/mortise, bent faceplate, faceplate cut-out off-centre, dirt or dried grease, weak spring | no - skip to the lock-side fixes |
| **only when the door is shut** | the frame side: door sag, loose hinge screws, strike plate cut-out misaligned with the bolt | yes |

#### Likely causes
| Cause | Tell-tale |
|---|---|
| Loose hinge screws / door sag | top of the door rubs the frame on the latch side; gap above the door is uneven; the top hinge screws turn freely |
| Strike plate misaligned | bolt catches on the edge of the plate's hole; lipstick mark sits above, below or beside the hole |
| Latch body not square in its bore or mortise | faceplate not flush with the door edge, or its screws loose; bolt sits off-centre in the faceplate cut-out |
| Bent faceplate | faceplate bowed or dented where the bolt slides through; bolt scrapes one side of the cut-out |
| Dirty or dried mechanism | bolt is slow or gritty even out of the door; old oil has turned to paste |
| Weak or broken spring | bolt returns slowly or not at all even when clean and square |

#### Diagnosis, step by step
1. **Door-open test** (Open items): sticks with the door open = lock side; only when shut = frame side.
2. **Look at the faceplate** on the door edge: flush and screws tight? Bolt centred in its cut-out? Shine a torch along the bolt for scrape marks on one side.
3. **Hinge screws:** try every screw on all hinges, frame side and door side. Any that spins without tightening has a stripped hole.
4. **Gap check:** the gap between door and frame should be even top to bottom on the latch side and across the top. A wider gap at the top of the latch side means the door has sagged.
5. **Lipstick or marker test** (frame-side fault only): rub lipstick, chalk or whiteboard marker on the bolt's tip, close the door gently onto the strike, open it, and see where the mark lands relative to the strike's hole. Masking tape on the strike plate shows it better on a dark plate.
6. **Bench test the latch** (lock-side fault that survives cleaning): take it out (faceplate screws, then the handle spindle), work the bolt by hand. Sticks out of the door = worn or broken inside, replace it. Smooth out of the door = it was being squeezed in the bore; enlarge the bore or mortise.

#### Fixes, in order of effort
| # | Fix | When | Time |
|---|---|---|---|
| 1 | **Tighten hinge and faceplate screws** | any screw loose | 5 min |
| 2 | **Longer hinge screw into the frame** (2.5-3 inch, one per hinge, through the hinge's inner hole into the stud/wall plug) | stripped hole, or door has sagged; top hinge lifts the latch side up, bottom hinge pulls it down | 20 min |
| 3 | **Clean and lubricate with a dry lubricant** - graphite powder or a dry PTFE spray, puffed into the bolt and latch body. Wipe old grease off first. **Not oil or general WD-40**: they collect dust and are what gums a latch up | slow or gritty bolt | 15 min |
| 4 | **Straighten or re-seat the faceplate**: tap a bent plate flat on a hard surface; re-seat a crooked latch so it is square to the door edge | faceplate bent, latch tilted | 30 min |
| 5 | **File the cut-out** - the faceplate's or the strike plate's, whichever the bolt catches. Small strokes, test after each. Fine for ~3mm or less | small offset | 30 min |
| 6 | **Move the strike plate** - unscrew, extend the wood mortise behind it with a chisel, re-fix with new screw positions; fill the old holes with matchsticks and glue | offset over ~3mm | 1-2h |
| 7 | **Replace the latch** - take the old one to the shop and match backset (centre of spindle to door edge, commonly 45mm or 60mm on mortise latches here), faceplate size and spindle size | bolt sticks out of the door, broken spring, cracked body | 1h |

- **Trap - the spring is rarely the cause** on its own: a spring weak enough to fail usually does so everywhere, not only where the cut-out binds. Do fixes 1-5 before blaming it.
- **Trap - do not file the bolt itself.** It shortens the throw and weakens it, and on a mortise lock it may leave the latch body to be replaced anyway.
- **Trap - sag comes back** if the screws only bite the old stripped holes: the long screw has to reach solid frame.

#### Tools
| Tool | For | Needed for fixes |
|---|---|---|
| Phillips and flat screwdrivers (medium and large) | hinge, faceplate, strike screws | all |
| Torch | seeing scrape marks in the cut-out | diagnosis |
| Lipstick, chalk or marker; masking tape | the strike test | diagnosis |
| Flat file and half-round or round needle file | enlarging a cut-out | 5, 6 |
| Wood chisel (12-18mm) and hammer | extending the strike mortise | 6 |
| Drill with a small bit (2-3mm) | pilot holes for the long hinge screws and the moved strike | 2, 6 |
| Old toothbrush, cloth | cleaning the mechanism | 3 |

Which of these are at home is not recorded (Open items).

#### Readymade alternatives
- **A local carpenter or locksmith** does fixes 1-6 in one visit, typically a few hundred rupees in labour (estimate, not quoted). Worth it if the strike needs moving and there is no chisel at home; otherwise the DIY path costs less than the visit.
- **Replacement latch** (fix 7) is the "buy it" option, and cheap enough that a badly worn latch should just be swapped rather than coaxed.

#### Parts
```parts
qty | item | est | note
1 | Graphite powder, puffer bottle | 50-150 | local hardware shop. Estimate. Dry lube: oil and general-purpose WD-40 attract dust and gum the latch
4 | Wood screws, 2.5-3 inch (65-75mm), steel, Phillips, head matching the hinge countersink | 30-80 | local, loose. Estimate. One per hinge into the frame, plus spares; skip if the hinge screws all hold
1 | Flat file (8 inch) | 150-300 | local. Estimate. Skip if one is at home; only for fixes 5-6
# Optional: dry PTFE spray instead of graphite
1 | Dry PTFE lubricant spray (e.g. WD-40 Specialist Dry Lube, ~400ml) | 400-700 | local hardware or auto shop, else online. Estimate - no Indian listing found 2026-11-26; overseas price ~£8/250ml. Cleaner than graphite, worth it only if the can will get other uses
# Option: replacement mortise latch
1 | Mortise latch body (keyless/baby latch), matching backset 45 or 60mm | 450-900 | local; take the old one along. Indiamart listings 2026-11-26: Godrej keyless latch 45mm ~₹473, 60mm ~₹850. Only if the bench test says it is worn
# Option: replacement tubular latch
1 | Tubular latch, matching backset (60 or 70mm) and bore | 300-700 | local; take the old one along. Estimate. Only if the bench test says it is worn
```

#### Cost detail
- **₹100-150** - the likely case: graphite and a few long hinge screws, tools at home.
- **₹250-450** - add a flat file.
- **Up to ~₹1,500** - the header ceiling: lube, screws, file and a replacement mortise latch, or the PTFE spray instead of graphite.
- **₹0** if the fault turns out to be a loose screw or a bent faceplate.

#### Effort detail
| Phase | Hours | Notes |
|---|---|---|
| Diagnosis (door-open test, screws, gap, lipstick) | 0.25-0.5 | decides everything after it |
| Tighten / long hinge screw / clean and lubricate | 0.5 | solves most cases |
| File a cut-out or straighten the faceplate | 0.5 | |
| Move the strike plate, or swap the latch | 1-2 | **the one that overruns**: chiselling the mortise to the right depth and re-drilling screw holes that wander into the old ones is the alignment work, same as every mechanical job in this repo |

#### Rejected
- **Oil or general-purpose WD-40 as the lubricant** - short-lived, attracts dust, and is the usual reason an old latch goes sticky.
- **Filing the bolt** - shortens the throw; see traps.
- **A smart lock while it is apart** - already considered and rejected in [`door-status.md`](door-status.md) (read-only sensing preferred; Tinxy cloud concerns).

#### Log
- 2026-11-26: entry created from the user's one-line description. Door, lock type and faulty part still to be identified.
