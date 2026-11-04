import { describe, it, expect, vi } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { OpenItemsOverview, ProjectOpenItems } from './OpenItems'
import { collectOpenItems } from '../lib/openItems'

const item = (owner, html, extra = {}) => ({ owner, when: null, done: false, html, ...extra })

const diwali = {
  id: 'diwali',
  title: 'Diwali lights',
  priority: 'P1',
  openItems: [
    item('Claude', 'update hardware.md'),
    item('Pramod', 'cover the boxes'),
    item('Together', 'tune the mic', { when: '04 Nov 21:00' }),
    item('Pramod', 'already done', { done: true }),
  ],
}
const shipped = { id: 'old', title: 'Old thing', openItems: [item('Pramod', 'stale item in a Done entry')] }
const sections = [
  { id: 'active', projects: [diwali] },
  { id: 'done', projects: [shipped] },
]

describe('collectOpenItems', () => {
  it('groups by owner, Pramod then Together then Claude, skipping done items and closed projects', () => {
    const groups = collectOpenItems(sections)
    expect(groups.map((g) => [g.owner, g.items.map((i) => i.html)])).toEqual([
      ['Pramod', ['cover the boxes']],
      ['Together', ['tune the mic']],
      ['Claude', ['update hardware.md']],
    ])
  })
})

describe('OpenItemsOverview', () => {
  it('shows each item with its project, and selects the project on click', async () => {
    const onSelect = vi.fn()
    render(<OpenItemsOverview sections={sections} onSelect={onSelect} open onToggleOpen={() => {}} />)
    const panel = screen.getByRole('complementary', { name: /open items across projects/i })
    expect(within(panel).getByText('cover the boxes')).toBeInTheDocument()
    expect(within(panel).getByText('04 Nov 21:00')).toBeInTheDocument()
    expect(within(panel).queryByText(/stale item/)).not.toBeInTheDocument()

    await userEvent.click(within(panel).getAllByRole('button', { name: /diwali lights/i })[0])
    expect(onSelect).toHaveBeenCalledWith('diwali')
  })

  it('renders nothing when no open project has items', () => {
    const { container } = render(
      <OpenItemsOverview sections={[{ id: 'active', projects: [] }]} onSelect={() => {}} open onToggleOpen={() => {}} />,
    )
    expect(container).toBeEmptyDOMElement()
  })
})

describe('ProjectOpenItems', () => {
  it('lists every item with its owner, done ones included', () => {
    render(<ProjectOpenItems items={diwali.openItems} />)
    const list = screen.getByRole('region', { name: 'Open items' })
    expect(within(list).getAllByRole('listitem')).toHaveLength(4)
    expect(within(list).getAllByText('Pramod')).toHaveLength(2)
  })

  it('renders nothing for an entry without a checklist', () => {
    const { container } = render(<ProjectOpenItems items={[]} />)
    expect(container).toBeEmptyDOMElement()
  })
})
