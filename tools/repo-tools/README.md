# tools/repo-tools/

Scripts about this repo itself.

| Script | What it does |
|---|---|
| `find_script_references.sh [NAME]` | everything that refers to a script - in the repo and in the places `git grep` never sees |
| `rewrite_paths.py OLD=NEW ...` | rewrites repo paths across every tracked file for a move (dry run unless `--apply`) |
| `check_hardware_md.sh` | drift check for `docs/hardware.md` |
| `check_endpoints_toml.sh` | drift check for `projects/endpoints/endpoints.toml` |
| `convert_apple_to_bitwarden.py` | one-off password export conversion |

## Before moving or renaming a file

Run `find_script_references.sh NAME`. Some scripts are called by absolute path
from outside git - the crontab, installed systemd units, HA's gitignored
config, running processes - and its "LIVE" column is those. Then move with
`rewrite_paths.py`, dry run first.

Things that fail quietly rather than loudly:

- **The crontab and the installed systemd units hold absolute paths.** Update
  the crontab in the same step as the move, ideally just after a `*/5` tick,
  and confirm the next run used the new path (`journalctl _COMM=cron`) and
  exited cleanly. Installed units are copies, not symlinks: re-copy to
  `~/.config/systemd/user/`, `systemctl --user daemon-reload`, and restart. A
  missed copy of spotifyd's unit fails silently, because its `ExecStartPre` is
  `-` prefixed. Diff the installed copy against the repo first - they can
  drift (on 2026-09-15 the installed `white-noise.service` had a `playerctl`
  line the repo did not).
- **Depth decides the repo root.** A file in `projects/<name>/` or
  `tools/<name>/` is two levels down: `$(dirname "$0")/../..` or
  `Path(__file__).resolve().parent.parent.parent`. Moving a file up or down a
  level is a code change, not a text substitution - `rewrite_paths.py` does
  not do it.
- **Tests that build a fake repo must mirror directories as real directories
  with per-file symlinks.** Symlinking a whole project folder and then writing
  a stub into it writes through to the real script - see
  `projects/healthcheck/test_healthcheck_dashboard_verify.sh`.
- **Another session may already have created the target.** `git mv src dst`
  into an existing `dst/` nests it as `dst/src/`. Check the target first.

Other machines talk to xero through services and ports, not repo paths, so a
move never breaks a running service on the Pi or the Mac. It does break the
*deploy* scripts that copy a file there, and the Mac's setup scripts that scp
from a repo path - update those in the same commit.
