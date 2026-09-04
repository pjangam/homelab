# wol-sender Pi - system units

Reference copies of the systemd units running on the wol-sender Pi
(`192.168.1.124`), taken verbatim from `/etc/systemd/system/`. Checked in so
the Pi's configuration is auditable from the repo - the Pi itself has no
persistent journal, so nothing about its past state can be recovered from the
device once it reboots.

These are **copies, not the source of truth**: systemd reads the files on the
Pi. `scripts/deploy_white_noise_buttons_pi.sh` is what installs the
white-noise unit (heredoc), and the scene-buttons unit is documented in
`scene_buttons_setup.md`. Edit the Pi, then refresh these copies.

Note `WorkingDirectory=/home/pramod` in both button-bridge units. That shared
line is what caused the 2026-09-04 outage
(`incidents/2026-09-04-lgpio-notify-fifo-collision.md`). It is now harmless -
each bridge script moves itself into its own directory before touching GPIO -
and is left as-is deliberately, so the fix does not depend on unit config
being right.
