# Airtel: download throughput is unstable, upload is not - diagnosed, not reported
**Status:** Closed

**Why:** fast.com read 1.9 Mbps on 2026-09-23 while the line still felt usable, and two router restarts changed nothing. Measuring it properly found something narrower and odder than "the internet is slow". Full write-up in `docs/incidents/2026-09-23-airtel-inbound-throughput-path-dependent.md`.
**Outcome:** **Closed 2026-09-29 without reporting it.** Diagnosed as congestion or capacity exhaustion on *particular inbound paths* into Airtel - different peering ports, IX links or transit hit differently - not one saturated pipe and not a shaper. The line is usable, upload is at full rate, and the one action left - an Airtel ticket - is not worth the call: the domestic test an agent would run reads 35 Mbps and closes it. Nothing here is unfinished work; it is a known property of this connection, kept because the next "the internet is slow" will look exactly like it.

#### What it is not

Not the local link (upload ran 34.8-40.6 Mbps over the same 2.4GHz Wi-Fi throughout - Wi-Fi carrying 40 Mbps up is not what caps 10 Mbps down), not the router, not the plan, and **not distance or international transit** - that was the working theory for most of the session and the evidence killed it.

#### The three findings

In order of how much they constrain the cause:
- **Inbound only.** The Patna speedtest server gave 15.9 Mbps down against 40.6 Mbps up - same host, same 89 ms RTT, same moment. Equal RTT in both directions rules out window-size and bandwidth-delay explanations entirely.
- **Unstable over minutes, which is what the path-dependence claim turned out to be.** Cloudflare Mumbai read 34.7, then 3.0, then 35.8 Mbps inside an hour with nothing changed at this end. An earlier version of this entry concluded "one congested peering path" from a table of *sequential* samples; re-measuring inverted the ranking completely. **Retracted** - see the write-up. Upload never moved throughout.
- **Loss only under load.** 0% idle and 12.5% while downloading on the Hetzner DE path; 0-3.3% domestic. Every idle ping looked clean all session, which is why it kept reading as "slow" rather than "lossy".

Together: congestion or capacity exhaustion on *particular inbound paths* into Airtel - different peering ports, IX links or transit hit differently - not one saturated pipe and not a shaper.

#### Why the speed tests disagreed

This is the thing that made it visible at all: neither measures "the internet", each measures one path to one server, and here paths differ by 6x. speedtest.net offered nothing nearer than Patna (~1000 km) because Airtel's geolocation of the IP places the connection far from where it is; Cloudflare terminates at a healthy Mumbai PoP and reads 35 Mbps. The disagreement is the signal - a single number hides the whole effect.

#### If it gets worse and a ticket becomes worth raising

- **Frame it as inbound-only congestion on specific paths**, including domestically-peered ones, with upload at full rate - *not* "my internet is slow". Ticket wording and the supporting numbers are in the incident write-up.
- **Re-measure first, and again after any claimed fix**, with `tools/network/speedcheck.sh [seconds_per_target]`: link and PoP, four throughput targets, DNS timing, idle-vs-loaded loss, traceroute.
- **Measure in the morning too.** Everything above was measured in one afternoon/evening, and the international numbers got visibly worse across the session (Hetzner DE 4.0 -> 0.9 Mbps). A morning run would say whether this is peak-hour congestion, which changes what Airtel can be asked for.

#### Not the MacBook DNS entry

That one also presents as "the internet is slow" and they overlapped on 2026-09-23. They are unrelated: DNS made *name lookups* take ~600 ms on the M2 only; this affects *throughput* on every device.

#### Log
- 2026-09-23: fast.com read 1.9 Mbps; two router restarts changed nothing; measured over one afternoon/evening (findings above). An early "one congested peering path" conclusion was retracted after re-measuring.
- 2026-09-29: closed without reporting it to Airtel.
