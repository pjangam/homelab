# scripts/ split into one folder per project
**Status:** Done

**Why:** `scripts/` had grown to 73 loose files across a dozen unrelated projects, with nothing saying which ones cron or a service depended on - the start of a big ball of mud.
**Outcome:** shipped 2026-09-15 - 14 project folders (`aarti-lights/`, `healthcheck/`, `notify/`, `miraie-ac/`, `spotifyd/`, `white-noise/`, `pi-buttons/`, `wol-sender/`, `clawlight/`, `network/`, `esp32-tools/`, `certs-backup/`, `dev-shell/`, `repo-tools/`), no loose files, and `scripts/README.md` saying where a new script goes.
- Left open: four descriptions in HA's root-owned `automations.yaml` still say `scripts/scene-buttons-mqtt.py` / `scripts/white-noise-buttons-mqtt.py` (text only), and root's crontab was not checked (needs sudo).

#### How it was done
Two phases: the ~50 scripts nothing live calls first, then the cron- and systemd-called ones together with their callers, moved just after a cron tick with no job running.

#### Notes worth keeping
- **`tools/repo-tools/find_script_references.sh NAME` before moving or renaming anything.** It covers what `git grep` cannot see: the crontab via `cron/*.sh`, installed systemd units, HA's gitignored config, running processes.
- **Installed user units are copies, not symlinks** - a repo edit changes nothing until re-copied, daemon-reloaded and restarted. spotifyd's `wait_for_network.sh` is `-` prefixed, so a missed copy would have silently brought back the boot race.
- **Scripts are now two levels below the repo root.** One level short resolves to `scripts/` and fails only when it reaches for `.env*` or `HOMEASSISTANT_CONFIG/`.
- **Nearly deleted the live healthcheck scripts.** Two healthcheck tests built a fake repo by symlinking each `scripts/` entry and then wrote stubs into it; once entries became folders the stubs would have gone through to the real cron-called scripts. Caught before the move; the tests now mirror real directories with per-file symlinks.
- Found on the way, not caused by the move: the tmux installer's `mktemp -t` only worked on macOS, so its test failed 32/63 on `xero`. Fixed.

#### Verification
Every file parses; no reference uses an old flat path; all moved tests pass with real scripts byte-identical before and after; aarti-lights, white-noise-mqtt and volume-mqtt restarted and running from the new paths; the 14:20 power watchdog sourced `notify/` silently, and the 14:30 healthcheck advanced its retained `last_check` (08:30 -> 09:00 UTC) with no problems.

#### Log
- 2026-11-04: the doc half of this split landed - see "Per-project READMEs: the root Readme split, and a rule that keeps it". The files moved in 2026-09-15; the prose describing them stayed in the root `Readme.md` for another seven weeks.
- 2026-09-15: split shipped and verified.
