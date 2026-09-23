# Airtel: download throughput is path-dependent, upload is not

**Date:** 2026-09-23
**Symptom:** fast.com reported 1.9 Mbps while the line felt usable. Two router
restarts changed nothing.

## What it is not

- **Not the local link.** Upload ran 34.8-40.6 Mbps over the same 2.4GHz Wi-Fi
  throughout. Wi-Fi that carries 40 Mbps up is not what caps 10 Mbps down.
- **Not the router.** Restarted twice, no change in any measurement.
- **Not the plan.** The line demonstrably does >=40 Mbps.
- **Not distance or international transit.** This was the working theory for
  most of the session and it is wrong - see below.

## What the numbers actually show

Download, various targets:

| Target                      | RTT    | Down        |
|-----------------------------|--------|-------------|
| Cloudflare Mumbai PoP       |  18 ms | 34.7 Mbps   |
| Netflix OCA, Pune (Airtel)  |  18 ms | 34.6 Mbps   |
| Netflix OCA, Mumbai (Airtel)|  19 ms | 27.6 Mbps   |
| Netflix OCA, Mumbai IX      |  10 ms | 27.7 Mbps   |
| Netflix OCA, Mumbai IX      |   9 ms | **6.0 Mbps**|
| Netflix OCA, Delhi IX       |  78 ms | 13.4 Mbps   |
| Speedtest, Patna (~1000 km) |  89 ms | 10.6-15.9   |
| Hetzner Falkenstein, DE     | 132 ms | 0.9-4.0     |
| Hetzner Ashburn, US         | 273 ms | 1.4-6.2     |

Upload, same period: **34.8-40.6 Mbps**, unaffected.

Three findings, in order of how much they constrain the cause:

1. **Inbound only.** The Patna server gives 15.9 Mbps down against 40.6 Mbps up
   - same host, same 89 ms RTT, same moment. Equal RTT in both directions rules
   out window-size and bandwidth-delay explanations entirely.
2. **Path-dependent, not distance-dependent.** Two Mumbai IX OCAs one
   millisecond apart differ 4.6x (27.7 vs 6.0 Mbps), and the 9 ms target is the
   lowest-latency host measured all session. Any story shaped like "the farther
   it is the slower it gets" is contradicted by this row.
3. **Loss only under load.** Hetzner DE: 0% loss idle, 12.5% while downloading.
   Domestic: 0% idle, 0-3.3% loaded. Every idle ping all session looked clean,
   which is why the problem kept reading as "slow" rather than "lossy".

Together: congestion or capacity exhaustion on *particular inbound paths* into
Airtel - different peering ports, IX links or transit providers hit differently
- not one saturated pipe and not a shaper.

## Why the speed tests disagreed

Neither measures "the internet"; each measures one path to one server, and on
this connection paths differ by 6x. fast.com tests Netflix OCAs, three of which
are fast here and one of which is 6 Mbps. speedtest.net offered nothing closer
than Patna (~1000 km) because Airtel's geolocation of 122.170.192.33 places the
connection far from where it is. Cloudflare terminates at a Mumbai PoP on a
healthy path and reads 35 Mbps.

The disagreement is the diagnostic signal. A single number would have hidden
the whole effect.

## Where this connection actually is, and which Airtel it is

`122.170.192.33` is **AS24560** (`AIRTELBROADBAND-AS-AP`, Bharti Airtel
Telemedia Services - the fixed-line arm), geolocated to **Pune**. Two things
follow:

- **The OCA table is mostly distance after all.** Pune 18 ms / 34.6 Mbps,
  Mumbai ~19 ms / 27.6, Delhi 78 ms / 13.4. The real anomaly is narrower than
  "path-dependent": it is the *single* Mumbai IX cache at 9 ms giving 6.0 Mbps
  while its neighbour at 10 ms gives 27.7. One congested peering path, not a
  broad fault - which is also what a cable cut would *not* look like.
- **Speedtest's server list was junk.** Patna is ~1,400 km from Pune, so its
  "nearest server" numbers (10.6-15.9 Mbps) were a long domestic haul, not a
  local baseline. The domestic baseline is the ~35 Mbps Cloudflare/Pune figure.

The ASNs worth knowing when escalating:

```
AS24560  AIRTELBROADBAND-AS-AP  Telemedia Services   <- this line
AS45609  BHARTI-MOBILITY-AS-AP  mobile / GPRS        <- an Airtel phone
AS9498   BBIL-AP                Airtel backbone      <- shared international transit
```

Broadband and mobile are separate access networks under separate ASNs sharing
the AS9498 backbone, so **tethering to an Airtel phone and re-running
`speedcheck.sh` splits the diagnosis**: mobile also degraded implicates AS9498's
backbone/transit (Airtel-wide, network team); mobile clean implicates AS24560's
access or backhaul locally (a line ticket).

## Has anyone else reported this?

The signature is documented, but nothing current matches:

- A TechEnclave thread on Airtel Xstream peering describes it closely -
  international downloads falling 30-32 -> 6-7 Mbps with India-hosted servers
  unaffected (Jan 2022, recurring Mar 2023). One March 2023 post is nearly
  verbatim this case: *"anything outside of India gives me <1mbps download, but
  still shows 100mbps upload"*.
  <https://techenclave.com/t/airtel-xstream-fiber-peering-issue/254934>
- Anurag Bhatia documented a real national-scale instance: from 2026-01-28
  20:08 IST the MENA submarine cable failed, Airtel AS9498 rerouted India-EU
  via Singapore and the US, latency past 320 ms, 20-80% loss on individual
  hops, Arelion's EU route learning for AS9498 down 7,000 prefixes. Repaired
  2026-03-13. <https://anuragbhatia.com/post/2026/01/eu-india-routing-issues/>
- **Nothing current.** His AS9498 posts since May 2026 are about RPKI and
  AS_PATH filters, not capacity; outage trackers show no Airtel spike.

That absence is evidence: a nationwide transit fault would be loud. It points
at something closer to this connection - local backhaul, the BNG, or one
congested peering port - which is consistent with the single-outlier finding
above.

## Reproducing

`tools/network/speedcheck.sh [seconds_per_target]` runs the comparison: link
and PoP, four throughput targets, DNS timing, idle-vs-loaded loss, traceroute.
Run it before and after any claimed ISP fix.

To re-enumerate the Netflix OCAs this connection is steered to:

```bash
curl -s "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=5"
```

## Open

Reported to Airtel? Not yet as of writing. The useful framing is inbound-only
congestion affecting specific paths including domestically-peered ones, with
upload at full rate - not "my internet is slow", which invites a domestic test
that will read 35 Mbps and close the ticket.
