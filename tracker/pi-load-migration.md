# Move some load to the Raspberry Pi
**Status:** Done

**Why:** the `wol-sender` Pi previously only sent a boot-time magic packet to `xero` - a trivially light job for a whole Pi, real spare capacity going unused.
**Outcome:** Node-RED moved to the Pi (2026-08-22), its watchdog redesigned (2026-08-23), and the rollback volume on `xero` confirmed gone (2026-09-02). Vaultwarden was the only other live candidate and stays deliberately deprioritized to last resort (2026-08-20 decision, see git history) rather than an open action item - re-open only if real headroom pressure shows up on the Pi.

#### Constraint: no battery backup on the Pi
Identified along the way: the Pi has no battery backup (unlike `xero`, on the UPS), but the LAN/router stays up during an outage - so anything actively network-depended-on during an outage can't move here without the Pi also getting battery backup. Ruled out Pi-hole, Mosquitto, Caddy, and Home Assistant on those grounds. Also ruled out: Watchtower (can only manage the Pi's own containers via its local Docker socket, not `xero`'s), Samba (storage lives on `xero`'s ZFS pool, moving just the container adds a network round-trip or needs real separate storage on the Pi).

#### Log
- 2026-08-20: decided Vaultwarden stays deprioritized to last resort (see git history).
- 2026-08-22: Node-RED migrated - flows/credentials/Miraie AC config copied to the Pi, started via plain `docker run`, both required MQTT connections (local HA broker, MirAIe cloud broker) confirmed live at the socket level. Removed `node-red` from `xero`'s `docker-compose.yml`.
- 2026-08-23: watchdog fixed and redesigned - the Mosquitto-auth security pass broke `watchdog_nodered.sh` (no credentials passed), which surfaced a deeper pre-existing bug: its `AC_TOPIC` never matched what the `ha-miraie-ac` node actually publishes, and that data isn't retained anyway (only sent once per reconnect). Rewrote to check the container's own `/proc/net/tcp` for ESTABLISHED connections instead - independent of the AC's power state. Documented in `projects/miraie-ac/README.md` under "Node-RED Watchdog (MQTT bridge health)".
- 2026-09-02: closed out - the old `homelab_node-red-data` volume on `xero`, left as a rollback net, is confirmed gone (`docker volume ls` no longer lists it).
