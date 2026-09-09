import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest'
import { render, screen, waitFor, within, cleanup } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import App from '../App'

const MARKDOWN = `## 🟢 Active

### Aarti lights
Sound-reactive backdrop.

\`\`\`parts
qty | item | est | note
1 | INMP441 I2S mic | 150-300 | digital, NOT analog
1 | Dupont jumpers | 150 |
\`\`\`

### Clawlight LED
A physical status light.

\`\`\`parts
3 | 220R resistor | 5 | one per leg
1 | Dupont jumpers | 150 |
\`\`\`

### Project with no parts
Nothing to buy here.
`

async function renderApp() {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: true,
    text: () => Promise.resolve(MARKDOWN),
  }))
  render(<App />)
  await waitFor(() => screen.getAllByText('Aarti lights'))
}

async function addToList(user, projectTitle) {
  const card = screen.getByText(projectTitle).closest('details')
  await user.click(within(card).getByLabelText(/add to shopping list/i))
}

describe('shopping list', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('shows no list until a project is added', async () => {
    await renderApp()
    expect(screen.queryByRole('complementary', { name: /shopping list/i })).not.toBeInTheDocument()
  })

  it('offers the checkbox only for projects that have parts', async () => {
    await renderApp()
    const bare = screen.getByText('Project with no parts').closest('details')
    expect(within(bare).queryByLabelText(/add to shopping list/i)).not.toBeInTheDocument()
  })

  it('merges a shared item across two projects into one line', async () => {
    await renderApp()
    const user = userEvent.setup()
    await addToList(user, 'Aarti lights')
    await addToList(user, 'Clawlight LED')

    const list = screen.getByRole('complementary', { name: /shopping list/i })
    expect(within(list).getAllByText('Dupont jumpers')).toHaveLength(1)
    expect(within(list).getByText('shared')).toBeInTheDocument()
    // 150 + 150 for the jumpers, 150-300 mic, 5 resistors.
    expect(within(list).getByText(/₹455-605/)).toBeInTheDocument()
  })

  it('keeps a ticked item visible rather than removing it', async () => {
    await renderApp()
    const user = userEvent.setup()
    await addToList(user, 'Clawlight LED')

    const list = screen.getByRole('complementary', { name: /shopping list/i })
    await user.click(within(list).getByRole('checkbox', { name: /220R resistor/i }))
    expect(within(list).getByText('220R resistor')).toBeInTheDocument()
  })

  it('survives a reload, since the list is used away from the machine', async () => {
    await renderApp()
    const user = userEvent.setup()
    await addToList(user, 'Aarti lights')
    expect(screen.getByRole('complementary', { name: /shopping list/i })).toBeInTheDocument()

    vi.unstubAllGlobals()
    cleanup()
    await renderApp()
    const list = await screen.findByRole('complementary', { name: /shopping list/i })
    expect(within(list).getByText('INMP441 I2S mic')).toBeInTheDocument()
  })
})
