// Driven by render.sh inside the Playwright image; writes PNGs to /out.
// Full-page desktop shots, plus each <svg> on its own at 2x so small pin
// labels are legible when checking for collisions.
import { chromium } from 'playwright'

const browser = await chromium.launch()

for (const scheme of ['light', 'dark']) {
  for (const [name, viewport] of [['desktop', { width: 1100, height: 900 }], ['phone', { width: 390, height: 844 }]]) {
    const page = await browser.newPage({ viewport, colorScheme: scheme, deviceScaleFactor: name === 'desktop' ? 2 : 1 })
    await page.goto('file:///work/page.html', { waitUntil: 'networkidle' })
    await page.screenshot({ path: `/out/${name}-${scheme}.png`, fullPage: true })
    console.log(`wrote ${name}-${scheme}.png`)

    if (name === 'desktop') {
      const svgs = await page.locator('svg[role="img"]').all()
      for (const [i, svg] of svgs.entries()) {
        await svg.screenshot({ path: `/out/svg${i + 1}-${scheme}.png` })
        console.log(`wrote svg${i + 1}-${scheme}.png`)
      }
      // Horizontal page scroll on desktop means something escaped its scroller.
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)
      if (overflow) console.log('WARNING: page scrolls horizontally at desktop width')
    } else {
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth)
      if (overflow) console.log('WARNING: page scrolls horizontally at phone width (diagrams should scroll inside .scroller, not the page)')
    }
    await page.close()
  }
}

await browser.close()
