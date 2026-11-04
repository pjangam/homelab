# MirAIe AC (Node-RED + MQTT bridge)

The Panasonic AC reaches Home Assistant through a Node-RED bridge: the
`node-red-contrib-ha-miraie-ac` node logs into MirAIe's cloud, and republishes
the unit onto the local Mosquitto broker as an MQTT-discovery climate entity.
Node-RED runs **on the wol-sender Pi** (`192.168.1.124`), Mosquitto and HA on
xero, so an outage here is usually one of those three links rather than the AC.

| | |
|---|---|
| **HA entity** | `climate.panasonic_ac_panasonic_ac` |
| **Health tile** | `binary_sensor.homelab_healthcheck_homelab_miraie_ac` on the Stats dashboard |
| **Is it usable?** | `check_miraie_ac_available.sh` (read-only, asks HA) |
| **What is broken?** | `diagnose_miraie_ac.sh` (read-only; `--capture` sniffs MQTT across a restart) |
| **Fix it** | `fix_miraie_ac.sh` (no-op when healthy, `--force` to restart anyway) |
| **Daily login renewal** | `renew_miraie_login.sh`, 11:05 from xero's crontab |
| **Refresh flow** | `nodered_refresh_flow.json` + `deploy_nodered_refresh_flow.sh` |


Mosquitto runs on `xero`; Node-RED itself runs on the Pi (`wol-sender`, `192.168.1.124`) - moved there 2026-08-22, see `PROJECTS.md` "Move some load to the Raspberry Pi". The `node-red-contrib-ha-miraie-ac` node is set up automatically. Manual steps after first run:

1. Open Node-RED at `http://192.168.1.124:1880` - the editor now requires login (`adminAuth` in `settings.js`, enabled 2026-08-22 since it's reachable over Wi-Fi rather than only from xero itself; previously had no auth at all). Username `pramod`; the password should be saved in Vaultwarden as "Node-RED admin" (check there first - if missing, it was generated during the 2026-08-22 migration and needs resetting via `node-red admin hash-pw` + editing `settings.js`'s `adminAuth` block on the Pi).
2. Find the `ha-miraie-ac` node in the palette (left sidebar), drag it into a flow
3. Double-click the node and configure:
   - **Mobile number** — Miraie registered phone number
   - **Password** — Miraie app password
   - **MQTT broker** — host `192.168.1.123` (xero's LAN IP - Node-RED isn't on the same Docker network as Mosquitto anymore, so the `mosquitto` container hostname won't resolve), port `1883`, username `homelab` + password (Mosquitto requires auth as of the 2026-08-23 security pass — see Vaultwarden "Mosquitto MQTT")
4. Click Deploy (top right) — node status should show "HA broker connected" and "MirAIe broker connected". If credentials were entered via the node's config panel, they must land nested under the node's "credentials" store, not as flat fields - if the broker doesn't connect after Deploy, a full container restart (`docker restart node-red`), not just a redeploy, may be needed to pick them up.
5. In Home Assistant: Settings → Integrations → Add Integration → MQTT → host `192.168.1.123`, port `1883`, username `homelab` + password
6. AC appears under Settings → Devices & Services → MQTT as "PANASONIC AC"
7. If entity shows "Unavailable", turn the AC on/off physically to trigger a state update

> **TODO (deferred): Full automation approach**
> 1. Store Miraie credentials in Bitwarden
> 2. On setup, pull them via Bitwarden CLI (`bw get item "Miraie AC"`)
> 3. Export working Node-RED flow as `nodered-flows.json` in repo, inject credentials and POST to Node-RED API
> 4. Set up HA MQTT integration via HA REST API using a long-lived token (no Selenium needed)
> 5. Only manual step: generate the HA long-lived token once

## Fixing a dead bridge by hand

**Symptom:** the AC is `unavailable` in HA, usually with *"This entity is no
longer being provided by the mqtt integration"*. That message means HA still
has the entity in its registry but no MQTT discovery config behind it -
Node-RED publishes `homeassistant/climate/panasonic-ac/config` on every
connect, so if the bridge is down it never gets republished.

```bash
projects/miraie-ac/fix_miraie_ac.sh           # no-op if the bridge is already healthy
projects/miraie-ac/fix_miraie_ac.sh --force   # restart anyway (republishes discovery)
projects/miraie-ac/diagnose_miraie_ac.sh      # read-only: what is actually broken
```

The fix is one `docker restart node-red` on the Pi - nothing on xero needs
restarting, Mosquitto and HA are unaffected. The script wraps that restart in
the two things that actually matter:

1. **It checks DNS first and refuses to restart if `miraie.in` isn't
   resolving.** Restarting into broken DNS silently recreates the original
   failure rather than fixing it (see below).
2. **It verifies the bridge came back**, polling for both ESTABLISHED
   connections. `docker restart` exiting 0 proves nothing, and neither does
   the container healthcheck - that only means Node-RED's web UI answers on
   1880.

**Root cause of the 2026-09-07 outage**, which is the failure mode to expect
again: a single DNS lookup failed at Node-RED startup and the node never
retried.

```
6 Sep 12:17:43 - [error] [ha-miraie-ac:MirAIe] There was an error logging in.
                         getaddrinfo EAI_AGAIN auth.miraie.in
```

The container then sat `Up (healthy)` for 29 hours holding **zero** broker
connections. Note the entrypoint's `until nslookup auth.miraie.in` guard did
not help: it passed, and DNS failed again five seconds later at login.

`projects/miraie-ac/diagnose_miraie_ac.sh --capture` restarts Node-RED while sniffing
MQTT, which is the only way to see this path's traffic - `ha-miraie-ac`
publishes state and availability with `retain=false`, so subscribing while the
AC sits idle shows nothing whether the bridge is healthy or dead.

## Is the AC actually usable? (healthcheck alert + dashboard tile)

`projects/miraie-ac/check_miraie_ac_available.sh` asks the only question that matters -
what does HA hold for `climate.panasonic_ac_panasonic_ac`? - and
`projects/healthcheck/healthcheck.sh` acts on the answer, with a tile on the Stats
dashboard (`binary_sensor.homelab_healthcheck_homelab_miraie_ac`) reflecting
the latest observation immediately:

1. **One unavailable run (*/15 cron):** nothing yet - discovery blips and
   node-red restarts drop the entity for seconds.
2. **Still unavailable on the next run:** it runs
   `projects/miraie-ac/fix_miraie_ac.sh --force` itself, **once per outage**,
   with the output going to `healthcheck.log`. If that brings the entity back
   (the missed-availability case, e.g. 2026-09-15) nobody is alerted.
3. **Not cured:** one email + ntfy saying what the fix found - exit 2 "switch
   the AC on", exit 3 "restart HA's MQTT integration", exit 1 "the bridge did
   not reconnect". It is not retried: those are not problems a restart fixes.

Cured outages still show on the tile as `autofixes_24h` / `last_autofix`
attributes, and 3 or more fixes in 24h raises its own alert, so an AC that
keeps dropping cannot hide behind a fix that keeps working.
`projects/miraie-ac/test_healthcheck_miraie_ac_autofix.sh` covers all of this
with the check and fix stubbed.

That tile was added with `projects/healthcheck/add_stats_dashboard_tile.py`, which edits the
dashboard over HA's websocket API. Use it rather than hand-editing
`.storage/lovelace.dashboard_stats`: storage-mode dashboards live in HA's
memory, so a file edit does nothing until HA restarts - and restarting HA is
itself what knocked the AC entity out for 37 minutes on 2026-09-11. The script
is idempotent and snapshots the dashboard into `backups/lovelace/` first.

Added 2026-09-11, after the AC broke twice that evening from two unrelated
causes and *nothing* noticed either time — both were found by looking. Every
signal that existed stayed green throughout: node-red runs on the Pi so it is
not in healthcheck's docker check at all, and the container reported
`Up (healthy)` through both outages anyway. Watching the entity catches both
root causes, and whatever breaks it next, because it watches the symptom you
actually depend on rather than any one mechanism.

Why 30 minutes: a brief `unavailable` is normal and self-healing — HA blips
every MQTT entity for a second or two when discovery re-registers, and every
`docker restart node-red` drops the entity for ~20s. Both real outages (79min
and 37min) run well past the threshold. The check exits 2 for "can't tell"
(no token, HA not answering) and the healthcheck deliberately does not alert
on that: HA being down is already covered by the container check.

## Node-RED Watchdog (MQTT bridge health)

**Why:** the `ha-miraie-ac` node can end up in a stale connection loop - confirmed once (2026-08-23), where credentials were correctly stored but the live MQTT connection to Mosquitto kept silently failing until a full container restart, not just a flow redeploy. `watchdog_nodered.sh` (on the Pi) checks the container's actual TCP state and restarts it if the bridge isn't connected.

**How it works:**
1. Every 10 minutes (cron, on the Pi), the script checks `/proc/net/tcp` inside the `node-red` container for two ESTABLISHED connections: one to MirAIe's cloud MQTT broker (port 8883) and one to Mosquitto on xero (port 1883).
2. If either is missing, it runs `docker restart node-red`.
3. Deliberately does **not** wait for AC state/availability MQTT messages (the original design) - Node-RED only publishes those once per reconnect (not retained by the node's own code), so nothing arrives while the AC is powered off, which is most of the year outside summer. That caused a false restart on every single run regardless of actual bridge health.
4. All actions logged via `logger -t nodered-watchdog` (`journalctl -t nodered-watchdog`) and to `nodered-watchdog.log` on the Pi.

**Currently enabled** (re-enabled 2026-09-11 for AC season, expected to stay on through at least mid-November 2026). It had been disabled since 2026-08-23 for the off-season. Verified on re-enable by stopping `node-red` and running the script by hand: it logged `MQTT bridge down (cloud_connected=0 local_connected=0)`, restarted the container, and the bridge was back in ~5s.

**A second, separate way the AC entity goes unavailable.** Later the same evening (2026-09-11 21:05) it happened again with a different cause: the unit was provably online - it answered a `mode/set` and published fresh state - while HA held the entity `unavailable` for 37 minutes. The node publishes the unit's `availability` with `retain=false`, and HA gates the entity on that topic (`avty_t` in the discovery payload). So once **HA** restarts it holds no availability value and keeps the entity unavailable no matter how much state arrives; it recovers only if HA happens to be subscribed when Node-RED republishes `online`, and since the config and availability go out back-to-back on a reconnect, that is a race HA can lose. Re-publishing `online` to `miraie-ac/panasonic-ac/availability` brings it straight back. `projects/miraie-ac/fix_miraie_ac.sh` now checks the HA entity and does exactly that re-delivery (exit 3 if the entity still will not come back, which means the problem is HA-side).

**What it does not cover.** This watchdog only sees the *bridge*. On 2026-09-11 the AC entity went `unavailable` in HA while both broker connections stayed healthy the whole time - the indoor unit itself had gone silent to the MirAIe cloud, and three `docker restart node-red` in a row reported success and changed nothing. The watchdog correctly stays quiet in that case, because restarting cannot fix a unit that is switched off. That failure is what `projects/miraie-ac/fix_miraie_ac.sh` diagnoses (exit 2 = the unit, not the bridge).

It also cannot see the missed-availability case above, where the bridge is healthy and the unit online but HA never got the `online`. On 2026-09-15 an HA restart at 16:15 set that up. Node-RED's connection to Mosquitto never dropped, so it had no reason to republish anything, and the entity sat unavailable until 17:52 while every run here logged "healthy". Restarting HA does **not** make Node-RED reconnect. Only a node-red restart or a lost broker connection does. Both entity-side cases are now handled from xero: `healthcheck.sh` watches the HA entity and runs `fix_miraie_ac.sh --force` on its own (see "Is the AC actually usable?" above).

**Status refresh flow (prevents the missed-availability case).** Since 2026-09-15 Node-RED has an inject node wired into the MirAIe node, firing 90s after start and then every 5 minutes. Any message into that node makes it fetch each AC's status from the MirAIe cloud API and publish state and availability again. So a missed `online` now costs HA at most 5 minutes, and nothing is invented: the value is the cloud's own `onlineStatus`, so an AC that is really off still shows unavailable. It does **not** republish the discovery config, so after an HA restart the entity stays gone until a node-red restart, which the healthcheck auto-fix still covers. This also means `miraie-ac/#` now carries traffic every 5 minutes, not only on reconnect or change.
- Source of truth: `projects/miraie-ac/nodered_refresh_flow.json`. Deploy with `projects/miraie-ac/deploy_nodered_refresh_flow.sh`: it backs up `flows.json` on the Pi, merges the nodes by id, restarts node-red, and checks on MQTT that the refresh publishes the same availability and state fields as the reconnect. If not, it rolls back automatically. Deploying edits the file and restarts, because the admin API needs the editor password. `--rollback` restores the newest backup by hand.
- `projects/miraie-ac/test_nodered_refresh_live.sh` publishes `offline` to make HA mark the AC unavailable, then waits for the refresh to bring it back. First run: back after 180s, no restart.
- Token lifetime: the node logs in once at startup and the refresh reuses that token. A MirAIe login returns `expiresIn` = 7257599s, which is **84 days** (measured 2026-09-15 with `projects/miraie-ac/check_miraie_token_lifetime.sh`, which does a separate login and prints no secrets; the node's refresh kept working afterwards). Every node-red restart logs in again and resets the 84 days, and the watchdog, the fix script and image updates all restart it, so an expiry would need node-red to run for 12 weeks straight. That case is covered too: `projects/miraie-ac/renew_miraie_login.sh` runs daily at 11:05 from xero's crontab (log `miraie-login-renew.log`). It reads node-red's `StartedAt` on the Pi and, once the login is 70 of its 84 days old, renews it by restarting node-red through `fix_miraie_ac.sh --force`. If the renewal fails it emails and pushes, and it retries daily for the two weeks left. Use `--force` to renew now. `projects/miraie-ac/test_renew_miraie_login.sh` covers its decisions, with ssh, the fix script and the alerts faked. If a token ever does expire, the refresh fails quietly: nothing is published, and the node logs `There was an error getting device status` (`ssh pramod@192.168.1.124 'docker logs --since 24h node-red | grep -i error'`).

**Disable / re-enable** (no need to touch cron; edit on the Pi): the toggle lives in `WATCHDOG_ENABLED` inside `/home/pramod/nodered-watchdog.env`, next to the script itself - a plain env file rather than a hidden dotfile, so it's easier to stumble on again next summer.
```bash
# on the Pi: edit /home/pramod/nodered-watchdog.env
WATCHDOG_ENABLED=false   # disable (e.g. AC off for the season)
WATCHDOG_ENABLED=true    # re-enable (e.g. before summer AC season)
```

**Cron entry** (`crontab -e` on the Pi):
```
*/10 * * * * /home/pramod/watchdog_nodered.sh >> /home/pramod/nodered-watchdog.log 2>&1
```

