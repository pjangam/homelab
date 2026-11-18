# Pi audio move follow-ups: monitoring, xero cleanup, then xero to the router
**Status:** Backlog
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Claude:** rest of monitoring step 1 - the bridge alarms (`whitenoise/available`, `volume/available`); Pi spotifyd is watched since 2026-11-05
- [ ] **Pramod:** pin the extender (`TL-WA850RE`) to `192.168.1.7` on the router
- [ ] **Claude:** watchdog ping signal (step 3) - must land before the router gets a UPS back

**Why:** white noise and Spotify moved to the wol Pi on 2026-09-24 (see "Move white noise and spotifyd from xero to the wol Pi" in Done). The cutover is done, but nothing watches the Pi's audio, and xero still carries the disabled copies.
**State:** xero moved to the router on 2026-10-17 (step 3), ahead of the watchdog change it was waiting on. The watchdog **still works for now**: the only working UPS backs xero and the router has none (user, 2026-10-22), so the router drops with mains and takes xero's carrier with it - it shut xero down cleanly in the 2026-10-22 outage. It goes blind the day the router is back on a UPS (when xero's CRU12V3A returns from warranty). Steps 1-2 not started: nothing alerts if spotifyd or a bridge breaks on the Pi; xero's spotifyd tile stays green only because its check now exits "not applicable".

#### Steps
1. **Monitoring - the real gap.**
   - ~~Move `watchdog_spotifyd.sh` to the Pi's cron~~ - done 2026-10-26 (`projects/spotifyd/deploy_watchdog_pi.sh`). Its restarts.log is on the Pi, so `healthcheck.sh`'s "keeps restarting" alarm on xero still can't see it.
   - ~~Point `check_spotifyd_advertising.sh`/the dashboard tile at `raspberrypi`~~ - done 2026-11-05: its own tile "Homelab Spotifyd (wol Pi)", see the Log.
   - Have `healthcheck.sh` alarm on the retained `whitenoise/available`/`volume/available` going `offline`.
2. **xero cleanup:** remove the disabled `white-noise`, `white-noise-mqtt`, `volume-mqtt` and `spotifyd` units and spotifyd from xero; update `projects/white-noise/README.md` and `white_noise_buttons_setup.md`, which still describe xero (the README carries a note saying so).
3. **Move xero to the router - moved 2026-10-17, the watchdog change is still to do.** Carrier loss stopped meaning a mains outage once xero went on the router's UPS (see the end of the Done entry). Add "the wol Pi **and** the extender both stop answering pings for N checks" to `watchdog_power.sh`; the extender needs a pinned IP first (it answers ARP for several LAN addresses with one MAC, `c2:c9:e3:09:e6:be`, so find its own one in the router's DHCP table). Patch cable replaced 2026-10-28: the link now comes up 1Gbps/Full (it had downshifted to 100Mbps, `check cabling!`).

#### Log
- 2026-11-05: **Pi spotifyd now on the healthcheck and the Stats dashboard**, after it sat disabled for two days unnoticed. New tile "Homelab Spotifyd (wol Pi)" (`binary_sensor.homelab_healthcheck_homelab_spotifyd_wol_pi`), red when `raspberrypi` is not advertising on the LAN (alert after two runs), Spotify's device list has lost it (alert at 30m), or its watchdogs restarted it 3+ times in 24h (its restarts.log is read over ssh). Also a new watchdog for the state neither host's `watchdog_spotifyd.sh` can see - running and advertising but forgotten by Spotify (xero 2026-11-01 to 11-03): `projects/spotifyd/watchdog_spotify_listed.sh`, xero cron */5, restarts the missing host's spotifyd after 15m, at most hourly; xero's tile now includes the same listed check. Checked first that a restart does not drop the device from Spotify's list, so it can't loop.
- 2026-10-26: `script.play_bedroom_track` failed with Spotify's "Device not found": spotifyd on the Pi logged `Connection to server closed` at 00:34 and never logged back in until a phone woke it at 11:08, while still advertising (so the advertising check stayed green). The watchdog had never been installed on the Pi. Added a lost-session rule (restart when the last session event is "closed" for 5 min), switched its journal reads to `_PID=` because the Pi keeps no user journal, added `test_watchdog_spotifyd.sh`, and deployed it with a */5 cron via `deploy_watchdog_pi.sh`.
- 2026-10-22: correction (user): xero is on the UPS, the router is **not** - the router's mini UPS was moved to xero while xero's CRU12V3A is out for warranty. So the watchdog was never blind in this setup; the 2026-10-22 outage proved it (carrier lost 15:12, clean shutdown 15:25).
- 2026-10-17: xero moved onto the Skadis board next to the router (`docs/skadis-layout.html`), cabled into the router, powered from the router's mini UPS. Same IP, nothing else to re-point. Link 100Mb/s Full, downshifted from 1Gbps by the cable. The wol Pi and the bedroom voice satellite were unplugged in the move and were offline afterwards. `docs/hardware.md`, `docs/home-network-uplink-options.md`, `Readme.md` and the watchdog's header updated.
