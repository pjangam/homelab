# Tailscale sidecars

Services that get their **own tailnet hostname** instead of a path under
`xero.<tailnet>`, each as a `tailscale/tailscale` sidecar container sharing the
`x-tailscale-sidecar` anchor in `docker-compose.yml`.

Why a sidecar rather than a Caddy handle: these sidecars **provision and
auto-renew their own certificates**, unlike the static files in `certs/` that
[`projects/certs-backup/renew_certs.sh`](../../projects/certs-backup/README.md)
has to keep alive. And some apps cannot run under a sub-path at all - ntfy
being the one that forced the pattern (upstream declined sub-path support,
binwiederhier/ntfy#1009).

- [`serve-config.template.json`](serve-config.template.json) - the shape they
  all share: terminate HTTPS on :443 with a Tailscale cert, proxy `/` to one
  upstream. The upstream is the only thing that differs, so it is the only
  parameter. Render with
  [`tools/network/render_ts_serve_config.sh`](../../tools/network/README.md).
- `ha/`, `ntfy/`, `photos/` - the rendered configs in use. `albums/` is
  gitignored: it carries the secret album path.

**Gotchas that have bitten:** these need `TS_AUTHKEY`, because `containerboot`
hard-deadlines `tailscale up` at 60s and an interactive login loses that race,
restarts, and leaves an orphan machine record squatting the DNS name. And a
sidecar's `hostname:` **shadows the service of the same name in Docker DNS** -
which is why ntfy's container is reached as `ntfy-server`. Do not "simplify"
that back.
