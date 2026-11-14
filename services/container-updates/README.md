# container-updates

How xero's containers stay on the latest versions: **Watchtower** applies updates that don't need a person, and **Diun** sends a notification for the ones that do. Both run on xero from the root `docker-compose.yml`. They have no files of their own, so this README is the only thing in this folder.

## Which mechanism covers which image

Each image's tag decides the mechanism:

| Tag style | Example | What keeps it current |
|---|---|---|
| Floating (`latest`, `stable`) | `homeassistant:stable`, `pihole:latest`, `grafana:latest` | Watchtower, Sundays 04:00 |
| Major tag (follows minors and patches) | `prom/prometheus:v3`, `prom/node-exporter:v1`, `syncthing:2`, `valkey:9` | Watchtower; Diun notifies when the **next major** ships |
| Minor tag (follows patches) | `cadvisor:0.60` (no `latest` on ghcr) | Watchtower; Diun notifies on the **next minor** |
| Exact pin | Immich `IMMICH_VERSION` in `.env` | Diun notifies on **every release**, then `services/immich/upgrade.sh` |
| Pinned by digest | Immich's valkey, Immich's postgres | Follow Immich upstream's compose (`upgrade.sh` shows the diff) |
| Built locally | `projects-ui` | Neither (label `com.centurylinklabs.watchtower.enable=false`) |

- **Why not let Watchtower do everything:** it only re-pulls the tag a container already has. It never moves `v3.3.5` to `v3.4.1`, so pinned images would sit on old versions forever with no warning. That happened to Immich.
- **Why Immich stays pinned:** a release can run database migrations that can't be undone, and some releases need compose changes. `upgrade.sh` takes a ZFS snapshot first; an update by Watchtower at 04:00 wouldn't. See `services/immich/README.md`.

## The two containers

| Container | Image | Schedule | Notifies |
|---|---|---|---|
| `watchtower` | `nickfedor/watchtower:latest` | Sun 04:00 (UTC, `WATCHTOWER_SCHEDULE`) | HA webhook `watchtower_update` + ntfy `homelab-updates` (priority 2) |
| `diun` | `crazymax/diun:latest` | daily 09:00 IST (`DIUN_WATCH_SCHEDULE`) | ntfy `homelab-updates` (priority 3) |

- **Watchtower is the maintained fork:** `containrrr/watchtower` was archived in Dec 2025 (last release 1.7.1, 2023). It was swapped for the fork on 2026-11-14. The env vars and labels are the same, with two differences:
  - **`.Name` has no leading `/`:** the template no longer slices it off, or `immich_server` would become `mmich_server`.
  - **No `DOCKER_API_VERSION`:** the fork negotiates the API version itself.
- **Both update themselves:** they use floating tags, so Watchtower pulls new versions of itself and of Diun.
- **State:** Diun keeps the tags it has already seen in the named volume `diun-data`. Watchtower keeps no state.
- **Token:** `NTFY_UPDATES_TOKEN` in `.env`, the write-only `watchtower` ntfy principal (`services/ntfy/README.md`). Both containers share it.

## Diun labels

Diun only watches containers that carry the label `diun.enable=true`. Each watched service in `docker-compose.yml` has:

| Label | Value | Why |
|---|---|---|
| `diun.watch_repo` | `true` | list the repo's tags, not only the running one |
| `diun.notify_on` | `new` | notify when a new tag appears; Watchtower already handles a rebuilt current tag |
| `diun.sort_tags` | `semver` | |
| `diun.include_tags` | regex | only the tags the running tag won't reach |

- **When a major or minor version is upgraded, bump the regex too.** For example, after moving prometheus to `v4`, its regex must start matching at `v5`. If you forget, Diun keeps notifying about the version you're already on.
- **`$$` in the compose regexes:** compose would otherwise treat `$'` as interpolation.
- **First run is silent** (`DIUN_WATCH_FIRSTCHECKNOTIF=false`): Diun records the tags that already exist without notifying. That's why Immich 3.4.1 didn't alert on 2026-11-14.
- **Immich's repo has thousands of tags** (one per commit and PR). Listing them is slow, and ghcr timed out once on the first run. Diun retries on its next run.

## After a notification

| Notification for | Do |
|---|---|
| Immich | `services/immich/upgrade.sh --check`, read what it prints, then `services/immich/upgrade.sh` from a real terminal |
| Next major or minor of another image | read the release notes, change the tag in `docker-compose.yml`, bump that service's `diun.include_tags`, `docker compose up -d <service>` |

## Re-run after a change

    docker compose up -d watchtower diun
    docker logs diun | tail    # "Found N image(s) to analyze": N = number of labelled containers
