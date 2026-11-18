# Expose Home Assistant via Tailscale with its own clean hostname
**Status:** Done

**Why:** Caddy only reverse-proxied Vaultwarden (`xero.{$TAILNET_SUFFIX}`); HA is the service most worth reaching remotely and already has its own login. Path-based routing (`/ha`) was rejected since HA's frontend/plugins assume a root-relative path.
**Outcome:** shipped 2026-08-26 - a `tailscale/tailscale` sidecar gives HA its own tailnet hostname `ha`, and `https://ha.{$TAILNET_SUFFIX}` was confirmed working from inside the home network; LAN access unaffected, Caddy untouched.
- Left open: **not yet tested from outside the home network / off Wi-Fi** - should work automatically over the tailnet like any other Tailscale node, but hasn't been verified.
- Left open, low priority: remove the stale offline `homeassistant` device (100.112.159.113, leftover from the Pi's old HAOS days) from the Tailscale admin console.

#### Design
`ha-tailscale` in `docker-compose.yml` uses userspace networking - xero's own native `tailscaled` rules out host-mode. It joins the tailnet under its own hostname `ha`, and `tailscale serve` (via `TS_SERVE_CONFIG` → `services/tailscale/ha/serve-config.json`) terminates TLS and reverse-proxies to HA at `192.168.1.123:8123`.

#### Gotchas
- `serve-config.json` gotcha: `AllowFunnel` is keyed per host:port, not a plain bool - a top-level `"AllowFunnel": false` crash-looped the container. Fix: omit it entirely (default off).
- Bigger gotcha: HA rejected the proxied requests with 400 (`X-Forwarded-For header from an untrusted proxy 172.18.0.7`). HA's proxy-trust list is **not** read from `configuration.yaml` once migrated - newer HA stores it in `.storage/http` (`yaml_migration_done: true`, this instance migrated 2026-08-09 with `trusted_proxies: ["100.64.0.0/10"]`, apparently pre-staged for this project). A YAML `http:` block post-migration does nothing useful and, if malformed, fails the entire `http` integration at boot - which cascades into recovery mode (frontend/auth/api/mqtt all depend on it) and is what happened mid-session. The real fix: edit `/config/.storage/http`'s `stable.trusted_proxies` list directly (JSON) - final value `["100.64.0.0/10", "172.18.0.0/16"]`, adding the docker-compose bridge subnet the sidecar's requests originate from.
- `configuration.yaml` and `.storage/http` are normally root-owned (privileged HA container); user chowned just those two files to themselves so edits don't need `sudo` each time - everything else in `HOMEASSISTANT_CONFIG` (secrets, tokens, DB) is still root-owned.

#### Log
- 2026-08-09: this HA instance migrated its `http` config to `.storage/http` with `trusted_proxies: ["100.64.0.0/10"]`.
- 2026-08-26: sidecar shipped, the two gotchas above hit and fixed, `https://ha.{$TAILNET_SUFFIX}` confirmed working from the home network.
