# ntfy (self-hosted push notifications)


Native push to the phone for clawlight's "needs your input" state and for
infrastructure health alerts, self-hosted so message content and credentials
stay on `xero`.

**Two topics, deliberately separate.** `clawlight` carries agent-status pings;
`homelab-health` carries `healthcheck.sh` and watchdog alerts. They were one
topic until 2026-09-11, which meant muting "an agent needs input" while
working also muted "ZFS is degraded" - the two want opposite attention.

**Reachable at** `https://ntfy.<tailnet>` (tailnet only). It is **not** behind
Caddy: ntfy cannot run under a sub-path (upstream declined it,
binwiederhier/ntfy#1009), so it gets its own tailnet hostname from the
`ntfy-tailscale` sidecar - the same pattern as `ha`, shared via the
`x-tailscale-sidecar` anchor in `docker-compose.yml`. The sidecar provisions and
**auto-renews** its own cert, unlike the static files in `certs/`.

The ntfy container itself listens on `127.0.0.1:8127` only - never the LAN - so
basic-auth credentials are not sent in plaintext anywhere. Local publishers
(clawlight) use that loopback port; the phone uses the HTTPS tailnet name.

## Accounts

`auth-default-access` is `deny-all`; nothing is readable or writable without an
explicit grant.

| user | `clawlight` | `homelab-health` | used by |
|---|---|---|---|
| `pramod` | read-write | read-write | the phone app / web UI |
| `clawlight` | **write-only**, token | *none* | `clawlight/server.py` |
| `healthcheck` | *none* | **write-only**, token | `tools/notify/push_ntfy.sh` |

The split is deliberate twice over: a leaked publish token cannot read
notification history, and neither publisher can post to the other's topic. No
rule is denial under `deny-all`, so there is nothing to revoke. Verify with:

```bash
./tools/notify/verify_ntfy_topics.sh   # proves both directions are refused
```
Credentials live in gitignored `.env.ntfy` (mode 600), created by:

```bash
./tools/notify/setup_ntfy_users.sh   # idempotent, safe to re-run
```

## Phone setup

Install the ntfy app, then **Add server** → `https://ntfy.<tailnet>`, log in as
`pramod` with `NTFY_ADMIN_PASSWORD` from `.env.ntfy`, and subscribe to **both
`clawlight` and `homelab-health`**. Logging in grants access but does not
subscribe you - an unsubscribed topic means those pushes silently land
nowhere, which for `homelab-health` means no alerts at all. Tailscale must be up on the phone to *fetch* message content: the
APNs wake-up relayed via `ntfy.sh` is contentless by design (it carries only a
message ID and a SHA256 of the topic URL - never the message body), so without
the tailnet the notification arrives generic.

## What alerts here

| source | notifies via |
|---|---|
| `clawlight/server.py` | ntfy (edge-triggered on `waiting`) |
| `projects/healthcheck/healthcheck.sh` | email + ntfy — containers, units, ZFS, disk, backups, **cert expiry**, **MirAIe AC** |
| `projects/power-watchdog/watchdog_power.sh` | email + ntfy — carrier lost/restored |
| `projects/certs-backup/renew_certs.sh` | ntfy on failure |
| `watchtower` | ntfy (`homelab-updates`, low priority) + an HA notification |

The tinxy and spotifyd watchdogs, and the backup scripts, do not alert directly
— they surface through `healthcheck.sh`, which checks their state and freshness.

**Watchtower publishes to its own topic, `homelab-updates`, at priority 2 (low).**
A container updating is informational, not a fault, so it must be mutable
without muting `homelab-health`. It posts to ntfy and HA in one shot, and
because Watchtower renders its template **once** and sends that same body to
every destination, the body is shaped to satisfy both: ntfy parses
`{topic,title,priority,tags,message}` as a native JSON publish and shows the
readable `message`, while HA ignores those and reads the structured
`updated`/`failed` arrays. See `WATCHTOWER_NOTIFICATION_TEMPLATE` in
`docker-compose.yml`. On the phone it reads:

```
Homelab: 1 container(s) updated
wt-test (alpine:latest): 6baf43584bcb -> 28bd5fe8b56d
```

Those are image IDs, not versions — Docker has no notion of a version, and
moving tags like `:stable` are unchanged across an update, so the short image
ID is the only thing that actually identifies what changed.

ntfy is reached at `ntfy-server` on the compose network (not `ntfy` — that
name resolves to the tailscale sidecar), so nothing extra is published on the
host. The write-only token comes from `tools/notify/setup_ntfy_users.sh`, which
also mirrors it into `.env` because that is the only env file docker compose
auto-loads.

## Adding another alert source

Source the shared helper (companion to `tools/notify/send_email.sh`):

```bash
[ -f "$SCRIPT_DIR/.env.ntfy" ] && { set -a; . "$SCRIPT_DIR/.env.ntfy"; set +a; }
source "$SCRIPT_DIR/tools/notify/push_ntfy.sh"

push_ntfy "title" "body" [priority] [tags]    # priority defaults 4, tags "warning"
```

It is a silent no-op when `NTFY_CLAWLIGHT_TOKEN` is unset, so scripts that also
run on machines without ntfy keep working unchanged, and it never fails the
caller — an alert that cannot be sent must not take down the watchdog sending it.

Give a genuinely separate alert its own topic and ACL rather than reusing
`clawlight`, so each can be muted independently on the phone.

**Caveat for power alerts:** a `lost carrier` event usually means the switch or
router lost power too, so neither the push nor the email can leave the house
until the link returns. It is still sent — it costs nothing and does get through
when the loss is upstream of the LAN rather than a whole-house outage.

## Gotchas

- These tailscale sidecars need `TS_AUTHKEY`. `containerboot` hard-deadlines
  `tailscale up` at 60s, so interactive login usually loses the race, restarts,
  and leaves an orphan machine record squatting the DNS name.
- The sidecar's `hostname: ntfy` shadows the `ntfy` service in Docker DNS, hence
  the `ntfy-server` alias the serve config proxies to. Do not "simplify" it back.
- `config.js` showing `"base_url": ""` is normal - the web app uses relative URLs.
