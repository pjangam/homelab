# diagrams

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
