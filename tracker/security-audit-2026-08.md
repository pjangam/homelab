# Network/security audit across all containers (Mosquitto auth, SSH, rpcbind)
**Status:** Done

**Why:** triggered by moving Node-RED's admin editor from localhost-only to reachable over Wi-Fi (see the Pi load migration entry) - prompted a full re-evaluation of network exposure and auth across every host/service, not just Node-RED.
**Outcome:** shipped 2026-08-23 - Mosquitto auth with every client rewired, Node-RED `adminAuth`, Pi SSH key-only, `rpcbind` disabled on the Pi, credentials in Vaultwarden.
- **Not changed (accepted status quo, not asked for):** Caddy only reverse-proxies Vaultwarden - HA, Pi-hole admin, and Node-RED remain plain HTTP on the LAN.

#### What shipped
- **Mosquitto auth.** `allow_anonymous false` + `password_file`, user `homelab`. Rewired every client: Node-RED's `ha-miraie-ac` node (via its "credentials" sub-object, not flat fields - flat fields are silently accepted as ordinary config and never reach the credential store, a real gotcha hit live), Home Assistant's own MQTT integration (patched directly into `.storage/core.config_entries` via `docker exec -u root homeassistant` since that file is root-owned and no local sudo was available - backed up first), `white-noise-mqtt.py`, `volume-mqtt.py`, `publish_healthcheck_mqtt.py` (all via a new gitignored `.env.mqtt` + `EnvironmentFile=` in their systemd units / sourced in `projects/healthcheck/healthcheck.sh`). Verified end-to-end post-rollout: HA's MQTT client connects and stays connected (checked via `mosquitto`'s own log, since it logs to a file not stdout), both Python bridges show `available: online`, the cron healthcheck publisher's MQTT step confirmed with a live triggered run (not just reasoned-correct), and Node-RED's local-broker + MirAIe-cloud connections both confirmed ESTABLISHED at the socket level.
- **Node-RED `adminAuth`** enabled on the Pi's editor (username `pramod`, bcrypt hash) - it was previously unauthenticated, fine when only reachable from `xero` itself, not once exposed over the LAN post-migration.
- **Pi SSH password auth disabled** (`PasswordAuthentication no` in `/etc/ssh/sshd_config`, confirmed reloaded via `journalctl` showing `SIGHUP`/reread at the same timestamp as the edit) - key-only access from here on.
- **`rpcbind` disabled** on the Pi (`systemctl disable --now`) - unused attack surface.
- Credentials (Node-RED admin, Mosquitto MQTT) pushed into Vaultwarden via `bw` CLI (user ran `bw unlock` themselves, shared only the session token - master password never seen by Claude) and deleted from scratchpad.
