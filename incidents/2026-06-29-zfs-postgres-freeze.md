# 2026-06-29: System freeze — SSH + display dead, Docker still accessible

**Symptom:** SSH unreachable, display blank, but Docker containers accessible on the network. Required hard power cycle to recover.

**Root cause:** `immich_postgres` was an orphaned container — Immich was commented out in `docker-compose.yml` but its containers were still running from a previous enable. Postgres got stuck in a ZFS I/O deadlock for ~55 hours (kernel soft lockup on CPU#3), eventually making SSH and display unresponsive. The kernel network stack stayed alive, so containers remained reachable.

**Diagnosis:**
```bash
journalctl -b -1 | grep "soft lockup"
# watchdog: BUG: soft lockup - CPU#3 stuck for 200169s! [postgres:24853]
```

**Fixes applied:**
- Removed orphaned containers: `docker compose down --remove-orphans && docker compose up -d`
- Added soft lockup panic so future lockups auto-reboot instead of hanging:
  ```bash
  echo "kernel.softlockup_panic=1" | sudo tee /etc/sysctl.d/99-softlockup.conf
  sudo sysctl -p /etc/sysctl.d/99-softlockup.conf
  ```

**Prevention:** After commenting out services in `docker-compose.yml`, always run `docker compose down --remove-orphans` — `docker compose up -d` alone does not stop containers removed from the file.
