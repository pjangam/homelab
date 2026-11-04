# Mosquitto (MQTT broker)

The bus every local integration talks over: the white-noise and volume
bridges, the GPIO buttons, pi-health, xero-stats, the healthcheck publisher and
the MirAIe AC bridge on the Pi all publish here, and Home Assistant discovers
its entities from it.

One file: [`mosquitto.conf`](mosquitto.conf). It listens on 1883 with
`allow_anonymous false` - authentication has been required since the
2026-08-23 security pass, so every client needs the `homelab` user's
credentials (`.env.mqtt`, and Vaultwarden as "Mosquitto MQTT"). The password
file and the log directory are gitignored.

Two things worth knowing before debugging a client:

- **Node-RED is not on this Docker network** any more (it moved to the Pi), so
  it reaches the broker at xero's LAN address, not the `mosquitto` container
  name.
- Several topics are **retained** (`whitenoise/state`, the health and stats
  JSON) and several deliberately are **not** (the AC's state and availability,
  button presses). Subscribing to a non-retained topic while nothing is
  happening shows silence whether the publisher is healthy or dead - see
  [`projects/miraie-ac/README.md`](../../projects/miraie-ac/README.md) for what
  that cost once.
