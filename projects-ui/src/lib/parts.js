// Parts lists live in PROJECTS.md as fenced ```parts blocks:
//
//   qty | item | est | note
//   1 | INMP441 I2S mic | 150-300 | digital, NOT analog MAX4466
//
// Buying happens per shop trip, not per project, so the useful question is
// "what do I need to walk out with today" across the two or three projects
// being started at once - which is what mergeParts answers.

export function parseParts(text) {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .map((line) => {
      const [qty = '', item = '', est = '', note = ''] = line.split('|').map((f) => f.trim())
      return { qty, item, est, note }
    })
    // Drop the optional header row, and any line with no item to buy.
    .filter((row) => row.item && row.qty.toLowerCase() !== 'qty')
}

// '150-300' -> {low:150, high:300}; '400' -> {low:400, high:400}; '' -> null.
export function parseCost(est) {
  const numbers = (est || '').match(/[\d,]+/g)
  if (!numbers) return null
  const values = numbers.map((n) => Number(n.replace(/,/g, '')))
  return { low: values[0], high: values[values.length - 1] }
}

// ['1','1'] -> '2'. Units we can't add ('5m','2m') stay side by side.
function mergeQty(quantities) {
  const present = quantities.filter(Boolean)
  if (present.length && present.every((q) => /^\d+$/.test(q))) {
    return String(present.reduce((sum, q) => sum + Number(q), 0))
  }
  return present.join(' + ')
}

export function formatRange(low, high) {
  // 185-185 reads as a guess; 185 does not.
  return low === high ? `₹${low}` : `₹${low}-${high}`
}

/**
 * Merge the parts of several projects into one list.
 *
 * Quantities and costs are summed for an item wanted by more than one
 * project. That is right for a part each build consumes (two projects needing
 * an ESP32 need two) and wrong for a shared consumable (one pack of jumper
 * wires covers both), and the parts syntax cannot tell them apart - so it errs
 * high and flags them via `sharedBy`, rather than quietly under-budgeting.
 *
 * @param {{title: string, parts: Array}[]} projects
 */
export function mergeParts(projects) {
  const byItem = new Map()

  for (const project of projects) {
    for (const row of project.parts ?? []) {
      const key = row.item.toLowerCase()
      const entry = byItem.get(key) ?? {
        item: row.item,
        quantities: [],
        cost: null,
        note: '',
        sharedBy: [],
      }
      entry.quantities.push(row.qty)
      if (!entry.sharedBy.includes(project.title)) entry.sharedBy.push(project.title)
      if (row.note && !entry.note) entry.note = row.note

      const cost = parseCost(row.est)
      if (cost) {
        entry.cost = entry.cost
          ? { low: entry.cost.low + cost.low, high: entry.cost.high + cost.high }
          : cost
      }
      byItem.set(key, entry)
    }
  }

  const rows = [...byItem.values()].map((entry) => ({
    item: entry.item,
    qty: mergeQty(entry.quantities),
    cost: entry.cost,
    note: entry.note,
    sharedBy: entry.sharedBy,
  }))

  const known = rows.filter((row) => row.cost)
  return {
    rows,
    total: {
      low: known.reduce((sum, row) => sum + row.cost.low, 0),
      high: known.reduce((sum, row) => sum + row.cost.high, 0),
    },
    // Counted so the UI can say the total is a floor rather than a budget.
    withoutEstimate: rows.length - known.length,
  }
}
