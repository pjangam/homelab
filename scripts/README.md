# scripts/

**Nearly folded away.** Since 2026-09-15 scripts live with their project in
`projects/<name>/`, or in `tools/<name>/` when several projects use them - see
the layout rules in the root `CLAUDE.md`. What is left here is the step still
to come: the projects that deploy to the wol-sender Pi or the Mac, which move
together with their deploy scripts.

| Folder | What lives there |
|---|---|
| `clawlight/` | the Pi LED client and its deploy script, clawlight tests (the server itself is in top-level `clawlight/`) |
| `pi-buttons/` | GPIO button bridges on the wol-sender Pi, their deploy and HA automations |
| `wol-sender/` | admin for the wol-sender Pi and the Node-RED on it |

Until a folder has moved, a new script for that project still goes here.
Before moving anything, read `tools/repo-tools/README.md`.
