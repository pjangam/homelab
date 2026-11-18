# One page listing every endpoint we serve
**Status:** Done

**Why:** there was no single place answering "what is running here and where do I open it" (noted 2026-09-19). The endpoints were scattered - some behind Caddy on `xero.<tailnet>`, some on their own tailnet hostnames, some plain LAN ports, one on the Pi, one on an ESP32 - and the only way to find one was to remember it or grep the repo.
**Outcome:** **shipped 2026-09-19 at `https://xero.<tailnet>/endpoints/`. 23 endpoints, 5 groups.** Option (A) from the original entry - a static page served by Caddy - and it stayed there: no new container, no RAM. Listing a service in `endpoints.toml` is now part of the definition of done in `CLAUDE.md`.
- Deployed after the write-up: the Caddyfile change, the compose mount and the first `render_endpoints.py` run landed on xero (`git pull`, render, `docker compose up -d caddy`); Caddy serves the rendered page (checked 2026-10-14).
- Left open: nothing enforces that the list matches reality; when a port moves, `endpoints.toml` is part of that work the way `docs/hardware.md` is.
- Left open: `tools/diagrams/render.sh` uses `realpath -m`, which is GNU-only, so it cannot run on a Mac (see Notes).

#### What it is

`projects/endpoints/endpoints.toml` is the single machine-readable list (service, protocol, host, port, what speaks it), `render_endpoints.py` renders it to `site/index.html`, and Caddy's new `/endpoints` handle serves that directory off disk via a read-only bind mount. Setup and editing rules: `projects/endpoints/README.md`.

**It covers more than HTTP, which was the point.** Web pages are the easy half; the ones that bite are MQTT (the broker *and* its topics), DNS, SMB, SSH, the WoL magic packet, and WLED's two UDP feeds. Anything a browser cannot open carries a **copyable connection string** instead of a link - that field is what stops the `mosquitto_sub` line and the DRGB packet layout being re-derived from `docker-compose.yml` every time.

#### Design decisions worth keeping

- **TOML, not YAML or JSON.** `tomllib` is in the standard library from Python 3.11 (xero is on 3.12), **pyyaml is not installed here**, and a links page does not justify a dependency. JSON was out because the data file wanted comments as much as any other config in this repo.
- **The rendered page is gitignored, the list is not.** `endpoints.toml` writes `{tailnet}` wherever the tailnet suffix belongs and the renderer substitutes it from `.env`, so the source stays safe to track and the output never enters git. Same split as `services/tailscale/`'s template - the difference is that one's output carries no secret, so it *is* tracked. **Consequence: a fresh clone 404s on `/endpoints` until the render is run.** That is documented in three places (the Caddyfile block, the compose mount, the README) because it is the one surprise this design buys.
- **`uri strip_prefix` plus a trailing-slash redirect**, unlike the `/projects` and `/clawlight` handles which keep their prefix intact. There is no app behind this one to route on the prefix - just an `index.html` - and without the redirect `/endpoints` strips to an empty path that `file_server` has no `/` to resolve against. The same redirect `projects-ui`'s nginx.conf does, for the same reason.
- **No up/down on it, deliberately.** `healthcheck.sh` already publishes per-check state to MQTT and HA renders it on **Stats**. This page is the index; Stats is the health view. That decision is what kept it a static page rather than gethomepage or Dashy - those are Node apps in the 100-200MB range whose draw is precisely the status half that already exists, on a box where Immich is parked for exactly that reason.
- **Web links open in a new tab (2026-09-19, after using it).** The page is a jumping-off point on a bookmark, so navigating away in place means coming back through history every time. Only `http(s)` gets `target=_blank`: `smb://` and `ssh://` are handed to the OS rather than navigated to, so the page is never left behind, and `_blank` on those opens a blank tab that never fills. `rel=noopener` with it.
- **Kept apart from the private inventory on purpose.** Ports, protocols and the LAN addresses `docker-compose.yml` already publishes in the clear go on the page; credentials, full device specs and which panels lack auth stay in the gitignored `docs/hardware.md`.

#### Part of the definition of done

A links page that nobody updates is worse than no page, so closing any project that serves something requires listing it in `endpoints.toml` first - a new rule in `CLAUDE.md`, deliberately shaped like the `docs/hardware.md` rule next to it, with `tools/repo-tools/check_endpoints_toml.sh` as the check. That script lists every host port `docker-compose.yml` publishes and every Caddyfile path the TOML does not mention. It reads the tracked config rather than the live machines, so it runs on any clone with no `.env` and no ssh - and so it is blind to the systemd `--user` units (clawlight on 8126), the Pi and the ESP32, which is called out in its header, its README row and the rule itself.

#### Verification

`caddy adapt` on the real Caddyfile produces the expected route order (`/projects` -> `/clawlight` -> `/endpoints` -> Vaultwarden catch-all), and the page was screenshotted at desktop and phone widths in light and dark via `tools/diagrams/render.sh`'s Playwright image. The check script was negative-tested (a fake loopback-bound `127.0.0.1:9999:80` and a fake `/grafana` handle), which is what caught its first version silently reading `1` out of `127.0.0.1:8127:80` and never checking ntfy's port at all.

#### Notes worth keeping

**One portability snag found on the way, not fixed:** `tools/diagrams/render.sh` uses `realpath -m`, which is GNU-only, so it cannot run on a Mac. Left alone as unrelated to this work - the underlying docker command was run by hand instead.

#### Log
- 2026-09-19: need noted; page built and verified (`caddy adapt`, screenshots, check script negative-tested); web links changed to open in a new tab after using it; the endpoints rule added to `CLAUDE.md` at the user's ask.
