# Certificates and offsite backups

Two jobs that happen to share a folder because they share a shape: both run
unattended from xero's crontab, both are useless if they fail silently, and
both therefore alert. Nothing here is interactive.

## Backups (rclone to Dropbox)

| script | what it copies | encrypted |
|---|---|---|
| `backup_vaultwarden.sh` | `vw-data/` | GPG |
| `backup_documents.sh` | the `documents` SMB share, only when it changed | GPG |
| `backup_hardware_md.sh` | `docs/hardware.md` - gitignored, so xero's copy is the only one | GPG |
| `backup_homeassistant.sh` | HA's own backups (already encrypted by HA) | by HA |
| `backup_and_apt_update.sh` | `/etc`, package selections, crontabs, unit state, partition table - then `apt full-upgrade` | no |

All of them need `BACKUP_PASSPHRASE` (from `.env.backup`) and an rclone remote
named `backup`. They do not alert directly: `projects/healthcheck/healthcheck.sh`
checks their freshness, which is what catches a backup that stopped running.
`test_backup_restart_guard.sh` covers the restart guard.


## TLS certificates (Caddy-served names)

`xero.<tailnet>` is served by Caddy from static files in `certs/`, renewed by
`projects/certs-backup/renew_certs.sh` (Sundays 05:00). Caddy runs with `auto_https off`, so
nothing renews these on its own - the script is the only thing that does.

```bash
./projects/certs-backup/renew_certs.sh          # safe to run any time; a no-op unless <30d left
cat cert-renew.log             # every run is logged
```

It renews via `tailscale cert --min-validity 720h`, writes to temp files and
validates them before installing, and **pushes a priority-5 ntfy alert on any
failure** - see [`services/ntfy/README.md`](../../services/ntfy/README.md). That alerting exists because this
job failed silently for three months
(`docs/incidents/2026-09-04-tls-cert-renewal-silently-broken.md`).

Two things that will bite you if you edit it:
- **No `sudo`.** This user has `NOPASSWD` only for `shutdown`, so any `sudo` in
  cron fails with no TTY. Cert access comes from `tailscale set --operator=pramod`,
  run once.
- **`--min-validity` is mandatory.** Without it `tailscale cert` returns the
  cached cert until it has effectively expired. Use Go duration units (`720h`) -
  there is no `d` unit, and `30d` is a parse error.

## Independent expiry check

`renew_certs.sh` alerts when it *fails*, but it cannot alert if it never runs at
all - a removed crontab line, a deleted script, or a machine that was off every
Sunday are all indistinguishable from silence, and that is exactly the failure
that went unnoticed for three months. So `projects/certs-backup/check_certs.sh` checks expiry
independently, called from `healthcheck.sh` every 15 minutes, sharing no
machinery with the thing it is checking.

It warns below **21 days**: renewal runs weekly with a 30-day `--min-validity`,
so a cert can legitimately sit just under 30d for up to a week before the next
Sunday run - below 21d means renewal has missed at least one scheduled run plus
slack. Problems go to email *and* an ntfy push.

```bash
./projects/certs-backup/check_certs.sh                  # silent when healthy; exits 1 if not
./projects/certs-backup/test_cert_expiry_check.sh    # 8 cases against synthetic certs
```

The test drives the real script against generated certs (89d/30d/22d silent,
20d/5d warn, expired, missing dir, malformed) rather than re-implementing its
logic - its first version asserted silence against fixtures that had failed to
generate, and "passed" while testing nothing.

`ha.<tailnet>` and `ntfy.<tailnet>` do **not** use any of this - their tailscale
sidecars renew their own certs internally, with no cron and no files in `certs/`.

Vaultwarden and projects-ui deliberately **stay** under `xero.<tailnet>` rather
than moving to that pattern (decided 2026-09-05). Moving them would retire this
script, but Vaultwarden's `DOMAIN` is pinned to `https://xero.<tailnet>` - a new
hostname would invalidate passkey/WebAuthn origins and force every client to be
re-pointed. So the renewal and independent-check scripts above are **permanent
infrastructure, not a stopgap**.
