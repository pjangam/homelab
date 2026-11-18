# Home Wi-Fi: evening 2.4GHz drops
**Status:** Done

**Why:** every 2.4GHz device (both voice satellites, the Diwali WLED, the kandil switch, the wol Pi) drops several times an evening, and on 2026-11-06 the router's 2.4GHz radio stalled for 7 minutes and took the whole Wi-Fi down while wired xero stayed up. Write-up: `docs/incidents/2026-11-06-router-2.4ghz-wifi-stall.md`; settings and their reasons: `docs/wifi.md`.
**Outcome:** router changed 2026-11-06 22:45 from channel 10 (Auto) / B+G+N / WPA2 Mixed to G+N / WPA2 AES-only, and at 23:03 to **channel 6** (empty in a neighbour scan; 11 is shared with Airtel_moha_8524 at -70 dBm); all devices rejoined. Evening drops stopped (2026-11-17 check, see Log). Reopen if they come back: start with `wifi_drops.py`, then "If drops continue" below.

#### If drops continue
- Rescan (`curl -s http://192.168.1.127/json/net`, twice) and compare with the 2026-11-06 scan in `docs/wifi.md`; try 11 or 1 if 6 got crowded.
- Then suspect the Airtel firmware: ask Airtel for a replacement, or an own AP behind the router with the router's Wi-Fi off.
- Retiring the extender is its own entry: "Move the Airtel router to a central spot".

#### Extender reset (optional, not a task)
Next time the extender needs a reset anyway: factory-reset it, re-create `dlink_pramod_bed_room` with the same password, save the new admin password in Vaultwarden, set its DHCP server Off and WPA2/AES if offered (steps in `docs/wifi.md`).

#### Log
- 2026-11-06: 22:21-22:28 outage diagnosed as the router's 2.4GHz radio (devices on router and extender dropped together; no carrier loss, same public IP; router log `br0 up` at 22:29). Router settings changed 22:45. `tools/ha-diag/wifi_drops.py` and `docs/wifi.md` added. 23:03: neighbour scan from the WLED board (first on record), channel moved 11 -> 6. Extender admin password unknown (not on the label, Tether's change-password needs the current one), so its DHCP server stays on Auto until a reset.
- 2026-11-08: 07 Nov 18:00-23:00 vs 06 Nov: WLED 7 -> 0, bedroom satellite 14 -> 0, kandil 10 -> 0, living-room satellite 29 -> 12 (all before 21:00); no outage. 01:20 on 08 Nov the bedroom satellite dropped 6 times and lost 40-60% of pings while an Android phone (.18, OnePlus/OPPO-family, Instagram/Facebook) was busy on the extender; router-side devices were fine - the extender's double 2.4GHz hop, not the router.
- 2026-11-17: `wifi_drops.py` for 08-17 Nov: no evening hour with more than 1 drop on any device (sat-living 8 in 9 days, vs 29 on 06 Nov). Not Wi-Fi: wled-door is powered off 00:00 to about 18:00 every day; 5 kandil drops are HA restarts. Left: about 7 same-second drops on router and extender devices together (09 20:01, 09 21:55, 10 00:04, 11 16:55, 12 18:58, 13 07:06, 17 02:10), so a short router or xero-side blip; each recovered at once, no repeat of the 7-min stall. Status Done; reopen if evening drops return.
