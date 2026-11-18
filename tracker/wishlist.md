# Wishlist page (expensive purchases)
**Status:** Done
**Priority:** P3

#### Open items
- Nothing open.

**Why:** keep track of the big-ticket things to buy, with rough prices, and decide what to buy when. Replaces the Google Sheet idea; kept server side so the phone and laptop see the same list.
**State:** live on xero since 2026-11-04 as the `wishlist` container (port 8128, Caddy `/wishlist`). See `projects/wishlist/README.md`. The list has 7 items (2026-11-06). **No off-box backup, by choice** (user, 2026-11-06): local only, plus the `.bak` of the previous save.

#### Design
- A stdlib Python server and one plain-JS page. Storage is one JSON file (`projects/wishlist/data/wishlist.json`, gitignored), rewritten atomically with a `.bak` of the previous save. No database: it holds tens of items, and the only database already running (Immich's Postgres) would tie this list to Immich's container. Python rather than Node for the server because xero has no Node, and clawlight's server is the same pattern.
- Each save carries the version it was loaded at; a stale save gets a 409 and the page reloads, so two devices can't silently overwrite each other.
- Order on the page = priority. Running total (Σ) per item; with a monthly amount set, each item shows the month it becomes affordable buying top-down.

#### Log
- 2026-11-04: built and deployed. API checked with curl (save, stale-version 409, nameless item 400) and through Caddy over the tailnet (200). Added to `endpoints.toml` (re-rendered) and to the xero entry in `docs/hardware.md`.
- 2026-11-04: page went blank (Caddy 502) minutes after deploy: `git pull --rebase` recreated `projects/wishlist/web/`, and the container's bind mount stayed on the deleted copy. Now mounts the repo root read-only, like projects-ui.
- 2026-11-06: Dropbox backup of `wishlist.json` dropped (user): local only is enough.
- 2026-11-17: marked Done (user). The list is entered and in use.
