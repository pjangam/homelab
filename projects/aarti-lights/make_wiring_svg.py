#!/usr/bin/env python3
"""Generate projects/aarti-lights/wiring.svg from the first diagram in wiring.html.

The HTML page themes itself with CSS custom properties, which is exactly what a
standalone SVG cannot rely on: GitHub renders SVG in markdown through an <img>
tag, so external CSS, scripts and even the page's own prefers-color-scheme rules
never reach it. So this bakes the light-theme token values in as literal colours
and paints an opaque panel behind the drawing, which makes it legible on a light
page and on a dark one without depending on any media query.

Run after editing the diagram in wiring.html:
    ./projects/aarti-lights/make_wiring_svg.py
"""
import html as htmlmod
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent

# Light-theme values from wiring.html's :root, chosen for contrast on the panel.
TOKENS = {
    "--surface": "#ffffff",
    "--sunk":    "#e4eaf0",
    "--ink":     "#15202b",
    "--muted":   "#4d5c6b",
    "--line":    "#b9c5d0",
    "--w5v":     "#bf3327",
    "--w33":     "#61409c",
    "--wgnd":    "#2b3a47",
    "--wdata":   "#8f6708",
    "--paper":   "#f5f8fa",
}
PANEL = "#f7f9fb"
BORDER = "#c6d0d9"

SANS = "system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"


def main() -> int:
    html = (HERE / "wiring.html").read_text()
    start = html.index('<svg viewBox="0 0 1020 660"')
    svg = html[start:html.index("</svg>", start) + len("</svg>")]

    for token, value in TOKENS.items():
        svg = svg.replace(f"var({token})", value)

    # No webfont reaches an <img>-rendered SVG, so name stacks that exist everywhere.
    svg = svg.replace('font-family="IBM Plex Sans Condensed, sans-serif"', f'font-family="{SANS}"')
    svg = svg.replace('font-family="IBM Plex Sans, sans-serif"', f'font-family="{SANS}"')
    svg = svg.replace('font-family="IBM Plex Mono, monospace"', f'font-family="{MONO}"')

    aria = re.search(r'aria-label="([^"]*)"', svg).group(1)
    svg = svg.replace(
        '<svg viewBox="0 0 1020 660"',
        '<svg xmlns="http://www.w3.org/2000/svg" width="1020" height="660" viewBox="0 0 1020 660"',
        1,
    )
    # Opaque panel first, so the drawing never sits on an unknown page background.
    svg = svg.replace(
        ">\n        <defs>",
        f'>\n        <title>Aarti lights wiring, as built</title>\n        <desc>{aria}</desc>\n'
        f'        <rect x="0.5" y="0.5" width="1019" height="659" rx="6" fill="{PANEL}" stroke="{BORDER}"></rect>\n'
        "        <defs>",
        1,
    )

    # Named HTML entities (&middot;, &minus;) are undefined in XML, and an SVG
    # served as a file must parse as XML. Unescape to the literal characters.
    svg = htmlmod.unescape(svg)

    out = HERE / "wiring.svg"
    out.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n")
    leftover = re.findall(r"var\(--[a-z0-9]+\)", svg)
    if leftover:
        raise SystemExit(f"unresolved tokens left in {out}: {sorted(set(leftover))}")
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
