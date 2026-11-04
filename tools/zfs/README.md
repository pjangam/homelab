# zfs

`arc_max.sh` - set xero's ZFS ARC cap, live and across reboots, or print the
counters used to judge it. The cap was 1 GiB from the 8GB-stick days; see "Use
xero's spare RAM" in `PROJECTS.md` for why it is 8 GiB now.

```bash
tools/zfs/arc_max.sh stats       # no sudo needed
sudo tools/zfs/arc_max.sh set 8  # GiB; needs a real terminal for sudo
```
