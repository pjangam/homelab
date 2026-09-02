# 2026-09-02: spotifyd's local Spotify Connect discovery silently broken since at least 2026-07-22

**Symptom:** "xero" never appeared as a Spotify Connect device in the Spotify app's device picker, on any device, ever (as far as could be confirmed). Everything else about spotifyd looked healthy - the service was `active (running)`, authenticated fine, and Spotify's Web API showed it as a valid logged-in session. Only local network discovery (Zeroconf/mDNS) was affected, so there was no obvious error surface until logs were checked directly.

**Root cause:** spotifyd's `libmdns`-based zeroconf advertisement enumerates every network interface on the host to broadcast itself. This host had an orphaned Docker bridge network (`homelab_node-red-net`, left over from the Node-RED → Raspberry Pi migration - see PROJECTS.md "Move some load to the Raspberry Pi" - with 0 containers attached) that `docker compose down` was never run against, so the bridge itself was never removed even though nothing used it. `libmdns` couldn't set up multicast on that dead interface and aborted the *entire* zeroconf setup as a result - not just skip the one bad interface - silently, on every single startup, going back to at least 2026-07-22 in the logs (the earliest `journalctl --user -u spotifyd` history covers). spotifyd 0.4.2 (the latest release) has no config option to restrict which interface it advertises on, so there was no way to work around this without removing the actual bad interface.

**How it was found:** while debugging a separate, unrelated request (adding an HA button to play a Spotify track on `xero`), `xero` still didn't show up as a device even after spotcast itself was confirmed working end-to-end (fixed in a separate incident - spotcast's own break was Spotify's `server-time` API endpoint changing, requiring a v4→v6 reinstall). That ruled out spotcast/HA as the cause and pointed back at spotifyd itself. `journalctl --user -u spotifyd -b | grep -iE "zeroconf|dns-sd|mdns"` showed `[ERROR] libmdns error: Setting up dns-sd failed: No such device (os error 19)` immediately after every "Starting zeroconf server" line, with no exception. `avahi-browse -a -t -r` confirmed no `_spotify-connect._tcp` service was ever actually being advertised, despite `avahi-daemon` itself (a separate, unrelated mDNS stack - spotifyd uses its own internal `libmdns`, not system avahi) running fine the whole time.

**Fix:**
```bash
docker network ls                       # look for a bridge with 0 containers attached
docker network inspect <name> --format '{{.Name}} containers={{len .Containers}}'
docker network rm homelab_node-red-net   # confirmed orphaned - 0 containers
systemctl --user restart spotifyd
```
Confirmed fixed: no `libmdns error` line on the next startup, and `avahi-browse -a -t -r` showed a genuine `_spotify-connect._tcp` record for `xero` on `enp1s0` afterward.

**Prevention:** run `docker compose down` (or at least `docker network prune`) whenever a service is removed from `docker-compose.yml`, rather than just deleting its block and leaving the service running - an orphaned network doesn't break the containers still using other networks, so nothing else would have surfaced this on its own. No proactive check exists for this class of drift; worth a glance at `docker network ls` next time a service is removed.
