# Move the Airtel router to a central spot (retire the Wi-Fi extender)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** answer the open questions below (`docs/home-network-uplink-options.md` has all the options, costs and trade-offs)

**Why:** the router sits where Airtel's fibre drop enters the house, so the far rooms depend on the TP-Link extender. A central router could cover the house on its own. (It used to be about xero's link too; xero is cabled into the router since 2026-10-17, so that part is moot.)
**State:** parked, nothing done. **Needs outside help:** Airtel has to re-route its fibre drop, or it has to be extended inside the house, and they may charge.

#### Open questions
- Where is central, and does the fibre drop reach it?
- The router's UPS has to move with it.
- Does a central router reach xero's room well without the extender?

#### If it works
- The extender and its failure mode go away.
- `watchdog_power.sh` loses its outage signal, because the extender is what drops. Do the ping change first; see the notes.

#### Log
- 2026-09-23: parked.
