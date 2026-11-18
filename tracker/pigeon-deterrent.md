# Pigeon deterrent - motion-triggered sprinkler (balcony railing/parapet)
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** revisit once the balcony water supply (see plant watering) and the runoff question are settled

**Why:** pigeons roost on the balcony railing/parapet. Original idea was image recognition + sprinkler.
**State:** not started. Plan is the dumb version first - a PIR sensor and a valve, no image recognition. Nothing planned: gated on the same balcony water supply as the watering project, and on the runoff question.

#### Notes
- **Image recognition ruled out on `xero`** - Celeron N5105, no GPU, 8GB RAM with Immich's ML already disabled for exactly this reason, and a history of memory-pressure lockups. Continuous object detection there would put the whole homelab at risk. Real CV would need dedicated hardware (Pi 5 + Hailo hat, or a Coral TPU), roughly a Rs 15-25k project - not a weekend build.
- **The CV is probably unnecessary anyway** - commercial motion-activated sprinklers (e.g. Orbit Yard Enforcer) are just a PIR sensor and a valve, no detection at all. Outdoor PIR does false-trigger on heat and moving shadows, but the cost of a false positive here is a cup of water. Build the dumb version first and only escalate to detection if it genuinely does not work.
- **Shares the watering project's blocker** - a sprinkler on the balcony needs water at the balcony, the same wall/pipe run described above. If that ever gets solved, both projects unlock together.
- **Two real-world constraints to settle before buying anything:** (1) **runoff** - the railing/parapet is an open edge, so spray falls onto whatever or whoever is below; worth confirming that is acceptable first, since it is the kind of thing that kills a project after it is built. (2) **habituation** - pigeons adapt fast to anything predictable, so randomise spray timing and duration rather than firing a fixed pattern.

#### Log
- 2026-09-04: noted.
