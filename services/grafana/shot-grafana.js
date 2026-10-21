// Screenshot Grafana dashboards after their panels finish loading, and
// report panels that show "No data" or an error. Run by shot_grafana.sh.
const { chromium } = require('playwright-core');
(async () => {
  const browser = await chromium.launch({ executablePath: '/ms-playwright/chromium_headless_shell-1187/chrome-linux/headless_shell' });
  // The container's POSIX locale makes Chromium report en-US@posix, which
  // Grafana's Intl.NumberFormat rejects at boot - a real browser never does.
  const page = await browser.newPage({ viewport: { width: 1600, height: 4200 }, locale: 'en-US' });
  let bad = 0;
  for (const uid of process.argv.slice(2)) {
    await page.goto(`http://127.0.0.1:3000/grafana/d/${uid}?from=now-1h&to=now`, { waitUntil: 'networkidle' });
    // Wait for uPlot canvases: one per time-series panel once data has drawn.
    await page.waitForSelector('canvas', { timeout: 30000 }).catch(() => {});
    await page.waitForTimeout(6000);
    const canvases = await page.locator('canvas').count();
    console.log(`${uid}: ${canvases} graph canvases drawn`);
    if (!canvases) bad = 1;
    const text = await page.locator('body').innerText();
    if (/failed to load its application files/.test(text)) {
      console.log(`${uid}: Grafana did not boot`); bad = 1;
    }
    const nodata = (text.match(/No data/g) || []).length;
    // Grafana's own marker for a failed query. Not any "error" in a test id
    // or label: that matched the "ZFS errors" panel's title (2026-10-21).
    const errs = await page.locator('[data-testid="data-testid Panel status error"]').count();
    console.log(`${uid}: "No data" x${nodata}, error markers x${errs}`);
    if (nodata || errs) bad = 1;
    await page.screenshot({ path: `/out/grafana-${uid}.png`, fullPage: true });
  }
  await browser.close();
  process.exit(bad);
})();
