# notify

The two shared alert senders every watchdog and check in this repo calls, plus
the ntfy account setup behind one of them. Routing, topics and ACLs are
documented in [`services/ntfy/README.md`](../../services/ntfy/README.md).

| | |
|---|---|
| `send_email.sh` | source it, then `send_email "subject" "body"`. Gmail SMTP; needs `GMAIL_USER` / `GMAIL_APP_PASSWORD` from `.env.healthcheck` |
| `push_ntfy.sh` | source it, then `push_ntfy "title" "body" [priority] [tags]`. Publishes to `homelab-health` |
| `setup_ntfy_users.sh` | creates the ntfy users, ACLs and publish tokens (ntfy has no web UI for this). Idempotent |
| `verify_ntfy_topics.sh` | proves the topic split actually enforces - each publisher can post to its own topic and **cannot** post to the others' |
| `ntfy_history.py` | what ntfy really sent on a topic, from the container's message cache - to check whether an alert fired, and when |

`push_ntfy` is a **silent no-op when `NTFY_CLAWLIGHT_TOKEN` is unset**, so
scripts that also run on machines without ntfy keep working, and it never fails
its caller: an alert that cannot be sent must not take down the watchdog
sending it.
