#!/usr/bin/env python3
"""Render endpoints.toml into site/index.html - the one page listing every
endpoint this homelab serves.

Run it on xero, where .env holds TAILNET_SUFFIX:

    projects/endpoints/render_endpoints.py

WHY THE OUTPUT IS NOT COMMITTED: endpoints.toml writes `{tailnet}` wherever the
tailnet suffix belongs, and this script substitutes the real value in. The
rendered site/ therefore contains the tailnet name and is gitignored; the
source list stays safe to track. Same split as services/tailscale's template,
except that one's rendered output carries no secret and so is tracked.

TOML, not YAML: tomllib is in the standard library from Python 3.11 (xero is
on 24.04 / 3.12), pyyaml is not installed here, and this page is not worth a
dependency. TOML also takes comments, which a JSON data file could not.

No templating engine, same reasoning. The escaping is done with html.escape on
every value that reaches the page.
"""
import html
import os
import re
import sys
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SOURCE = HERE / "endpoints.toml"
OUTDIR = HERE / "site"


def tailnet_suffix() -> str:
    """TAILNET_SUFFIX from the environment, else from the repo's .env.

    Read by hand rather than sourced: .env is a docker compose env file, not a
    shell script, and sourcing it would run anything in it.
    """
    value = os.environ.get("TAILNET_SUFFIX")
    if value:
        return value.strip()
    envfile = REPO / ".env"
    if envfile.exists():
        for line in envfile.read_text().splitlines():
            match = re.match(r"\s*TAILNET_SUFFIX\s*=\s*(.+?)\s*$", line)
            if match:
                return match.group(1).strip().strip("\"'")
    sys.exit(
        "TAILNET_SUFFIX not set and not found in .env.\n"
        "This renders on xero, where .env lives. Elsewhere, pass it in:\n"
        "  TAILNET_SUFFIX=example.ts.net projects/endpoints/render_endpoints.py"
    )


def esc(value, tailnet: str) -> str:
    """Substitute the tailnet placeholder, then escape for HTML."""
    return html.escape(str(value).replace("{tailnet}", tailnet))


# Protocol badges. The colour is doing real work: it is the fastest way to see
# at a glance that a row is not something a browser can open.
PROTO_CLASS = {
    "https": "web", "http": "web",
    "mqtt": "msg",
    "dns": "net", "smb": "net", "ssh": "net",
    "udp": "raw",
}


def render_endpoint(ep: dict, tailnet: str) -> str:
    proto = ep.get("proto", "")
    address = esc(ep["host"], tailnet)
    if "port" in ep:
        address += f":{ep['port']}"

    out = ['<article class="ep">', '<header>']
    out.append(f'<span class="badge {PROTO_CLASS.get(proto, "raw")}">{esc(proto, tailnet)}</span>')
    if "url" in ep:
        url = esc(ep["url"], tailnet)
        # Open web links in a new tab: this page is a jumping-off point kept on
        # a bookmark, and navigating away from it in place means coming back
        # through history every time.
        #
        # Only http(s) gets target=_blank. smb:// and ssh:// are handed to the
        # OS rather than navigated to, so the page is not left behind anyway -
        # and _blank on those opens a blank tab that never fills and never
        # closes itself. rel=noopener because target=_blank without it hands
        # the opened page a window.opener reference back to this one.
        target = ' target="_blank" rel="noopener"' if url.startswith(("http://", "https://")) else ""
        out.append(f'<h3><a href="{url}"{target}>{esc(ep["name"], tailnet)}</a></h3>')
    else:
        out.append(f'<h3>{esc(ep["name"], tailnet)}</h3>')
    out.append(f'<code class="addr">{address}</code>')
    out.append("</header>")

    out.append(f'<p class="desc">{esc(ep["desc"], tailnet)}</p>')
    if "who" in ep:
        out.append(f'<p class="who"><span class="label">Used by</span> {esc(ep["who"], tailnet)}</p>')
    if "connect" in ep:
        # The payload for everything a browser cannot open. data-copy carries
        # the unescaped-on-render text; the button hands it to the clipboard.
        value = esc(ep["connect"], tailnet)
        out.append(
            f'<div class="connect"><code>{value}</code>'
            f'<button type="button" class="copy" data-copy="{value}">copy</button></div>'
        )
    if "note" in ep:
        out.append(f'<p class="note">{esc(ep["note"], tailnet)}</p>')

    if ep.get("topic"):
        out.append('<dl class="topics">')
        for topic in ep["topic"]:
            out.append(f'<dt><code>{esc(topic["name"], tailnet)}</code></dt>')
            out.append(f'<dd>{esc(topic["desc"], tailnet)}</dd>')
        out.append("</dl>")

    out.append("</article>")
    return "\n".join(out)


CSS = """
:root {
  color-scheme: light dark;
  --bg: #fbfaf8; --panel: #fff; --ink: #1c1d20; --dim: #5d6168;
  --line: #e4e1db; --accent: #8a4b2a; --code-bg: #f3f1ed;
  --web: #2f6f4f; --msg: #8a4b2a; --net: #3b5a86; --raw: #6b5a8a;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #17181b; --panel: #1e2024; --ink: #e8e6e2; --dim: #9aa0a8;
    --line: #2e3137; --accent: #d79a76; --code-bg: #26292e;
    --web: #7fc6a0; --msg: #d79a76; --net: #8fb2e0; --raw: #b7a3d8;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2.5rem 1.25rem 4rem; background: var(--bg); color: var(--ink);
  font: 16px/1.55 ui-sans-serif, -apple-system, "Segoe UI", Roboto, sans-serif;
}
.page { max-width: 62rem; margin: 0 auto; }
h1 { font-size: 1.6rem; margin: 0 0 .35rem; letter-spacing: -.01em; }
.sub { color: var(--dim); margin: 0 0 2.5rem; font-size: .95rem; }
h2 {
  font-size: 1.05rem; margin: 2.75rem 0 .3rem; padding-bottom: .4rem;
  border-bottom: 1px solid var(--line); letter-spacing: .02em; text-transform: uppercase;
}
.blurb { color: var(--dim); font-size: .9rem; margin: .5rem 0 1.25rem; }
.grid { display: grid; gap: .85rem; }
.ep {
  background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
  padding: .9rem 1.05rem;
}
.ep header { display: flex; flex-wrap: wrap; align-items: baseline; gap: .55rem; margin-bottom: .45rem; }
.ep h3 { font-size: 1rem; margin: 0; font-weight: 600; }
.ep h3 a { color: var(--accent); text-decoration: none; }
.ep h3 a:hover { text-decoration: underline; }
.badge {
  font: 600 .66rem/1 ui-monospace, SFMono-Regular, Menlo, monospace;
  text-transform: uppercase; letter-spacing: .06em; padding: .3rem .45rem;
  border-radius: 4px; border: 1px solid currentColor;
}
.badge.web { color: var(--web); } .badge.msg { color: var(--msg); }
.badge.net { color: var(--net); } .badge.raw { color: var(--raw); }
code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: .85em; }
.addr { color: var(--dim); margin-left: auto; }
p { margin: .3rem 0; }
.desc { font-size: .92rem; }
.who, .note { font-size: .85rem; color: var(--dim); }
.label {
  font: 600 .68rem/1 ui-monospace, monospace; text-transform: uppercase;
  letter-spacing: .05em; color: var(--dim); opacity: .8;
}
.note::before { content: "\\2014\\00a0"; }
.connect {
  display: flex; gap: .5rem; align-items: center; margin: .6rem 0 .2rem;
  background: var(--code-bg); border-radius: 6px; padding: .45rem .6rem;
}
/* The connection strings are the long ones and the ones that must not wrap
   into something uncopyable - scroll the box rather than the page. */
.connect code { overflow-x: auto; white-space: pre; flex: 1; }
.copy {
  flex: none; font: 600 .7rem/1 ui-monospace, monospace; cursor: pointer;
  background: transparent; color: var(--dim); border: 1px solid var(--line);
  border-radius: 4px; padding: .32rem .5rem;
}
.copy:hover { color: var(--ink); }
.topics { margin: .7rem 0 0; padding-top: .6rem; border-top: 1px dashed var(--line); }
.topics dt { margin-top: .45rem; }
.topics dt code { color: var(--msg); }
.topics dd { margin: .1rem 0 0; font-size: .85rem; color: var(--dim); }
footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--line);
  color: var(--dim); font-size: .85rem; }
footer p { margin: .5rem 0; }
@media (max-width: 34rem) {
  .addr { margin-left: 0; width: 100%; }
}
"""

JS = """
document.addEventListener('click', function (e) {
  var btn = e.target.closest('.copy');
  if (!btn) return;
  navigator.clipboard.writeText(btn.dataset.copy).then(function () {
    btn.textContent = 'copied';
    setTimeout(function () { btn.textContent = 'copy'; }, 1200);
  });
});
"""

FOOTER = """
<footer>
<p><strong>Up/down is not here on purpose.</strong> <code>healthcheck.sh</code> already
publishes per-check state to MQTT every 15 minutes and Home Assistant renders it on the
<strong>Stats</strong> dashboard. This page is the index; Stats is the health view. Two
half-dashboards would be worse than either.</p>
<p>Generated from <code>projects/endpoints/endpoints.toml</code> by
<code>render_endpoints.py</code>. Move a port, edit that file and re-render - do not edit
this page. The private inventory (device specs, which panels have no auth) stays in the
gitignored <code>docs/hardware.md</code>.</p>
</footer>
"""


def main() -> None:
    tailnet = tailnet_suffix()
    data = tomllib.loads(SOURCE.read_text())

    body = []
    count = 0
    for group in data["group"]:
        body.append(f'<h2>{esc(group["name"], tailnet)}</h2>')
        if "blurb" in group:
            body.append(f'<p class="blurb">{esc(group["blurb"], tailnet)}</p>')
        body.append('<div class="grid">')
        for endpoint in group["endpoint"]:
            body.append(render_endpoint(endpoint, tailnet))
            count += 1
        body.append("</div>")

    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Homelab endpoints</title>
<style>{CSS}</style>
</head>
<body>
<div class="page">
<h1>Homelab endpoints</h1>
<p class="sub">{count} endpoints. Everything this house serves, what speaks it, and whether it is
something you can click.</p>
{"".join(f"{line}\n" for line in body)}
{FOOTER}
</div>
<script>{JS}</script>
</body>
</html>
"""
    OUTDIR.mkdir(exist_ok=True)
    (OUTDIR / "index.html").write_text(page)
    print(f"rendered {OUTDIR / 'index.html'} ({count} endpoints, tailnet {tailnet})")


if __name__ == "__main__":
    main()
