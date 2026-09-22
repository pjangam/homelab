// Runs inside the Playwright container (see dump_overview.sh). Logs into HA's
// frontend with a long-lived token, opens the auto-generated Overview and
// prints it fully expanded, as JSON: every strategy - the dashboard's, each
// view's and each section's - replaced by the config it generated, so the
// result is a plain dashboard that renders the same without any strategy.
//
// Overview is the Home panel since 2025.x (/lovelace redirects to it); a
// classic dashboard still renders as ha-panel-lovelace, so DASH=<url_path>
// dumps one of those too.
const { chromium } = require("playwright-core");

const HA_URL = process.env.HA_URL || "http://localhost:8123";
const TOKEN = process.env.HA_TOKEN;
const DASH = process.env.DASH || "home";

// Walk the shadow DOM from <home-assistant> down to the panel's hui-root.
const FIND = `
  const q = (el, sel) => el && el.shadowRoot && el.shadowRoot.querySelector(sel);
  const main = q(document.querySelector("home-assistant"), "home-assistant-main");
  const panel = main && (main.shadowRoot.querySelector("ha-panel-home") || main.shadowRoot.querySelector("ha-panel-lovelace"));
  const lovelace = panel && (panel._lovelace || panel.lovelace);
  const root = q(panel, "hui-root");
  const view = q(root, "hui-view");
  const sections = [];
  const walk = (r) => { for (const el of r.querySelectorAll("*")) { if (el.tagName === "HUI-SECTION") sections.push(el); if (el.shadowRoot) walk(el.shadowRoot); } };
  if (view) { walk(view); if (view.shadowRoot) walk(view.shadowRoot); }
`;

async function grab(page, expr, what) {
  const h = await page.waitForFunction(expr, null, { timeout: 60000 }).catch(async (e) => {
    await page.screenshot({ path: "/out/dump-overview-fail.png" }).catch(() => {});
    console.error(`stuck waiting for ${what} at ${page.url()}`);
    console.error(await page.evaluate(`(() => { ${FIND} const v = view && view._config; return JSON.stringify({path: v && v.path, strategy: !!(v && v.strategy), n: v && (v.sections || []).length, rendered: sections.length, cfgs: sections.map((s) => !!s._config), types: v && (v.sections||[]).map(s => s.strategy ? "S:" + s.strategy.type : s.type)}); })()`).catch(String));
    throw e;
  });
  return JSON.parse(await h.jsonValue());
}

(async () => {
  const browser = await chromium.launch({
    executablePath: "/ms-playwright/chromium-1187/chrome-linux/chrome",
    args: ["--no-sandbox"],
  });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  // Seed the frontend's token store so it skips the login page.
  await page.addInitScript(([url, token]) => {
    localStorage.setItem("hassTokens", JSON.stringify({
      hassUrl: url, clientId: url + "/", access_token: token,
      refresh_token: "", token_type: "Bearer", expires_in: 1e9,
      expires: Date.now() + 1e12,
    }));
  }, [HA_URL, TOKEN]);

  await page.goto(`${HA_URL}/${DASH}`);
  const dash = await grab(page, `(() => { ${FIND}
    const c = lovelace && lovelace.config;
    return c && c.views && c.views.length ? JSON.stringify(c) : null; })()`, "dashboard config");

  const views = [];
  for (const [i, raw] of dash.views.entries()) {
    const path = raw.path || String(i);
    await page.goto(`${HA_URL}/${DASH}/${path}`);
    // A view's own strategy is expanded into hui-view._config. Its sections
    // (and a sections view's sidebar) may be strategies too, each expanded
    // into its hui-section's _config; the element's .config is the very
    // object from the view config, which is how each one is matched back.
    const got = await grab(page, `(() => { ${FIND}
      const v = view && view._config;
      if (!v || v.strategy || (v.path || "") !== ${JSON.stringify(raw.path || "")}) return null;
      const out = { view: v, expanded: [] };
      for (const where of ["sections", "sidebar"]) {
        const list = where === "sections" ? v.sections : v.sidebar && v.sidebar.sections;
        for (const [j, sec] of (list || []).entries()) {
          if (!sec.strategy) continue;
          const el = sections.find((e) => e.config === sec);
          if (!el || !el._config || el._config.strategy) return null;
          out.expanded.push({ where, j, cfg: el._config });
        }
      }
      return JSON.stringify(out); })()`, `view ${path}`);
    const v = got.view;
    for (const { where, j, cfg } of got.expanded)
      (where === "sections" ? v.sections : v.sidebar.sections)[j] = cfg;
    const left = JSON.stringify(v).includes('"strategy"');
    if (left) console.error(`warning: view ${path} still contains a strategy`);
    views.push(v);
  }
  const { strategy, ...rest } = dash;
  process.stdout.write(JSON.stringify({ ...rest, views }));
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
