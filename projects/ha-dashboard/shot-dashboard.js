// Runs inside the Playwright container (see shot_dashboard.sh). Screenshots
// each given dashboard path and reports any card that failed to render
// (hui-error-card), which is how a bad edit to a YAML dashboard shows up.
const { chromium } = require("playwright-core");

const HA_URL = process.env.HA_URL || "http://localhost:8123";
const paths = process.argv.slice(2);

(async () => {
  const browser = await chromium.launch({
    executablePath: "/ms-playwright/chromium-1187/chrome-linux/chrome",
    args: ["--no-sandbox"],
  });
  const page = await browser.newPage({ viewport: { width: 1400, height: 1800 } });
  await page.addInitScript(([url, token]) => {
    localStorage.setItem("hassTokens", JSON.stringify({
      hassUrl: url, clientId: url + "/", access_token: token,
      refresh_token: "", token_type: "Bearer", expires_in: 1e9,
      expires: Date.now() + 1e12,
    }));
  }, [HA_URL, process.env.HA_TOKEN]);
  let bad = 0;
  for (const p of paths) {
    await page.goto(`${HA_URL}/${p}`);
    await page.waitForTimeout(6000);
    const errors = await page.evaluate(() => {
      const found = [];
      const walk = (r) => { for (const el of r.querySelectorAll("*")) {
        if (el.tagName === "HUI-ERROR-CARD") found.push(el.shadowRoot ? el.shadowRoot.textContent.trim().replace(/\s+/g, " ") : "error card");
        if (el.shadowRoot) walk(el.shadowRoot); } };
      walk(document);
      return found;
    });
    const out = `/out/${p.replace(/\//g, "_")}.png`;
    await page.screenshot({ path: out, fullPage: true });
    console.log(`${p}: ${errors.length} error card(s) -> ${out}`);
    for (const e of errors) console.log("  " + e);
    bad += errors.length;
  }
  await browser.close();
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
