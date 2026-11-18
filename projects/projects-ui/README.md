# projects-ui

The dashboard that renders the project files in [`tracker/`](../../tracker/README.md) as a browsable page at
**`https://xero.<tailnet>/projects`** (tailnet only, through Caddy). A React +
Vite app, built into an nginx image by its own `Dockerfile` and run from the
root `docker-compose.yml`. It carries
`com.centurylinklabs.watchtower.enable=false` because it is built locally, so
Watchtower could only ever 401 against Docker Hub.

It is **read-only**: the `tracker/` files stay the source of truth and are
edited as text. The app fetches nginx's JSON listing of `tracker/` and then
every file, live through the repo bind mount (`src/hooks/useProjects.js`),
joins them back into one document (`src/lib/trackerFiles.js`), parses it
(`src/lib/parseProjects.js`), groups projects by Status, shows each one's
Cost / Effort under its title,
and pulls out two cross-cutting views:

- **Open items** (`src/lib/openItems.js`, `components/OpenItems.jsx`) - every
  project's `#### Open items` checklist in one panel, so what is waiting on whom
  is visible at a glance. This is why the checklist format is enforced at
  commit time by `.githooks/pre-commit`: an item that breaks the format is
  invisible here, which means it is effectively forgotten.
- **Shopping list** (`src/lib/parts.js`, `components/ShoppingList.jsx`) - the
  parts named across projects, collected.

```bash
cd projects/projects-ui
npm install
npm run dev        # vite dev server
npm test           # vitest - the parsers have real coverage, keep it
npm run lint       # oxlint
npm run build      # what the Dockerfile runs
scripts/screenshot.sh   # headless screenshot (xero has no browser; Playwright image)
```

Served under the `/projects` path with the prefix **kept intact** - its own
`nginx.conf` serves from a matching location and redirects `/projects` to
`/projects/`. See [`services/caddy/README.md`](../../services/caddy/README.md).
