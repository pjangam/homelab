# scripts/

One folder per project. There are no loose files at the top level - a new
script goes into the folder of the project it belongs to, or a new folder if
it starts a new project. Split out of a flat 73-file directory on 2026-09-15.

| Folder | What lives there |
|---|---|
| `aarti-lights/` | WLED control, the Tier 3 sound renderer (runs as `aarti-lights.service`), audio tooling |
| `certs-backup/` | cert expiry and backup restart-guard tests |
| `clawlight/` | the Pi LED client and its deploy script, clawlight tests (the server itself is in top-level `clawlight/`) |
| `dev-shell/` | tmux/Claude shell installer, local-LLM REPL |
| `esp32-tools/` | flashing, serial and USB diagnostics for any ESP32 board |
| `healthcheck/` | what `cron/healthcheck.sh` publishes and verifies |
| `miraie-ac/` | MirAIe AC availability check, diagnosis and self-heal |
| `network/` | DNS diagnosis and the Mac DNS recorder, Tailscale fixes and serve config |
| `notify/` | `push_ntfy.sh` and `send_email.sh` (sourced by several cron jobs), ntfy setup |
| `pi-buttons/` | GPIO button bridges on the wol-sender Pi, their deploy and HA automations |
| `repo-tools/` | scripts about this repo itself |
| `spotifyd/` | Connect advertising check, the boot-time network wait |
| `white-noise/` | white noise and volume MQTT bridges (both run as services) |
| `wol-sender/` | admin for the wol-sender Pi and the Node-RED on it |

## Before moving or renaming a script

Run `repo-tools/find_script_references.sh NAME`. Some scripts are called by
absolute path from places `git grep` never sees - the crontab (via
`cron/*.sh`), installed systemd units, HA's gitignored config, running
processes - and the "LIVE" column is those.

Three things that fail quietly rather than loudly:

- **Installed systemd units are copies, not symlinks.** Editing
  `systemd/user/*.service` changes nothing on its own: re-copy to
  `~/.config/systemd/user/`, `systemctl --user daemon-reload`, and restart. A
  missed copy of spotifyd's unit fails silently, because its `ExecStartPre` is
  `-` prefixed.
- **Scripts here are two levels below the repo root.** Use
  `$(dirname "$0")/../..` or `Path(__file__).resolve().parent.parent.parent`.
  One level short resolves to `scripts/` and mostly still "works" until it
  looks for `.env*`, `HOMEASSISTANT_CONFIG/` or `cron/`.
- **Tests that build a fake repo must mirror `scripts/` as real directories
  with per-file symlinks.** Symlinking a whole project folder and then writing
  a stub into it writes through to the real script - see
  `healthcheck/test_healthcheck_dashboard_verify.sh`.

The Pi and the Mac run their own deployed copies (e.g. `~/clawlight-led.py`
on the Pi), so moving a script here breaks its deploy script's source path,
not the running service. Re-deploy after a move if the file itself changed.
