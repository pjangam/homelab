#!/usr/bin/env bash
# Let tailscaled manage /etc/resolv.conf again. Run on xero with sudo.
#
# THE BUG
# new_machine_setup.sh disables systemd-resolved because it squats on port 53
# and Pi-hole can't bind while it's there. But the systemd-resolved *package*
# also ships /usr/sbin/resolvconf as a symlink to resolvectl, and that symlink
# stays behind. tailscaled probes for a resolvconf binary, finds it, and picks
# resolvconf mode - then every DNS update fails:
#
#   error running command path="/usr/sbin/resolvconf" ... exitCode=1
#   Failed to resolve interface "tailscale": No such device
#
# resolvectl demands a real kernel interface; tailscale passes the logical name
# "tailscale" (the interface is tailscale0). So the shim could never work here,
# and with systemd-resolved disabled it has nothing to talk to anyway.
#
# Nothing looked broken because /etc/resolv.conf already held the right
# contents - but nothing was maintaining them. A reboot, a link change, or a
# rebuild would have left this host with a stale resolver and no owner. Same
# class of drift as 20a64ce: config that looks handled while the real
# dependency is elsewhere.
#
# THE FIX
# Divert the shim so tailscaled falls through to its "direct" manager and
# writes /etc/resolv.conf itself. dpkg-divert (not rm) so a systemd upgrade
# doesn't silently restore it, and so it's cleanly reversible.
set -euo pipefail

SHIM=/usr/sbin/resolvconf
BACKUP=/etc/resolv.conf.before-tailscale-fix

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

echo "=== before ==="
ls -l "$SHIM" 2>/dev/null || echo "  $SHIM already absent"
echo "--- resolv.conf ---"
cat /etc/resolv.conf
echo "--- tailscale health ---"
tailscale status 2>&1 | sed -n '/Health check/,$p' | head -5 || true

echo
echo "=== backing up resolv.conf to $BACKUP ==="
cp -a /etc/resolv.conf "$BACKUP"

echo
echo "=== diverting the shim ==="
if dpkg-divert --list | grep -q "$SHIM"; then
  echo "  already diverted, nothing to do"
else
  dpkg-divert --local --rename --add "$SHIM"
fi

echo
echo "=== restarting tailscaled so it re-picks a DNS manager ==="
systemctl restart tailscaled

# Wait for tailscaled to come back and rewrite resolv.conf, rather than
# assuming a fixed sleep is long enough.
for _ in $(seq 30); do
  tailscale status >/dev/null 2>&1 && break
  sleep 1
done

echo
echo "=== after ==="
echo "--- resolv.conf (should still point at MagicDNS) ---"
cat /etc/resolv.conf
echo "--- tailscale health (the resolvconf error should be gone) ---"
if tailscale status 2>&1 | grep -q "Health check"; then
  tailscale status 2>&1 | sed -n '/Health check/,$p'
else
  echo "  no health warnings"
fi
echo "--- which manager did it pick? ---"
journalctl -u tailscaled --since "2 min ago" --no-pager 2>/dev/null \
  | grep -iE "dns: using|resolvconf|OScfg" | tail -5 || true

echo
echo "=== proof DNS still resolves and still lands in Pi-hole ==="
MARKER="resolvconf-fix-$RANDOM.example.com"
dig +time=4 +tries=1 "$MARKER" >/dev/null 2>&1 || true
dig +time=4 +tries=1 google.com +short | head -2
sleep 2
if docker exec pihole grep -q "$MARKER" /var/log/pihole/pihole.log 2>/dev/null; then
  echo "  marker $MARKER reached Pi-hole - path intact"
else
  echo "  WARNING: marker $MARKER did NOT reach Pi-hole - check before walking away"
fi

echo
echo "Rollback if anything looks wrong:"
echo "  sudo dpkg-divert --local --rename --remove $SHIM"
echo "  sudo cp -a $BACKUP /etc/resolv.conf && sudo systemctl restart tailscaled"
