# Door rim lock whose spring latch sticks on the way out
**Status:** Active
**Priority:** P3
**Cost:** ₹100-1,700
**Effort:** ~1 evening (1-3h)

#### Open items
- [ ] **Pramod:** play test: hold the lock body firmly against the door and wiggle the latch - does the wobble go away? Are the back-cover screws tight? This picks the branch below
- [ ] **Pramod:** check what the copper-coloured piece inside the bottom opening is (old shim, or the edge of the latch)
- [ ] **Pramod:** note which door this is
- [ ] **Pramod:** if the play test says the lock is sound, file where the latch catches, clean and puff in graphite; otherwise buy a matching rim lock at the local shop (take the old one along) and swap it
- [ ] **Pramod:** if a new spot starts catching after the filing, replace the lock rather than file again

**Why:** the door's spring latch sticks as it springs back out, so the door does not latch reliably (user, 2026-11-26). Purely mechanical: no electronics, no code.
**State:** diagnosed from the user's photos, 2026-11-26; repair started. The lock type is known (surface rim lock), the faulty part is known (the bevelled spring latch in the bottom forend opening), and the likely root cause is vertical play in the latch. Not yet known: where the play comes from (Open items), which door it is.

#### What the photos show (2026-11-26)
| Part | Seen |
|---|---|
| **Lock type** | **Surface-mounted box lock (rim lock / night latch)**: body screwed onto the inside face of the door, L-shaped forend plate wrapping the door edge, slotted screws, knob on the inside face. Not a mortise or tubular latch |
| **Top forend opening** | flat rectangular deadbolt - looks fine |
| **Bottom forend opening** | bevelled **spring latch** - the one that sticks |
| **Bottom opening's edges** | curved bulges and dents on the top and bottom edges, likely worn in by the latch hitting them; crust of rust and paint plus an inward lip on the bottom edge |
| **Latch, door open** | comes out **tilted** |
| **Inside the opening** | something copper-coloured; unconfirmed whether an old shim or the latch's edge (Open items) |
| **Around the lock** | rust and paint drips - moisture is likely |
| **Latch play (user's finding)** | **lots of vertical wobble.** A fraction of a millimetre is normal; clearly visible wobble lets the latch tilt, come out at an angle and catch the edges of the opening |

- **Root cause, probably:** the vertical play. The deformed edges are the result, not the cause.
- **Ruled out:** strike plate, hinges and door sag. It sticks with the door open, so the frame side is not involved.

#### Feasibility
**Yes, a routine fix.** Either tighten what is loose and dress the opening, or swap the whole rim lock for a same-size one into the same screw holes - both are hand-tool jobs. A locksmith is not needed.

#### The plan
1. **Find where the play comes from (2 min).**
   - Hold the lock body firmly against the door and wiggle the latch.
   - **Wobble goes away** - the body is loose on the door: tighten the mounting screws; if the holes are worn, use slightly thicker or longer screws.
   - **Latch still wobbles** - check and tighten the **back-cover screws** of the lock body; a lifted cover gives the latch room to move.
   - **Everything tight, still wobbles** - the internal guide is worn: replace the lock.
2. **File only where the latch catches.**
   - Mark the latch's sides with pencil lead or marker, work the knob, and see which edge of the opening the mark rubs off onto. File only there, with a small flat needle file.
   - Hold the latch retracted while filing so it is not nicked. A few strokes, test, repeat.
   - Aim to straighten the bulges, rust and paint lip - **not widen the opening**, which adds rattle.
3. **Clean and lubricate.** Brush out filings, rust and paint flakes; puff in graphite powder.
4. **If it still sticks:** take the lock off (a few screws), open the back cover, check the latch guide and spring. Straighten a bent guide. Broken spring or heavy rust inside: replace the lock.

- **Trap - never file the latch itself.** It shortens the throw and the latch still tilts.
- **Trap - no oil or WD-40.** They collect dust and gum the latch; graphite only.
- **Trap - filing is treating the symptom.** It is fine once, to clean up edges the wobble has already deformed, but it does not remove the play.

#### If it comes back
- **Rule (user asked):** if a **new spot** starts catching after the filing, **stop filing**. The opening was never the real problem; the play is, and more filing only loosens it further. Go to the table below, and **replace the lock** if it comes back within a few months.

| Symptom | Cause | Fix |
|---|---|---|
| Lock body moves when pushed | loose or worn mounting screws | tighten; thicker or longer screws in worn holes |
| Latch tilts or wobbles | worn or bent internal guide | open the cover and straighten, or replace the lock |
| Latch returns slowly and weakly | tired or broken spring | replace the lock (usually simpler than finding a spring) |
| Fresh rust on the edges | moisture | keep it dry; graphite now and then |

#### Replacement
- **A same-size surface rim lock / night latch**, matched at the local hardware shop by taking the old one along.
- **Match:** body size, the forend (L-plate size and opening positions) and the **hand** (which way the door opens, inside or outside opening), so it goes into the same screw holes.
- **Prices found 2026-11-26** (online listings, for scale - the local shop is the baseline):
  - Godrej Outside Opening Super Night Latch 8813: ₹1,339 on [Moglix](https://www.moglix.com/godrej-outside-opening-super-night-latch-rim-lock-8813/mp/msn2vl2bair72f) (MRP ₹1,510)
  - Godrej 7-lever night latch, inside opening: ₹1,269 on [Flipkart](https://www.flipkart.com/godrej-7-lever-night-latch-inside-opening-lock/p/itmey7n4vy2rnggw) (sold out); outside opening ₹1,287-1,582 on [McCoy Mart](https://mccoymart.com/buy/godrej-night-latch-rim-lock-7-lever-night-latch-outside-opening-)
  - Godrej Night Latch 8812: ₹1,250 on [IndiaMART](https://m.indiamart.com/impcat/night-latch.html) (seller quote, GST may be extra)
  - **Link, Europa and unbranded rim locks:** no listing fetched; **estimate ₹400-900**.

#### Readymade alternatives
- **Swap the lock straight away** (₹400-1,600) instead of filing. Worth it if the play test says the guide is worn; otherwise the ₹100 repair is the better first try.
- **A local carpenter or locksmith** would do the same swap for a few hundred rupees in labour (estimate, not quoted) - not needed, it is a few screws.

#### Overlap
- **[`door-status.md`](door-status.md)** plans bolt sensing on the **main and safety doors**. It applies only if this is one of those doors (not yet known, Open items): then fix the latch first, since a latch that does not throw fully reads "unlocked" for ever, and a replacement rim lock changes what that entry's sensor would sit against. If it is any other door, there is no overlap.

#### Parts
```parts
qty | item | est | note
1 | Graphite powder, puffer bottle | 50-150 | local hardware shop. Estimate. Dry lube only - no oil or WD-40
1 | Needle file set (small flat file is the one used) | 100-250 | local hardware shop. Estimate. Skip if a small flat file is at home
4 | Wood screws, one size thicker or longer than the lock's mounting screws, slotted or Phillips | 20-50 | local, loose. Estimate. Only if the play test shows the body loose and the old holes worn; take an old screw along
# Option: replacement rim lock
1 | Surface rim lock / night latch, same body size, forend and hand as the old one | 400-1,600 | local hardware shop; take the old lock along. Godrej ~₹1,250-1,600 online 2026-11-26; Link/Europa/unbranded ₹400-900 estimate. Only if the play test or step 4 says the lock is worn
```

#### Cost detail
- **₹0** - if the fix is tightening the mounting or back-cover screws.
- **₹50-150** - the likely repair case: graphite, a file already at home.
- **₹170-450** - graphite, needle files and new mounting screws.
- **Up to ~₹1,700** - the header ceiling: graphite plus a Godrej replacement. A local unbranded lock keeps a replacement under ~₹1,000.

#### Effort detail
| Phase | Hours | Notes |
|---|---|---|
| Play test, tighten screws | 0.1-0.25 | decides everything after it |
| Mark, file, clean, graphite | 0.5-1 | **the one that overruns**: a few strokes at a time with tests between, and the urge to keep filing is exactly the trap above |
| Open the back cover, inspect guide and spring | 0.25-0.5 | only if it still sticks |
| Shop trip and swap the lock | 1-1.5 | only if worn; the swap itself is a few screws, the time is matching it at the shop |

#### Rejected
- **Strike plate, hinge and door-sag fixes** (lipstick test, moving the strike, long hinge screws) - the latch sticks with the door open, so the frame side is not the fault.
- **Mortise or tubular latch replacement** - the lock is a surface rim lock; those parts do not fit.
- **Oil or general-purpose WD-40** - short-lived, attracts dust, gums a latch.
- **Filing the latch, or widening the opening** - shortens the throw or adds rattle; the play is the cause.
- **A smart lock while it is apart** - already rejected in [`door-status.md`](door-status.md) (read-only sensing preferred; Tinxy cloud concerns).

#### Log
- 2026-11-26: entry created from the user's one-line description, assuming a mortise or tubular latch; that was wrong.
- 2026-11-26: the user's photos showed a **surface rim lock / night latch**. Diagnosis: vertical play in the bevelled spring latch lets it come out tilted and catch the bottom forend opening, whose edges are now deformed (bulges, rust and paint lip); it sticks with the door open, so strike, hinges and sag are ruled out. Plan: play test to find where the wobble comes from, tighten, file only where the latch catches, clean and graphite; replace the lock if the guide is worn or a new spot catches later. Status set to Active, the user has started.
