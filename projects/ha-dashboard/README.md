# HA Home dashboard

**Home** (`/dashboard-home`) is a copy of Overview that can be edited in the
HA UI (pencil, top right). It is a storage-mode dashboard, so HA keeps it in
the gitignored `HOMEASSISTANT_CONFIG/.storage/`; `dashboards/home.yaml` is its
tracked copy, kept in sync by `ui_dashboard.py` over the websocket API (no
restart):

    projects/ha-dashboard/ui_dashboard.py export   # after editing in the UI, then git diff + commit
    projects/ha-dashboard/ui_dashboard.py restore  # push home.yaml back into HA (after a rebuild)
    projects/ha-dashboard/ui_dashboard.py create   # recreate the dashboard from scratch

It was YAML mode from 2026-09-22 to 2026-09-24, but a YAML-mode dashboard
cannot be edited from the UI, which is the whole point of this one.

## How it is wired

- `docker-compose.yml` bind-mounts `dashboards/` read-only at `/config/dashboards`.
- `HOMEASSISTANT_CONFIG/configuration.yaml` (gitignored, root-owned) ends with
  `lovelace: !include dashboards/lovelace.yaml`, which now declares no YAML
  dashboards (`dashboards: {}`). Adding one there needs an HA restart.

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

## Which entities get used

    projects/ha-dashboard/touched_entities.py

Optional input for editing `home.yaml`: counts, per entity, the state changes
a *user* made (app, dashboard, voice) over the recorder's window (10 days),
read-only from `home-assistant_v2.db`. Physical buttons act through
automations, so they count in the second column.

## Checking an edit

    projects/ha-dashboard/shot_dashboard.sh <out_dir> dashboard-home/overview dashboard-home/areas-bedroom

Screenshots each path and exits non-zero if any card rendered as an error card,
which is how a typo in the YAML shows up.

## Restarting HA for a lovelace.yaml change

Restarts have side effects here: the Tinxy devices come back `unavailable`
until the integration is reloaded (the watchdog does it after 20 min; do it by
hand with `POST /api/config/config_entries/entry/<tinxy entry>/reload`), and
see `projects/miraie-ac/` for the AC.
