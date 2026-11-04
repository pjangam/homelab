# Wishlist

A priority-ordered list of the expensive things to buy, each with a rough price.
It replaces the Google Sheet idea.

- Open it at `https://xero.<tailnet>/wishlist/`, or on the LAN at `http://192.168.1.123:8128/wishlist/` (that one has no TLS and no auth).
- The top of the list is what to buy first. Reorder with ⤒ / ↑ / ↓.
- **Σ** under each price is the running total down to that item: what you need to have spent to get that far down the list.
- Fill in **Can set aside per month** and each item also shows the month it becomes affordable, buying top-down.
- **Bought ✓** moves an item to the Bought section with today's date. **Undo bought** puts it back at the bottom of the list.

## How it works

- `server.py`: a stdlib-only Python server (no dependencies, no build). It serves the page and `GET`/`PUT /wishlist/api/list`.
- `web/index.html`: the whole page, plain JavaScript.
- `data/wishlist.json`: the list itself. It is **gitignored** and rewritten whole on every save, atomically. The previous version is kept as `wishlist.json.bak`.
- Every save carries the version it was loaded at. If another device saved in between, the server refuses the save (409) and the page reloads the latest copy instead of overwriting it.
- Runs as the `wishlist` container in `docker-compose.yml` (stock `python:3.13-alpine`, code mounted read-only). Caddy proxies `/wishlist` to `localhost:8128`.

## Run / redeploy

```sh
cd ~/code/homelab
docker compose up -d wishlist          # start, or pick up a compose change
docker restart wishlist                # after editing server.py (the page reloads on its own)
docker restart caddy                   # only after editing the Caddyfile
curl -s localhost:8128/wishlist/api/list   # check it's serving
```

## Undo a bad save

```sh
cd ~/code/homelab/projects/wishlist/data
cp wishlist.json.bak wishlist.json     # only the single previous save is kept
```
