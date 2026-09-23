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
