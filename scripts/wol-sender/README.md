# wol-sender Pi (admin)

Housekeeping for the Raspberry Pi at `192.168.1.124`, which is both xero's
wake-on-LAN sender and - since the 2026-08/09 moves - the host for Node-RED,
white noise, spotifyd, the GPIO buttons and the second Pi-hole. Still under
`scripts/` because that whole group moves together later; see
[`scripts/README.md`](../README.md).

## Waking xero

| | |
|---|---|
| `update_wol_sender.sh` | install/update the boot-time WoL sender (`ssh wol-sender bash -s < …`). It waits for the router to answer and resends until xero is up - the earlier fixed `sleep 3` and 3-packet versions both fired before the router had booted |
| `persist_wol_setting.sh` | keep xero's NIC WoL flag across reboots |
| `wol_listener.py` | run **on xero** with sudo: confirms the Pi's packet is valid and arrives, without shutting xero down for a real wake test |

An ESP32 does the same job from a non-UPS outlet, so that mains returning is
itself the trigger - [`esp32/wol_on_boot/`](../../esp32/wol_on_boot/README.md).

## The Pi itself

| | |
|---|---|
| `set_wol_sender_static_ip.sh` | pin it to `.124`. Its DHCP lease silently jumped .103 → .105 once, which would have broken the AC bridge with no visible error |
| `setup_wol_sender_nopasswd_sudo.sh` | the narrow passwordless-sudo rules the unattended scripts need |
| `fix_wol_sender_overlay_hang.sh` | recovery notes for the read-only overlay filesystem that left it hanging on boot (fixed by pulling the SD card and removing `overlayroot=tmpfs`) |
| `start_nodered_on_pi.sh`, `watchdog_nodered_pi.sh` | Node-RED on the Pi, and the */10 cron watchdog that restarts it when its MQTT bridge is not actually connected. What it does and does not cover: [`projects/miraie-ac/README.md`](../../projects/miraie-ac/README.md) |

## Desk clock / screensaver

`analog_clock.py` is a fullscreen GTK3 analog clock with HA's weather beside
it, shown by `clock_screensaver.sh` after 5 idle minutes and started at login
by `clock-screensaver.desktop`; `deploy_clock_screensaver.sh` installs all
three, `kanshi-config` sets the display layout. GTK3 because the desktop is
labwc (Wayland), where xscreensaver and the X11 clocks misbehave.
