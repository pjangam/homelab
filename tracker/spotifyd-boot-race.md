# spotifyd stopped advertising as a Connect device - boot race, not the old Docker-network bug
**Status:** Done

**Why:** `script.play_bedroom_track` failed with `Could not find media_player.xero_..._spotcast in the managed integrations`, while `spotifyd.service` showed `active (running)` with 5 days uptime and a clean authenticated session. Same visible symptom as the 2026-09-02 zeroconf bug, different cause.
**Outcome:** fixed and verified 2026-09-11 - spotifyd now waits for the network in `ExecStartPre`, its unit is tracked in `systemd/user/`, the watchdog restarts on the libmdns error, and `projects/spotifyd/check_spotifyd_advertising.sh` alerts if `xero` stops being discoverable. Full writeup: `docs/incidents/2026-09-11-spotifyd-zeroconf-lost-to-boot-race.md`.
- Left open: worth watching whether the ESP32/remote-control projects hit the same user-unit-network trap.

#### Root cause
- spotifyd's `libmdns` zeroconf server enumerates interfaces once at startup and never retries. At the 2026-09-06 boot it started at 11:56:02, two seconds before `enp1s0` got carrier at 11:56:04, logged one non-fatal `Setting up dns-sd failed: No such device (os error 19)` and ran happily for five days without ever advertising. No advertisement → `xero` absent from Spotify's device list → spotcast's entity never became available → the HA script errored. Four layers between cause and symptom.
- **The unit's `After=network-online.target` was a no-op the whole time.** It's a `systemd --user` unit, and that target only exists in the system manager - the user manager reports it `not-found` and silently drops the ordering. It had looked like it waited for the network for months and never did.
- **Not a regression of the 2026-09-02 fix** - `docker network ls` is clean. That fix was applied by restarting spotifyd by hand long after boot, which is exactly why it worked and exactly why this race stayed hidden until the next reboot.
- **The watchdog was blind to it:** `projects/spotifyd/watchdog_spotifyd.sh` only looked for the 2026-08-04 hang signature (`CLOSE-WAIT` with `Recv-Q > 0`). Here the sockets were perfectly healthy; only the mDNS advertisement was missing.

#### Fix
- **Fixed three ways:** new `projects/spotifyd/wait_for_network.sh` waits for a global-scope IPv4 address, wired in as `ExecStartPre=-` (dash so a dead network degrades to "start anyway"); `spotifyd.service` is now tracked in `systemd/user/` (it lived only in `~/.config` and was version-controlled nowhere) with the misleading `After=` replaced by a comment explaining why it can't work; the watchdog now greps the current MainPID's journal for the libmdns error and restarts on sight, scoped by `_PID=` so a stale error can't retrigger forever, with no threshold wait because this state never self-heals.
- **Also cleared:** 36 × `429 Too Many Requests` and a websocket dead since Sep 10 00:54 - the known 2026-08-17 staleness pattern, independent of the above, fixed by the same restart.
- **Detection gap closed.** The fixes above prevent and auto-heal it, but nothing would have *said* anything - every spotifyd signal on the dashboard was watchdog-derived, so all five silent days read green. Added `projects/spotifyd/check_spotifyd_advertising.sh`, which asks the end-state question (is it actually discoverable?) rather than looking for a known log line, so it catches future causes too. **No new cron** - it rides the existing `*/15` healthcheck. Alerts after two consecutive misses (a single miss is just the ~10s window during a watchdog restart), while the dashboard flag flips on the first. New tile `binary_sensor.homelab_healthcheck_homelab_spotifyd_connect_advertising`; alerts reuse `problems[]`, so email + ntfy fire through the existing dedup with no new alerting path. 19 checks across two test scripts, with alert senders and the MQTT publisher stubbed so tests never mail, push, or write a fake red tile.

#### Verification
`avahi-browse -rt _spotify-connect._tcp` shows `xero` advertising; spotcast device sensor 2 → 3; the entity went `unavailable` → `off`.

#### Log
- 2026-09-06: boot race - spotifyd started before `enp1s0` had carrier and never advertised for five days.
- 2026-09-11: diagnosed, fixed three ways, 429s/websocket cleared by the same restart, verified. Same day: detection gap closed with `check_spotifyd_advertising.sh`.
