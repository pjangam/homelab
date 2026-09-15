// Driven by screenshot.sh inside the Playwright image; writes PNGs to /out.
import { chromium } from 'playwright'

const url = process.env.URL
const browser = await chromium.launch()

async function shoot(page, name) {
  await page.screenshot({ path: `/out/${name}.png` })
  console.log(`wrote ${name}.png`)
}

// Desktop: pick a project that has parts, add it to the shopping list, then
// collapse the list.
{
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 } })
  await page.goto(url)
  await page.getByRole('navigation').getByRole('button').first().waitFor()
  await shoot(page, 'desktop-1-initial')

  await page.locator('.project-link', { has: page.locator('.parts-badge') }).first().click()
  await shoot(page, 'desktop-2-selected')

  const add = page.getByLabel(/add to shopping list/i)
  if (!(await add.isChecked())) await add.check()
  await shoot(page, 'desktop-3-shopping-list-open')

  await page.getByRole('complementary', { name: /shopping list/i }).locator('summary').click()
  await shoot(page, 'desktop-4-shopping-list-collapsed')
  await page.close()
}

// Phone: the panes take turns.
{
  const page = await browser.newPage({ viewport: { width: 400, height: 860 }, isMobile: true, hasTouch: true })
  await page.goto(url)
  await page.getByRole('navigation').getByRole('button').first().waitFor()
  await shoot(page, 'phone-1-list')

  await page.getByRole('navigation').getByRole('button').nth(2).click()
  await shoot(page, 'phone-2-detail')
  await page.close()
}

await browser.close()
