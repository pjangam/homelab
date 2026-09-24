# HA dashboards in YAML

`dashboards/` holds Home Assistant dashboards in **YAML mode**, so they live in
git instead of the gitignored `HOMEASSISTANT_CONFIG/.storage/`, and a container
rebuild restores them. The trade is deliberate: a YAML dashboard cannot be
edited from the UI. Change the file, then refresh the browser.

- `dashboards/home.yaml` - **Home** (`/dashboard-home`), the curated
  dashboard: only what gets acted on. First cut 2026-09-24; the verbatim copy
  of Overview it replaced is commit b833b4d (see the PROJECTS.md entry "A
  clean HA dashboard").
- `dashboards/lovelace.yaml` - declares the dashboards. Adding, renaming or
  removing one here needs an HA restart; editing a dashboard's own file does not.

## How it is wired

- `docker-compose.yml` bind-mounts `dashboards/` read-only at `/config/dashboards`.
- `HOMEASSISTANT_CONFIG/configuration.yaml` (gitignored, root-owned, edit via
  `docker exec homeassistant ...`) ends with
  `lovelace: !include dashboards/lovelace.yaml`. If the mount is missing, that
  include fails and HA starts without these dashboards.

## Overview is not stored anywhere

Since 2025.x the default Overview is the **Home panel** (`/home`; `/lovelace`
redirects there). It is generated in the browser by frontend strategies from
the area registry and the favorites/shortcuts in `.storage/frontend.system_data`,
and each view and section is a strategy of its own, expanded only when rendered.
So there is no file to copy. `dump_overview.sh` renders it in the Playwright
container and prints the fully expanded result as YAML:

    projects/ha-dashboard/dump_overview.sh > /tmp/overview-now.yaml
    DASH=dashboard-stats projects/ha-dashboard/dump_overview.sh   # any other dashboard

Re-dump and diff against `home.yaml` to see what Overview has picked up since
(a new device, a new area) that Home has not.

## What belongs on Home

    projects/ha-dashboard/touched_entities.py

Counts, per entity, the state changes a *user* made (app, dashboard, voice)
over the recorder's window (10 days), read-only from `home-assistant_v2.db`.
That list is what Home holds; re-run it to see what has drifted in or out.
Physical buttons act through automations, so they count in the second column.

## Checking an edit

    projects/ha-dashboard/shot_dashboard.sh <out_dir> dashboard-home/overview dashboard-home/areas-bedroom

Screenshots each path and exits non-zero if any card rendered as an error card,
which is how a typo in the YAML shows up.

## Restarting HA for a lovelace.yaml change

Restarts have side effects here: the Tinxy devices come back `unavailable`
until the integration is reloaded (the watchdog does it after 20 min; do it by
hand with `POST /api/config/config_entries/entry/<tinxy entry>/reload`), and
see `projects/miraie-ac/` for the AC.
