# 2026-09-11: spotifyd stops advertising as a Connect device, because a --user unit can't wait for the network

**Symptom:** the HA script `script.play_bedroom_track` failed with

```
Failed to perform the action script/play_bedroom_track.
Could not find media_player.xero_t2ri8v1ku89v8s2ci4d6vrfv2_spotcast
in the managed integrations
```

`spotifyd.service` looked perfectly healthy throughout - `active (running)`, 5 days uptime, authenticated as `t2ri8v1ku89v8s2ci4d6vrfv2`, connected to `ap-gae2.spotify.com`, resolving its spclient AP. Nothing had crashed and nothing was restarting.

**Root cause:** spotifyd's `libmdns` zeroconf server enumerates network interfaces **exactly once, at startup, and never retries**. At the 2026-09-06 boot it ran before NetworkManager had brought `enp1s0` up, found no usable interface, logged one line, and carried on forever:

```
Sep 06 11:56:02 xero spotifyd[1329]: [INFO] Starting zeroconf server to advertise on local network.
Sep 06 11:56:02 xero spotifyd[1329]: [ERROR] libmdns error: Setting up dns-sd failed: No such device (os error 19)
```

From there the whole chain fails quietly: no `_spotify-connect._tcp` advertisement → `xero` never appears in Spotify's device list → spotcast never marks its `media_player.xero_..._spotcast` entity available → any script targeting that entity errors out. The user-visible failure is four layers away from the cause, and the cause is a single non-fatal ERROR line five days in the past.

**Why the unit's `After=` didn't prevent it:** it looked like it should. The unit read

```
After=network-online.target sound.target
```

but this is a `systemd --user` unit, and `network-online.target` exists only in the **system** manager. The user manager resolves it to nothing and drops the ordering silently:

```
$ systemctl --user list-units --all | grep network-online
● network-online.target   not-found inactive dead   network-online.target
```

So the service had appeared to wait for the network for as long as the unit had existed, and never had. `Restart=always` doesn't help either - the process never exits, so systemd has no failure event to react to.

**The race, from the journal:**

- **11:55:43** - boot.
- **11:56:01** - the per-user systemd manager for UID 1000 starts; `default.target` queued.
- **11:56:02** - spotifyd starts, sets up zeroconf, finds no interface, logs the error.
- **11:56:04** - `enp1s0: Link is Up`; NetworkManager begins activation and only then assigns the address.

spotifyd lost the race by about two seconds. It had also failed the same way at 11:33, 11:43 and 11:44 that morning - every start attempt during the post-outage reboot sequence.

**Not the previous zeroconf bug.** On 2026-09-02 an identical *symptom* was traced to an orphaned Docker network breaking libmdns interface enumeration (`2026-09-02-spotifyd-zeroconf-broken-by-orphaned-docker-network.md`). That is genuinely fixed - `docker network ls` is clean, only `bridge`/`homelab_default`/`host`/`none`. Same error line, different cause. What masked it: the 2026-09-02 fix was applied by restarting spotifyd *by hand, long after boot*, when the network was obviously up. That restart is why it worked, and it's why the underlying boot race stayed hidden until the next reboot re-rolled the dice.

**Why the watchdog didn't catch it:** `cron/watchdog_spotifyd.sh` existed and ran every 5 minutes, but only looked for the 2026-08-04 hang signature - a `CLOSE-WAIT` socket with `Recv-Q > 0`. This failure has no stuck socket. Sockets were healthy; only the mDNS advertisement was missing, which the watchdog never looked at.

**Secondary issue found in the same logs:** 36 × `429 Too Many Requests` this boot, and a websocket that stopped responding at `Sep 10 00:54` with nothing after it - the known session-staleness pattern from 2026-08-17. Independent of the zeroconf bug; the same restart cleared it.

**Fixes:**

1. **`scripts/wait_for_network.sh`** - blocks until a global-scope, non-loopback IPv4 address exists (`ip -4 -brief addr show scope global up`), 45s timeout. Wired in as `ExecStartPre=-...` in `spotifyd.service`. The `-` prefix is deliberate: if the network truly never arrives, start spotifyd degraded rather than not at all.
2. **`systemd/user/spotifyd.service`** - the misleading `After=network-online.target` is gone, replaced with a comment explaining why it can't work in a user unit, so it doesn't get "helpfully" re-added later. The unit is now tracked in the repo; it previously existed only at `~/.config/systemd/user/` and was in no way version-controlled.
3. **`cron/watchdog_spotifyd.sh`** - now also greps the current MainPID's journal for `Setting up dns-sd failed` and restarts on sight. Scoped by `_PID=` so an error from an already-replaced invocation can't retrigger forever. No threshold wait, unlike the CLOSE-WAIT check: this state never self-heals, so there's nothing to wait out.

**Verified:** after restart, `avahi-browse -rt _spotify-connect._tcp` shows `xero` advertising on `enp1s0`; spotcast's device sensor went 2 → 3 with `xero` in the list; `media_player.xero_..._spotcast` went `unavailable` → `off`. The new `ExecStartPre` runs and exits 0. The watchdog's new check matches the real historical log line, returns 0 for the healthy PID, and leaves a healthy spotifyd untouched.

**Follow-up the same day - closing the detection gap, not just the bug.** The three fixes above prevent and auto-heal this, but nothing would have *told* anyone. The dashboard tile and the healthcheck's spotifyd signals were all watchdog-derived, so during the five silent days every one of them read green: `stuck_now` false, `restarts_24h` 0, unit active. The alerting was working perfectly and had nothing to report.

Added a check of the end state instead of a symptom - **is spotifyd actually discoverable?** (`scripts/check_spotifyd_advertising.sh`, an exact-match lookup for the host's own `_spotify-connect._tcp` advertisement). This is deliberately not a check for the libmdns log line: the advertisement is what the Spotify device list, the spotcast entity and every HA script downstream actually depend on, so it catches any cause - both known ones, and whatever breaks it next.

- **No new cron.** It rides the existing `*/15` healthcheck, so nothing new polls the machine.
- **Alerting needs two consecutive misses (~15min).** A single miss is expected: the watchdog restarts spotifyd on its own, and there's a ~10s window mid-restart where it genuinely isn't advertising. Alerting on that would page for something already fixed.
- **The dashboard flag flips on the first miss**, though - a tile is for looking at, an alert is for interrupting you.
- **Three-way exit code.** "Not advertising" (rc=1) and "can't tell" (rc=2 - spotifyd stopped, or avahi-daemon down) are different: rc=2 never alerts, because a stopped spotifyd is already covered by the failed-unit check and a dead avahi would otherwise point the finger at the wrong service.
- Surfaces as `binary_sensor.homelab_healthcheck_homelab_spotifyd_connect_advertising`, tiled next to the existing spotifyd tiles (`scripts/apply_spotifyd_advertising_dashboard_tile.sh`), and goes through `problems[]` so email and ntfy both fire with the existing change-based dedup - no new alerting path.

Covered by `scripts/test_spotifyd_advertising_check.sh` (7 checks: healthy, the real fault, another device advertising, a prefix-colliding name, a removal event, spotifyd stopped, avahi missing) and `scripts/test_healthcheck_spotifyd_advertising.sh` (12 checks, running the real `healthcheck.sh` inside a mirror repo with the advertising check, both alert senders and the MQTT publisher stubbed - so a test never mails, pushes, or writes a fake red tile to the live dashboard).

**Prevention - the general rule this establishes:** `After=`/`Wants=` on a **system** target is silently a no-op in a `systemd --user` unit. It does not warn, it does not fail, it just doesn't order anything. Any user unit that truly needs the network must wait for it itself, in `ExecStartPre`. And more generally: a daemon that sets something up once at startup and never retries cannot be verified by `systemctl status` - "active (running)" only ever meant the process is alive, and for spotifyd that has now been three separate incidents (2026-08-04 hang, 2026-09-02 orphaned network, this one) where it was alive and useless.
