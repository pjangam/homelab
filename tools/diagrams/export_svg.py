#!/usr/bin/env python3
"""Export every drawing in a wiring-diagram HTML page as a standalone .svg.

GitHub does not render HTML pages, but it shows SVG files and SVGs embedded in
markdown. It shows them through an <img> tag, though, so nothing from the page
reaches them: no CSS custom properties, no prefers-color-scheme rules, no
webfonts. So for each <svg role="img"> in the page this:
  - bakes every var(--token) to the page's own light-theme :root value,
  - swaps the IBM Plex webfonts for font stacks that exist everywhere,
  - paints an opaque panel behind the drawing (legible on light and dark pages),
  - adds xmlns, width/height, <title> and <desc> (from aria-label),
  - turns named HTML entities (&middot;) into characters, since an SVG file
    must parse as XML; &amp; &lt; &gt; &quot; &apos; are left alone.

Usage:
    tools/diagrams/export_svg.py PAGE.html [OUT_DIR]
OUT_DIR defaults to <page stem>-svg/ next to the page. Files are named
NN-<slug>.svg, the slug taken from the first sentence of the aria-label.
Commit the output: it is what GitHub shows. Re-run after every edit of the page.
"""
import html as htmlmod
import pathlib
import re
import sys
import xml.dom.minidom

SANS = "system-ui, -apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"
FONTS = {
    "IBM Plex Sans Condensed, sans-serif": SANS,
    "IBM Plex Sans, sans-serif": SANS,
    "IBM Plex Mono, monospace": MONO,
}
XML_ENTITIES = {"amp", "lt", "gt", "quot", "apos"}


def light_tokens(page: str) -> dict:
    # The first :root block is the light theme; dark redefinitions come later.
    block = re.search(r":root\s*\{([^}]*)\}", page)
    if not block:
        raise SystemExit("no :root { ... } token block found in the page")
    return dict(re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", block.group(1)))


def slugify(text: str) -> str:
    first = re.split(r"[.:]", text, maxsplit=1)[0]
    words = re.findall(r"[a-z0-9]+", first.lower())[:5]
    return "-".join(words) or "drawing"


def export(svg: str, tokens: dict, title: str) -> str:
    def token(m):
        name = m.group(1)
        if name not in tokens:
            raise SystemExit(f"var({name}) is not defined in the page's :root")
        return tokens[name].strip()

    svg = re.sub(r"var\((--[\w-]+)\)", token, svg)
    for old, new in FONTS.items():
        svg = svg.replace(f'font-family="{old}"', f'font-family="{new}"')
    svg = re.sub(
        r"&(\w+);",
        lambda m: m.group(0) if m.group(1) in XML_ENTITIES else htmlmod.unescape(m.group(0)),
        svg,
    )

    open_tag = re.match(r"<svg\b[^>]*>", svg).group(0)
    vb = re.search(r'viewBox="([\d.\s-]+)"', open_tag).group(1).split()
    w, h = vb[2], vb[3]
    aria = re.search(r'aria-label="([^"]*)"', open_tag)
    desc = aria.group(1) if aria else title
    new_tag = open_tag.replace(
        "<svg", f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}"', 1
    )
    panel = (
        f"<title>{htmlmod.escape(title)}</title><desc>{desc}</desc>"
        f'<rect x="{vb[0]}" y="{vb[1]}" width="{w}" height="{h}" rx="6" '
        f'fill="{tokens.get("--surface", "#ffffff").strip()}" '
        f'stroke="{tokens.get("--line", "#c6d0d9").strip()}"/>'
    )
    svg = svg.replace(open_tag, new_tag + panel, 1)
    out = '<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n"
    xml.dom.minidom.parseString(out.encode())  # fail loudly if it is not valid XML
    return out


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(__doc__)
        return 2
    page_path = pathlib.Path(sys.argv[1]).resolve()
    out_dir = pathlib.Path(sys.argv[2]) if len(sys.argv) == 3 else page_path.with_name(page_path.stem + "-svg")
    page = page_path.read_text()
    tokens = light_tokens(page)
    page_title = re.search(r"<title>([^<]*)</title>", page)
    page_title = htmlmod.unescape(page_title.group(1)) if page_title else page_path.stem

    svgs = re.findall(r"<svg\b[^>]*role=\"img\".*?</svg>", page, flags=re.S)
    if not svgs:
        raise SystemExit("no <svg role=\"img\"> drawings found")
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("*.svg"):
        old.unlink()  # a drawing removed from the page must not linger here
    for i, svg in enumerate(svgs, 1):
        aria = re.search(r'aria-label="([^"]*)"', svg)
        slug = slugify(htmlmod.unescape(aria.group(1))) if aria else "drawing"
        path = out_dir / f"{i:02d}-{slug}.svg"
        path.write_text(export(svg, tokens, f"{page_title} - {slug.replace('-', ' ')}"))
        print(f"wrote {path} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
