# Fibre or Cat6 from the router to the desk
**Status:** Closed

**Why:** a real cable from the Airtel router to xero's desk replaces the extender's 2.4GHz Wi-Fi hop. It also keeps xero, its speaker and its screen where they are.
**Outcome:** closed 2026-10-17, not needed: xero moved to the router instead (cabled into it, on its UPS; "Pi audio move follow-ups", step 3). Nothing was bought or pulled. The notes below stay for reference if xero ever has to go back to the desk.

#### The route
An existing conduit that already carries 230V mains wiring and has many bends.

#### The two options (full detail in `docs/home-network-uplink-options.md`)
- **Fibre with a BiDi media converter pair,** ~₹3,500-6,500:
  - pull bare G.657A2 fibre, then have an FTTH technician fit SC plugs
  - no electrical path, no surge path, an easier pull
  - with the xero-side converter on plain mains, `watchdog_power.sh` keeps working unchanged
- **Cat6,** ~₹1,500-3,000:
  - works fine in practice
  - realistic worst case is a network port killed by a surge (add an Ethernet surge protector)
  - the power watchdog needs the ping change
  - shielded Cat6 is ruled out

#### Unlocks
- per-device data-usage monitoring with xero as the gateway (an OpenWrt router with nlbwmon remains the better way)
- faster and more reliable Immich, backups and Tailscale access

#### Log
- 2026-09-23: parked.
- 2026-10-17: closed - xero moved to the router instead.
