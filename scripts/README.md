# scripts/

Since 2026-09-15 most scripts live with their project in `projects/<name>/`,
or in `tools/<name>/` when several projects use them - see the layout rules in
the root `CLAUDE.md`. What is left here stays here by decision: the projects
that deploy to the wol-sender Pi or the Mac. Moving them was skipped, not
postponed, so do not move them unless asked.

| Folder | What lives there |
|---|---|
| `clawlight/` | the Pi LED client and its deploy script, clawlight tests (the server itself is in top-level `clawlight/`) |
| `pi-buttons/` | GPIO button bridges on the wol-sender Pi, their deploy and HA automations |
| `wol-sender/` | admin for the wol-sender Pi and the Node-RED on it |

A new script for one of these projects goes in its folder here.
Before moving anything, read `tools/repo-tools/README.md`.
