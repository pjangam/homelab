# Vaultwarden

The password manager, and the store every other secret in this repo points at
("check Vaultwarden" in a setup doc means here). It is a container defined in
`docker-compose.yml` with no config file of its own - its settings are the
environment there, and its data is the gitignored `vw-data/` at the repo root,
backed up encrypted by
[`projects/certs-backup/backup_vaultwarden.sh`](../../projects/certs-backup/README.md).

Served at `https://xero.<tailnet>/` (the Caddyfile's catch-all handle), and it
**stays** on that hostname rather than moving to its own tailscale sidecar:
`DOMAIN` is pinned to it, and changing it would invalidate every passkey /
WebAuthn origin. That is why the cert renewal in `projects/certs-backup/` is
permanent infrastructure.

## Signups


Signups are currently **disabled** (`SIGNUPS_ALLOWED: "false"` in `docker-compose.yml`). To allow a new account, temporarily set it to `"true"`, run `sudo docker compose up -d vaultwarden`, create the account, then set it back to `"false"`.
