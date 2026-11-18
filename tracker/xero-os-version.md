# xero OS: stay on Ubuntu 24.04 LTS, no 26.04 upgrade yet
**Status:** Parked
**Priority:** P3
**Cost:** ?
**Effort:** ?

#### Open items
- [ ] **Pramod:** revisit only on a trigger: a new machine (install Ubuntu Server 26.04 fresh), keeping xero long-term (release upgrade early 2027), or the ZFS mismatch causing a real problem

**Why:** `do-release-upgrade -c` has offered 26.04.1 LTS since its .1 release, and the 2026-10-29 power-cut reboot brought up a new kernel, which raised the question of whether the OS should move too. Recorded so the reasoning isn't worked out again from scratch.
**State:** decided 2026-10-29: stay on 24.04. xero is Lubuntu 24.04.5 (`lubuntu-desktop` installed, GUI off: boots to `multi-user.target`) on the 7.0 HWE kernel (`linux-generic-hwe-24.04`, 7.0.0-42 as of 2026-10-29). unattended-upgrades keeps kernel patches coming within 24.04, so a new kernel is not an OS upgrade. 24.04 standard support runs to 2029 for the Ubuntu base (kernel, ZFS, systemd, Docker host packages); Lubuntu's own flavour packages (LXQt and its apps) get only 3 years, to April 2027 - irrelevant while the GUI is off, but one more reason to purge the desktop if xero is kept past then. If xero is kept long-term, the release upgrade goes on a quiet weekend after backups and a `zpool scrub`, with keyboard and screen attached.

#### Why not upgrade now
- Little to gain: the HWE kernel already gives 24.04 the new kernel and hardware support, and nearly everything else runs in Docker, which doesn't care about the host release.
- Real risk on the box that runs everything: the release upgrade disables third-party repos (Docker, Tailscale), moves the system Python (host scripts and systemd --user units using it, e.g. `websockets` in `projects/healthcheck/add_stats_dashboard_tile.py`), and rebuilds the ZFS module the pools depend on. A failure takes HA, Immich, Pi-hole and the AC bridge down together.
- The bad RAM that made a big upgrade unsafe was replaced with the 32GB stick, so that is no longer the reason.
- **One point for 26.04:** ZFS userland is `zfs-2.2.2` (24.04's) while the HWE kernel module is `zfs-kmod-2.4.1`. Works day to day, but it is an untested pairing and new pool features can't be managed with 2.2 tools. Don't `zpool upgrade` while it lasts. 26.04 would put them back in step.

#### Was Lubuntu the right choice?
Ubuntu was right for this box: prebuilt, signed ZFS modules on every kernel (Debian builds them with DKMS, which can break on a kernel update and leave the pool unmounted), HWE kernels for the N5105, and first-party Docker/Tailscale repos. The desktop flavour was not needed: with the GUI off it costs little, but it still runs services a headless server doesn't use (`cups`, `cups-browsed`, `ModemManager`, as of 2026-10-29) and pulls desktop packages into every update. Not worth a reinstall; check what depends on each before removing it (avahi and bluetooth may be used by spotifyd and audio). Alternatives considered:
- **Debian stable:** leaner and steadier, but ZFS via DKMS (above). Fine if the root isn't ZFS and you accept the occasional rebuild.
- **Proxmox VE:** ZFS-native and good for VMs/LXC, but adds a layer over the Docker-everything setup with no gain on a 4-core N5105. Worth a look only on a much bigger machine.
- **TrueNAS SCALE / Unraid:** appliance OSes that fight host-level cron jobs, systemd --user units and the repo-driven setup used here.
- **NixOS:** the whole machine as reproducible config, but a steep switch from a working setup.
- **Alpine:** tiny and secure, great *inside* containers, poor as this host: OpenRC instead of systemd (this repo runs on systemd units, `systemd --user` with linger, timers and `journalctl`, all of which would need rewriting), musl libc breaks some host binaries and Python wheels, and ZFS on the root/host pool is less travelled there. Its size advantage doesn't matter on a 32GB/SSD box.

Verdict: for the next machine, **Ubuntu Server LTS**: the same base, without the desktop.

#### Removing the desktop (if xero is kept past April 2027)
Simulated 2026-10-29, not done. `apt purge lubuntu-desktop` alone removes only the meta-package; `apt purge --autoremove lubuntu-desktop` removes **382 packages**, including ones xero uses: `pipewire-audio`, `pipewire-alsa`, `alsa-base` (spotifyd and the `filter-chain` user service play through PipeWire), `bluez`, `network-manager-openvpn`. NetworkManager itself stays (it brings up `enp1s0` - keep it). Safe order:
1. `sudo apt-mark manual` pipewire, pipewire-pulse, pipewire-audio, pipewire-alsa, wireplumber, alsa-base, network-manager, avahi-daemon (and anything else the next step shows that's in use).
2. `apt-get -s purge --autoremove lubuntu-desktop` again and read the list.
3. Purge, reboot, then check: network, Tailscale, all containers, spotifyd audio, the systemd --user units.
~30 minutes; anything removed by mistake comes back with `apt install`. Result: about the same as a fresh Ubuntu Server, minus leftovers (configs, NetworkManager instead of networkd).

#### Log
- 2026-10-29: entry created. 7.0.0-42 was installed by unattended-upgrades at 06:49 and went live at the 17:46 reboot after the power-watchdog shutdown. Upgrade deferred, reasons above.
