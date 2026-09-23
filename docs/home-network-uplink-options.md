# Home network: xero's uplink, per-device data usage, and cabling options

Notes from a 2026-09-23 discussion, parked so none of it has to be worked out
again. None of this is being done now: every option needs outside help (an
electrician, a fibre technician or Airtel), so it sits in the `PROJECTS.md`
backlog under "Move the Airtel router to a central spot" and "Fibre or Cat6
from the router to the desk". All prices are rough estimates for local shops.

## Where things stand

- **The router:** an Airtel fibre router (login page `http://192.168.1.1/admin/login.asp`)
  and the house's only internet gateway. It has its own UPS. It handles DHCP;
  Pi-hole only does DNS.
- **xero's link:** xero (`192.168.1.123`) is wired to the **TP-Link Wi-Fi extender**,
  and the extender reaches the router over **2.4GHz Wi-Fi**. Everything xero
  sends crosses that one wireless hop. The extender has no UPS.
- **The internet plan:** 40 Mbps today, maybe 100 Mbps later. Nothing faster
  is planned.

## 1. Seeing how much data each device uses

**The Airtel router can't do it.** It counts traffic per port and per band,
not per device, and Pi-hole sees DNS lookups, not bytes. To count bytes per
device, something has to sit in the path of all traffic.

| Option | Cost | Verdict |
|---|---|---|
| Make xero the gateway (IP forwarding + NAT on xero, ntopng or vnstat) | ₹0 | **Not while xero is on the extender:** every byte would cross the 2.4GHz hop twice, which is about the limit at 40 Mbps and too slow at 100. Even on a cable, xero becomes a single point of failure for the whole house's internet (a reboot, a Docker problem, the RAM question). It also needs Pi-hole to take over DHCP and IPv6 to be switched off on the LAN, or IPv6 traffic bypasses xero. |
| An OpenWrt router behind the Airtel box (Xiaomi AX3000T, TP-Link Archer C6 v3/AX23) running **nlbwmon** | ~₹2,500-4,000 | **The recommended way.** Per-device daily and monthly usage out of the box, xero stays out of the internet path, and Wi-Fi control improves. Best with the Airtel box in bridge mode (ask Airtel, and have the PPPoE credentials); it also works double-NAT behind it, as long as every device joins the new router's Wi-Fi. |
| A managed switch with port mirroring | - | **Doesn't work:** Wi-Fi devices talk to the Airtel box directly, so a switch never sees their traffic. |

**Extender caveat:** devices behind the TP-Link extender keep their own IP
addresses, so they still show up separately. Some extenders rewrite MAC
addresses, though, and a monitor that groups by MAC would then lump them
together.

## 2. Moving xero next to the router (a cable straight into it)

This would work: a gigabit cable makes xero-as-gateway workable. It is **not**
free, though:

- **It breaks the power-outage watchdog.** `projects/power-watchdog/watchdog_power.sh`
  detects a mains outage by `enp1s0` losing carrier, which happens only because
  the extender has no UPS. The router *has* a UPS, so the link would stay up in
  an outage, the watchdog would never fire, and xero would run its battery flat
  and lose power abruptly (the thing the watchdog exists to prevent).
  **The fix:** keep the carrier check and also start the timer when **both** the wol
  Pi (`192.168.1.124`, mains-only) **and** the extender stop answering pings for
  several checks in a row. Requiring both avoids false alarms from the Pi's
  flaky supply. The extender needs a pinned IP first.
- **The speaker moves with xero.** White noise and Spotify Connect play through
  xero's USB speaker. That is why they are being moved to the wol Pi: the
  active `PROJECTS.md` entry "Move white noise and spotifyd from xero to the
  wol Pi".
- **Local access:** the monitor, and ESP32 flashing over xero's USB. Minor.
- **Unaffected:** Pi-hole, HA, MQTT and Tailscale (same IP), WoL from the Pi
  (better, with no Wi-Fi hop; re-test it), and xero's Wi-Fi fallback profile
  (harmless; it just stops being needed).

## 3. A cable from the router to xero's desk instead

This keeps xero, its speaker and its screen where they are. The route is an
existing conduit that **already carries 230V mains wiring** and has **many
bends**.

### Fibre (media converters)

- **Parts:**
  - a gigabit **single-fibre BiDi (WDM) media converter pair**, A/B, with SC ports
    (~₹2,000-3,500 for the pair; or TP-Link MC220L plus BiDi SFP modules, ~₹6,000)
  - **bare single-mode G.657A2 fibre**, indoor or FTTH drop cable, route length
    plus ~3m (₹300-700)
- **Pulling it:**
  - **Pull the fibre bare, without plugs.** A pre-fitted plug snags at elbows,
    while bare ~3mm fibre goes wherever a fish tape goes. Drop cable has
    strength members, so it takes pulling force well.
  - Pull in stages through the junction boxes, use lubricant or talc, and
    switch the circuit off at the MCB while pulling.
  - **A local FTTH technician fits SC plugs afterwards,** with a splicer or
    quick-fit plugs (₹300-1,000). The Airtel/JioFiber installers do this daily,
    and often do the pull too, which saves a visit.
- **Bends are fine for the signal:** G.657A2 tolerates bends down to ~7.5mm
  radius, and the converters are built for ~20km. Only a sharp kink hurts it.
- **Power, and why it keeps the watchdog working:**
  - the router-side converter goes on the **router's UPS**
  - the xero-side converter goes on **plain mains, not xero's UPS**

  In an outage the xero-side converter dies, `enp1s0` loses carrier as it does
  today, and `watchdog_power.sh` needs **no change**.
- **Total: ~₹3,500-6,500.** About half a day of work over one or two visits.

### Cat6

- **Parts and labour:** cable ₹600-1,200, plugs or wall jacks ₹100-300 (any
  electrician can fit them after the pull), pull labour ₹500-1,500.
  **Total: ~₹1,500-3,000,** the cheaper option.
- **It works:** gigabit over 20-30m beside mains is very likely fine. The pairs
  are twisted to cancel noise, and 50Hz is millions of times below Ethernet's
  frequencies. Noise shows up as dropouts, not a slower link.
- **Shielded Cat6 (STP/FTP), as Gemini suggested, is not worth it.** The
  shield only works grounded at both ends, and the router and xero have plain
  plastic ports, so it would float and can act as an antenna. It does nothing
  for insulation or surges, and it is thicker and stiffer, which is worse for
  a conduit with many bends. Ruled out by the user.
- **Wiring rules:** IS 732 / IEC 60364 say data and mains cable should not
  share a conduit unless the data cable is rated for mains voltage (look for
  "300V" printed on the jacket).
- **Fire:** Cat6 carries milliwatts, so it can't overheat or start a fire (no
  PoE here). Its jacket adds a little fuel, about the same as the mains wires'
  own insulation.
- **A 230V leak onto the cable:** it needs three insulation layers to fail at
  one spot. Ethernet ports have 1,500V isolation transformers, so the realistic
  worst case is a **dead network port** on xero or the router, not a dead
  server. An RCCB or ELCB trips on such a fault (check the house has one).
- **Surges are the bigger practical risk:** lightning or switching spikes of
  thousands of volts, picked up over 20-30m beside mains, are how ports die in
  the monsoon. An earthed Ethernet surge protector at xero's end costs
  ~₹500-1,000.
- **The watchdog breaks,** as in section 2: both ends are on a UPS, so the
  link never drops in an outage. It needs the ping-based change.

### Risks that apply to either cable (the real fire risk)

- **Scraped insulation:** pulling any cable past old mains wires can scrape
  their insulation. Damaged mains insulation is the genuine fire and short
  risk. Thinner and more flexible is gentler: fibre is ~3mm, Cat6 ~6mm.
- **Crowding:** a crowded conduit makes the mains wires run hotter.

**Before buying anything:** have the electrician check how full the conduit is
and the state of the old wiring, then push a fish tape or nylon pull cord
through. If a cord gets through, bare fibre will too. If the conduit is packed
or the insulation is brittle, pull nothing through it.

### Comparison

| | Cat6 | Fibre |
|---|---|---|
| Cost | ~₹1,500-3,000 | ~₹3,500-6,500 |
| Pulling through many bends | harder (6mm, stiff) | easier (3mm bare, flexible) |
| Surge path to router and xero | yes (mitigate with a surge protector) | none |
| Wiring rules in a mains conduit | only with 300V-rated cable | fine |
| Power watchdog | needs the ping change | works unchanged |
| Extra powered boxes | none | two converters |

**Fallback if the conduit is unusable:** a surface run along the skirting.
Flat Cat6 costs ~₹1,000 and is DIY, but it is visible and needs the watchdog
ping change. A thin fibre run is nearly invisible.

## 4. Moving the router to a central spot

This would remove the need for the extender altogether. Open questions for the
backlog entry: Airtel has to re-route its fibre drop, or extend it inside the
house, and may charge for it; the router's UPS has to move with it; and a
central router must still reach xero's room well without the extender. If it
does, xero could hang off a short cable or good 5GHz, and sections 2 and 3
shrink or disappear.
