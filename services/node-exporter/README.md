# node_exporter

Host metrics for Prometheus ([`services/prometheus/`](../prometheus/README.md)),
on both machines. xero's exporter is a service in `docker-compose.yml`; the Pi
has no compose file, so `deploy_pi.sh` (run **on xero**) creates its container
with one `docker run` - idempotent, re-run it to change version or flags. It
binds the Pi's LAN address only, never the tailnet: read-only metrics whose one
reader is Prometheus on xero.

`zpool_textfile.sh` fills the gap node_exporter cannot: it only sees
per-dataset statfs numbers, where each dataset's "size" is its own data plus
the shared free space and snapshots count nowhere - so no sum of them says how
full the pool really is. The script writes pool `used`/`avail` and each vdev's
read/write/checksum error counts for the textfile collector, from cron every
minute. Its output directory is gitignored.
