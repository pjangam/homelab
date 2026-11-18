# Home power audit - smart/network devices + major appliances
**Status:** Active
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** decide whether real numbers matter; if so, buy a cheap plug-in energy meter
- [ ] **Claude:** check whether the Tinxy integration exposes energy data for the loads behind the two Tinxy units
- [ ] **Together:** measure the fridge first (likely the biggest load), then replace the router/extender/xero/Pi estimates

**Why:** triggered by a tangent while discussing whether a new WiFi button (Shelly) would raise the electricity bill - user wants to know the actual continuous background draw of always-on smart/network gear versus the usage-driven draw of major appliances, to know where money is actually going.
**State:** first pass done (2026-08-22), estimated from specs/datasheets (no plug meter available - see caveat below). Always-on stack estimated at **~30W continuous**, roughly ₹130-175/month; the fridge is likely larger than all of it but was not measured.

#### Hardware confirmed
Confirmed real hardware details for two of the "always-on" devices by querying them directly:
- `xero` is a Beelink mini PC, Celeron N5105 (10W TDP), 2x SSD (Kingston SA400 960GB + Biwin 128GB boot), no spinning disk.
- The wol-sender Pi is a **Raspberry Pi 3 Model B Rev 1.2** (not 4 or Zero as assumed) with a GPIO-wired fan as extra continuous load, and `vcgencmd get_throttled` shows a sticky historical under-voltage flag consistent with the known wall-mount power-cable issue tracked elsewhere (not current-state undervoltage).

#### Always-on draw estimate
Estimated always-on draw (rounded, spec-based):
| Device | Est. watts (continuous) | Basis |
|---|---|---|
| Airtel router | ~8W | general router range (5-20W), no exact model datasheet found |
| TP-Link WiFi extender | ~4W | TP-Link range-extender models measured 3-4.8W |
| xero (Beelink N5105, 2 SSD) | ~12W | N5105 mini PCs commonly idle 10-14W depending on PSU/RAM config |
| wol-sender Pi 3B + fan | ~2.5W | Pi 3B measured idle ~1.2-2W; GPIO fan adds continuous draw on top |
| Tinxy 4-node switch x2 (self-consumption only, not switched load) | ~2W each (~4W total) | no official datasheet number found; general WiFi relay module self-consumption is ~0.5-1.5W per relay, shared control board per unit |
| **Total** | **~30W continuous** | → ~21.6 kWh/month → roughly ₹130-175/month at typical India residential rates (₹6-8/kWh) |

#### Major appliances
Fridge is the only major appliance with a comparable continuous-ish profile (compressor duty-cycling): a typical double-door fridge averages ~60-90W day-long, a 5-star inverter model less (~30-50W) - likely **larger than the entire smart/network stack combined**, but wasn't measured here. Washing machine, dishwasher, and microwave standby draw is negligible (~1-3W each when idle); their real cost is almost entirely usage-frequency driven (cycles/week, not standby watts) and wasn't estimated - needs the user's actual usage pattern to be worth calculating.

#### Caveat
All "always-on" numbers above are spec/datasheet estimates, not measured - could realistically be off ±30-40% per device without a real inline meter. Good enough to rank contributors and sanity-check "does this add to my bill" questions (context: prompted by the Shelly WiFi-button power question), not precise enough to reconcile against an actual bill.

#### Parts
```parts
qty | item | est | note
1 | Plug-in energy meter (socket type, kWh + live watts) | | local - only if real numbers are wanted (see Open items); fridge first
```

#### Log
- 2026-08-22: first pass done, estimated from specs/datasheets.
