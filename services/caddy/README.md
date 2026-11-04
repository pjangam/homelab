# Caddy (reverse proxy, TLS)

The single HTTPS front door for everything served off xero's own tailnet name.
One file: [`Caddyfile`](Caddyfile).

It runs with **`auto_https off`** - Caddy renews nothing here. The certificate
for `xero.<tailnet>` is a static pair of files in the gitignored `certs/`,
renewed by
[`projects/certs-backup/renew_certs.sh`](../../projects/certs-backup/README.md).
That is the only thing keeping it alive, which is why it has its own
independent expiry check.

Paths under `xero.<tailnet>`: `/projects`, `/clawlight`, `/wishlist`,
`/endpoints`, `/grafana`, and a catch-all to Vaultwarden. Grafana also gets
port `3443` at its own root, for mobile apps that keep only `scheme://host:port`.
The full list of what is served where is
[`projects/endpoints/endpoints.toml`](../../projects/endpoints/README.md) -
add an entry there when a handle is added here.

Two shapes that look like duplication but are not: most blocks keep the path
prefix intact (the app behind them routes on it), while `/endpoints` strips it
because there is no app behind it, only `index.html` on disk. `ha` and `ntfy`
do **not** go through Caddy at all - they have their own tailscale sidecars
with self-renewing certs (see [`services/tailscale/`](../tailscale/README.md)).
