import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import App from './App'

const MARKDOWN = `## 🟢 Active

### Robot vacuum firmware
Investigating a flaky sensor.

### Second active thing
Nothing interesting here.

## 💡 Backlog ideas

### UI to visualize PROJECTS.md
Would be nice to have a dashboard.
`

async function renderApp() {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: true,
    text: () => Promise.resolve(MARKDOWN),
  }))
  render(<App />)
  await waitFor(() => screen.getByText('Robot vacuum firmware'))
}

describe('App', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('renders every project title grouped under its status', async () => {
    await renderApp()
    expect(screen.getByText('Robot vacuum firmware')).toBeInTheDocument()
    expect(screen.getByText('Second active thing')).toBeInTheDocument()
    expect(screen.getByText('UI to visualize PROJECTS.md')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /active/i })).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /backlog ideas/i })).toBeInTheDocument()
  })

  it('filters projects by search text (title or body)', async () => {
    await renderApp()
    const user = userEvent.setup()

    await user.type(screen.getByPlaceholderText(/search/i), 'flaky sensor')

    expect(screen.getByText('Robot vacuum firmware')).toBeInTheDocument()
    expect(screen.queryByText('Second active thing')).not.toBeInTheDocument()
    expect(screen.queryByText('UI to visualize PROJECTS.md')).not.toBeInTheDocument()
  })

  it('hides a status section entirely when its chip is toggled off', async () => {
    await renderApp()
    const user = userEvent.setup()

    await user.click(screen.getByRole('button', { name: /backlog ideas/i }))

    expect(screen.queryByText('UI to visualize PROJECTS.md')).not.toBeInTheDocument()
    expect(screen.getByText('Robot vacuum firmware')).toBeInTheDocument()
  })

  it('expand all opens every project body, collapse all closes them', async () => {
    await renderApp()
    const user = userEvent.setup()

    await user.click(screen.getByRole('button', { name: /expand all/i }))
    const activeSection = screen.getByText('Robot vacuum firmware').closest('details')
    expect(activeSection).toHaveAttribute('open')

    await user.click(screen.getByRole('button', { name: /collapse all/i }))
    expect(activeSection).not.toHaveAttribute('open')
  })

  it('shows an error message when the fetch fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 500, text: () => Promise.resolve('') }))
    render(<App />)

    await waitFor(() => expect(screen.getByText(/couldn.t load/i)).toBeInTheDocument())
  })
})
