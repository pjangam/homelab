# diagrams

Wiring diagrams are **Markdown + standalone SVG** since 2026-11-05: GitHub shows
SVG files and Markdown, not HTML pages. A project keeps `wiring.md` plus
`wiring-svg/NN-<what>.svg` (reference: `projects/smart-switch/`). The rules for
the SVGs (literal colours, opaque panel, system fonts, valid XML) are in
`.claude/agents/circuit-diagram.md`.

| | |
|---|---|
| `preview_svg.sh OUT_DIR file.svg...` | screenshot SVGs the way GitHub shows them (`<img>`, light and dark page, desktop and phone) |
| `export_svg.py PAGE.html [OUT_DIR]` | pull every drawing out of an older HTML wiring page as standalone SVGs (literal colours, panel, fonts swapped) |
| `render.sh PAGE.html [OUT_DIR]` | screenshot an HTML page; `preview_svg.sh` uses it |


`render.sh` - screenshot a local wiring-diagram HTML page at desktop and phone
widths, in light and dark mode, so whoever drew it can **look at the result**
before publishing: overlapping labels, wires running through text, unreadable
dark-mode colours. xero has no browser of its own, so it runs in the same
Playwright image as `projects/projects-ui/scripts/screenshot.sh`.

```bash
tools/diagrams/render.sh PAGE.html [OUT_DIR]   # default OUT_DIR: PAGE-render/
```

Output directories (`*-render/`) are gitignored - they are throwaway
screenshots. The usual caller is the `circuit-diagram` agent
(`.claude/agents/circuit-diagram.md`); the pages themselves live with their
project (`projects/aarti-lights/wiring.html`,
`projects/diwali-lights/wiring.html`, `projects/curtains/cord-loop.html`).
