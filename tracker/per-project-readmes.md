# Per-project READMEs: the root Readme split, and a rule that keeps it
**Status:** Done

**Why:** the 2026-09-15 split moved the *files* into `projects/`, `services/`, `tools/` and `docs/`, but not the prose. `Readme.md` was still 754 lines and still owned the runbooks for MirAIe AC, white noise, the GPIO buttons, both watchdogs, spotifyd, ntfy and the TLS certs - every one of which had a folder of its own by then. So `projects/miraie-ac/` held the scripts while the only description of what they fix sat 150 lines deep in a root README, and 11 of 19 project folders had no README at all. Found while reviewing the repo structure on 2026-11-04.

**Outcome:** shipped 2026-11-04.
- **Root `Readme.md` is host-level only**, 754 → ~280 lines: new machine setup, git hooks, HA config gitignore rationale, what runs here, OS updates, memory management, TTY font, past incidents, known issues, the N5105 quirks and overheating. Plus a **"Where things live" index** - the four homes, then every `projects/`, `services/` and `tools/` folder with a one-line description and a link.
- **Eleven sections moved to their owner**, byte-for-byte by line range (`tools/repo-tools/split_readme.sh`, deleted after the run; its ranges are in the commit): MirAIe AC → `projects/miraie-ac/`, white noise → `projects/white-noise/`, Tinxy and power watchdogs → their folders, spotifyd → `projects/spotifyd/`, TLS certs → `projects/certs-backup/`, ntfy → `services/ntfy/`, Vaultwarden → `services/vaultwarden/`, Immich hardware → `services/immich/`, GPIO buttons → `scripts/pi-buttons/`, and the Alfred Camera notes into the "Baby-cry alert via ntfy" entry (its Overlaps already pointed at them).
- **28 new READMEs**, so every folder under `projects/`, `services/`, `tools/`, `scripts/` and `esp32/` now has one. `projects/projects-ui/README.md` was the Vite template boilerplate and is now a real one.
- **A rule in `CLAUDE.md`**, placed with the layout rules rather than next to the hardware/endpoints ones: the README arrives with the folder's **first file**, not before Done. A half-built project is when "what is this, what runs it, what breaks it" is hardest to reconstruct.
- **`tools/repo-tools/check_readmes.sh`**, and `.githooks/pre-commit` runs it `--staged` - so a commit that creates a folder without a README is stopped, while the repo's existing state can never fail a commit.

#### Notes worth keeping
- **The IP sweep in `check_hardware_md.sh` had to move with the prose.** It grepped `PROJECTS.md`, `Readme.md` and the root `*_setup.md` for `192.168.*`, so every address that moved into a project README would have silently left its coverage - the exact drift the check exists to catch. It now reads the per-project READMEs too, via `git ls-files`. Incident write-ups are deliberately still excluded: they name devices that are long gone, which would report missing for ever.
- **Moved prose is not automatically true prose.** `projects/white-noise/README.md` still describes xero's paths and card numbers, because the service moved to the Pi on 2026-09-24 and nobody rewrote it (step 2 of "Pi audio move follow-ups"). It carries a note saying so rather than reading as current.
- **Three references pointed into sections that no longer exist** (`PROJECTS.md` ×3, plus the cross-links inside the moved text itself, e.g. the reconnect-loop bug note the white-noise page cites in the pi-buttons page). `toggle_button_setup.md`, cited from three files, has not existed since ac07b71 (2026-08-31).
- The root `Makefile` is dead - it starts node-red under pm2, and node-red moved to the Pi on 2026-08-22. Untracked `nodered/node_modules/` at the root is its leftover. Not removed here; it is not documentation.

#### Log
- 2026-11-05: `.DS_Store` added to `.gitignore`. It was already covered by `~/.gitignore_global` on the Mac, so it was never a live risk from this clone - but xero commits from its own checkout, which has no such config. Ignored in-repo for the same reason as `*.gpg`.
- 2026-11-04: shipped, after a structure review that also turned up `.DS_Store` missing from `.gitignore` and the Done/Closed weight in this file (see "PROJECTS.md: move Done and Closed history out of the tracker").
