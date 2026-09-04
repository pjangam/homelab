# 2026-09-04: TLS cert renewal silently broken for 3 months — 5 days from expiry

**Symptom:** none. That is the point of this report. Everything worked normally right up until it was noticed by accident, while adding an unrelated service (self-hosted ntfy). `certs/xero.<tailnet>.crt` was valid until **Sep 10 2026** and its mtime was **Jun 12** — the renewal cron had produced no effect for three months. Discovered Sep 4, five days before Vaultwarden, projects-ui and clawlight would all have started serving an expired certificate.

**The job that was supposed to do it:**
```cron
0 4 1 * * sudo tailscale cert --cert-file .../certs/xero.<tailnet>.crt \
                              --key-file  .../certs/xero.<tailnet>.key xero.<tailnet> \
          && sudo chown pramod:pramod .../certs/* \
          && sudo docker kill --signal=USR1 caddy >> backup.log 2>&1
```

**Root cause — three independent bugs, any one of which was enough:**

1. **`sudo` can never work from cron here.** Sudoers grants `NOPASSWD` for exactly one command:
   ```
   (root) NOPASSWD: /usr/sbin/shutdown -h now
   ```
   Everything else needs a password, and cron has no TTY. The job died at its first command every month since June.

2. **The failure was invisible by construction.** `>> backup.log 2>&1` binds only to the **last** command of an `&&` chain — `sudo docker kill`. That command never ran, because the chain died at step one, so nothing was ever written to the log. The error went to local cron mail, which nothing reads. `backup.log` shows no cert lines at all on Jul 1, Aug 1 or Sep 1.

3. **`tailscale cert` would not have renewed even if sudo had worked.** Without `--min-validity`, it only guarantees the returned cert is *not already expired* — a cert with 5 days left is "fine" and it hands back the cached copy. Confirmed empirically: the first fixed run rewrote the files and reported success while `notAfter` stayed `Sep 10`. The flag's own help says it: *"the output certificate is never expired if this flag is unset or 0, but the lifetime may vary."*

**Also wrong: the schedule.** Monthly on the 1st, against a 90-day cert expiring Sep 10, meant Sep 1 was the single remaining opportunity. A monthly job that fails has no retry before expiry.

**Diagnosis:**
```bash
openssl x509 -in certs/xero.<tailnet>.crt -noout -enddate   # Sep 10, mtime Jun 12
sudo -n true                                                # "a password is required"
sudo -n -l                                                  # NOPASSWD only for shutdown
tailscale cert --cert-file /tmp/probe.crt ... <host>        # "Access denied: cert access denied"
```
Note `tailscale cert` printed `Access denied` and still **exited 0** — so exit status alone is not a usable success signal.

**Fixes applied:**
- `sudo tailscale set --operator=pramod` (once, manually) — grants the user cert access, so renewal runs unprivileged and needs no sudoers exception. This is Tailscale's own suggested remedy, printed in the access-denied message.
- Replaced the inline crontab entry with `cron/renew_certs.sh`, which:
  - passes `--min-validity 720h` (30 days; Go duration syntax has **no `d` unit** — `30d` is a parse error),
  - writes to temp files and validates the cert parses and has the right CN before installing, so a bad issuance cannot replace a working cert,
  - does not trust `tailscale cert`'s exit status, checking the output file instead,
  - logs every run to `cert-renew.log`,
  - **pushes a priority-5 ntfy alert on any failure**, and additionally if the cert still has under 21 days left after a supposedly successful run.
- Rescheduled **weekly** (Sundays 05:00, offset from watchtower's 04:00 container restarts) so a single failure has several retries before expiry.
- Renewed the cert: `5d -> 89d`, now valid to **Dec 3 2026**. Verified Caddy serves it and that projects-ui, clawlight and Vaultwarden all still return 200.

**Prevention / what to remember:**
- A cron job whose output goes nowhere is not monitored, it is merely quiet. Both new alerts fired for real during this fix (`invalid value "30d"`, then `still only has 5d left`) and both reached the phone — the alerting is proven by actual failures, not a synthetic test.
- Do not put `sudo` in this user's crontab. Nothing but `shutdown` will run.
- `--min-validity` is mandatory for proactive renewal; without it `tailscale cert` is a no-op until the cert has effectively lapsed.
- The `ha` and `ntfy` hostnames are **immune** to all of this: their tailscale sidecars provision and renew certs internally, with no cron, no sudo and no files in `certs/`. Migrating Vaultwarden and projects-ui to that pattern would retire this script entirely — the strategic fix, deliberately not attempted five days before an expiry.
