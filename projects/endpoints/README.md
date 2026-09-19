# Endpoint index

One page listing every endpoint this homelab serves, at
`https://xero.<tailnet>/endpoints/`. Open one bookmark, click the thing.

PROJECTS.md entry: **"One page listing every endpoint we serve"**.

## What it is

Two files and no container:

| File | What it is |
|---|---|
| `endpoints.toml` | The list. Service, protocol, host, port, what speaks it, and a copyable connection string for the ones a browser cannot open. |
| `render_endpoints.py` | Renders `site/index.html` from it. Standard library only. |
| `site/` | The rendered page. **Gitignored** - see below. |

Caddy serves `site/` straight off disk (the `/endpoints` handle in
`services/caddy/Caddyfile`, bind-mounted read-only by the `caddy` service in
`docker-compose.yml`). No new container, no RAM, nothing to update.

## Editing it

**Edit `endpoints.toml`, never `site/index.html`.** The page is generated; a
hand-edit to it is lost on the next render. Then:

```sh
projects/endpoints/render_endpoints.py     # on xero, where .env lives
```

Caddy picks up the new file immediately - it is read off disk per request, so
there is nothing to reload or restart.

Away from xero, pass the suffix in rather than inventing one:

```sh
TAILNET_SUFFIX=example.ts.net projects/endpoints/render_endpoints.py
```

## Why the rendered page is not in git

`endpoints.toml` writes `{tailnet}` wherever the tailnet suffix belongs, and
the renderer substitutes the real value from `.env`. So the source list is safe
to track and the rendered page is not - `site/` is gitignored, and a fresh
clone has nothing there until the render is run. **If `/endpoints` 404s on a
machine, that is the reason.**

The same split, and the same reason, as `services/tailscale/`'s template. The
difference is that its rendered output carries no secret, so that one is
tracked and this one is not.

## What belongs in the list and what does not

**In:** service names, protocols, ports, the LAN addresses `docker-compose.yml`
already publishes in the clear, and which process talks to what. That is the
exposure the repo already has.

**Out:** credentials, and the tailnet suffix (use the placeholder). The private
inventory - full device specs, which panels have no auth in front of them -
stays in the gitignored `docs/hardware.md`. This page is the opposite of that
file: the handful of things a person actually clicks, safe to serve behind
Tailscale. Keep them apart.

## Why it does not show up/down

Deliberately. `projects/healthcheck/healthcheck.sh` already publishes per-check
state to MQTT every 15 minutes and Home Assistant renders it on the **Stats**
dashboard. This page is the index; Stats is the health view. Two
half-dashboards would be worse than either, which is also why this stayed a
static page rather than becoming gethomepage or Dashy - those are Node apps in
the 100-200MB range, and their draw is precisely the status half that already
exists.

## Keeping it honest

Nothing enforces that this list matches reality. The three sources it was
written from, and the ones to re-read when something moves:

- `docker-compose.yml` - published ports for everything containerised
- `services/caddy/Caddyfile` - what is behind `xero.<tailnet>`
- `docs/hardware.md` (gitignored) - the systemd units, the Pi, the ESP32

When a port moves or a service arrives, `endpoints.toml` is part of that work,
the same way `docs/hardware.md` is - that is a rule in `CLAUDE.md`, not just
good manners. The check that backs it up:

```sh
tools/repo-tools/check_endpoints_toml.sh
```

It lists every host port `docker-compose.yml` publishes and every path the
Caddyfile handles that `endpoints.toml` does not mention, and exits non-zero if
anything is missing. It reads the tracked config rather than the live machines
(unlike `check_hardware_md.sh`), so it runs on any clone with no `.env` and no
ssh - and so it **cannot see** the systemd `--user` services, the Pi or the
ESP32. clawlight on 8126, Node-RED on the Pi and the WLED UDP feeds are all on
the page and invisible to it. Adding one of those is on you.
