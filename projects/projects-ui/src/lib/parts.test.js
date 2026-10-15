import { describe, it, expect } from 'vitest'
import { parseParts, parseCost, mergeParts, formatRange, selectedParts } from './parts'

const AARTI = parseParts(`qty | item | est | note
1 | INMP441 I2S mic | 150-300 | digital, NOT analog
1 | Dupont jumpers | 150 |
5m | WS2812B strip | 1300-2000 | must be 5V
1 | Mystery bracket | | no idea what these cost`)

const LED = parseParts(`3 | 220R resistor | 5 | one per leg
1 | Dupont jumpers | 150 | shared with the aarti build`)

describe('parseParts', () => {
  it('drops the header row and keeps the four fields', () => {
    expect(AARTI).toHaveLength(4)
    expect(AARTI[0]).toEqual({
      qty: '1', item: 'INMP441 I2S mic', est: '150-300', note: 'digital, NOT analog',
    })
  })

  it('tolerates missing trailing fields', () => {
    expect(parseParts('2 | Widget')[0]).toEqual({ qty: '2', item: 'Widget', est: '', note: '' })
  })

  it('ignores blank and commented lines', () => {
    expect(parseParts('\n# just a note\n1 | Thing | 5 |\n')).toHaveLength(1)
  })
})

describe('parseCost', () => {
  it('reads a range and a single value', () => {
    expect(parseCost('150-300')).toEqual({ low: 150, high: 300 })
    expect(parseCost('400')).toEqual({ low: 400, high: 400 })
  })

  it('handles thousands separators', () => {
    expect(parseCost('1,300-2,000')).toEqual({ low: 1300, high: 2000 })
  })

  it('returns null when there is no estimate', () => {
    expect(parseCost('')).toBeNull()
    expect(parseCost(undefined)).toBeNull()
  })
})

describe('mergeParts', () => {
  const merged = mergeParts([
    { title: 'Aarti lights', parts: AARTI },
    { title: 'Clawlight LED', parts: LED },
  ])

  it('merges an item wanted by two projects into one row', () => {
    const jumpers = merged.rows.filter((r) => r.item === 'Dupont jumpers')
    expect(jumpers).toHaveLength(1)
    expect(jumpers[0].sharedBy).toEqual(['Aarti lights', 'Clawlight LED'])
  })

  it('sums quantity and cost for a shared item', () => {
    const jumpers = merged.rows.find((r) => r.item === 'Dupont jumpers')
    expect(jumpers.qty).toBe('2')
    expect(jumpers.cost).toEqual({ low: 300, high: 300 })
  })

  it('keeps units it cannot add side by side rather than guessing', () => {
    expect(merged.rows.find((r) => r.item === 'WS2812B strip').qty).toBe('5m')
  })

  it('carries a note over from whichever project supplied one', () => {
    expect(merged.rows.find((r) => r.item === '220R resistor').note).toBe('one per leg')
  })

  it('counts items with no estimate so the total is not mistaken for a budget', () => {
    expect(merged.withoutEstimate).toBe(1)
    expect(merged.total).toEqual({ low: 1755, high: 2605 })
  })

  it('is empty for no projects', () => {
    expect(mergeParts([]).rows).toEqual([])
  })
})

describe('formatRange', () => {
  it('collapses an exact estimate', () => {
    expect(formatRange(185, 185)).toBe('₹185')
    expect(formatRange(150, 300)).toBe('₹150-300')
  })
})

describe('options', () => {
  const parts = parseParts(`qty | item | est | note
1 | Charger | 200 |
# Option 1 - robot
1 | Robot | 6000 |
# Option 2 - pulley
1 | Motor | 400 |
2 | Microswitch | 40 |`)
  const curtains = { id: 'curtains', title: 'Curtains', parts }

  it('tags rows under a # line with that option, and leaves rows above it untagged', () => {
    expect(parts.map((r) => r.group)).toEqual([undefined, 'Option 1 - robot', 'Option 2 - pulley', 'Option 2 - pulley'])
  })

  it('puts one option plus the shared rows on the list', () => {
    const [picked] = selectedParts([curtains], new Set(['curtains#Option 2 - pulley']))
    expect(picked.title).toBe('Curtains (Option 2 - pulley)')
    expect(picked.parts.map((r) => r.item)).toEqual(['Charger', 'Motor', 'Microswitch'])
  })

  it('still puts every part on the list for a whole-project pick', () => {
    const [picked] = selectedParts([curtains], new Set(['curtains']))
    expect(picked.parts).toHaveLength(4)
  })

  it('leaves unpicked projects off', () => {
    expect(selectedParts([curtains], new Set(['other']))).toEqual([])
  })
})
