# A clean HA dashboard, next to Overview rather than instead of it
**Status:** Done

**Why:** the default **Overview** is rigid and cluttered (noted 2026-09-19), and it cannot be curated without "taking control" of it, which stops it auto-adding new devices.
**Outcome:** **shipped 2026-09-24: Home (`/dashboard-home`), now the default dashboard.** It started as a verbatim copy of Overview and was then edited by hand in the HA UI. Living Room and Bedroom became top-level tabs, and the dead `light.wled_main`/`segment_*` tiles and the Lights summary are gone. **Overview is untouched** and stays the complete, auto-updating index one click away. Details: `projects/ha-dashboard/README.md`. Left open: the stale Tinxy devices (their own backlog entry) still clutter Overview and the area pages.

#### Design decisions worth keeping

- **Storage mode, not YAML mode.** It was YAML mode from 2026-09-22 to 2026-09-24, tracked in git and bind-mounted. But HA then refuses UI edits ("The edit UI is not available when in YAML mode"), and the whole point was Overview plus changes made in the browser. `lovelace.yaml` now declares nothing (`dashboards: {}`); it is kept so the include and the mount stay valid.
- **Git is still the record.** `projects/ha-dashboard/ui_dashboard.py export` copies the live dashboard into `dashboards/home.yaml` over the websocket API, with no restart. Run it and commit after UI edits. `restore` pushes the file back in, e.g. after a rebuild.
- **Overview is not stored anywhere.** In HA 2026.9 it is the Home panel, generated in the browser by strategies. `dump_overview.sh` renders it in Playwright and prints the expanded config, which is how the copy was made; re-dump and diff to see what Overview picked up since.
- **Stats stays a separate dashboard** for health; Home does not repeat it.
- **The default dashboard is per user/device**, set in Profile, not in the dashboard config. Set it again on any device that still opens Overview.
- Helpers: `shot_dashboard.sh` screenshots a path and fails on error cards; `touched_entities.py` lists entities by how often a user changed them (recorder, 10 days).

#### Log
- 2026-09-19: Overview's clutter noted.
- 2026-09-22: Home built in YAML mode, tracked in git and bind-mounted.
- 2026-09-24: switched to storage mode so it can be edited in the UI; shipped as the default dashboard.
