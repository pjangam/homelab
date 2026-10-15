import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ProjectDetail } from './ProjectDetail'

const section = { id: 'active', emoji: '🟢', label: 'Active' }

const project = {
  id: 'a-project',
  title: 'A project',
  bodyHtml: '<p>Some <strong>body</strong>.</p>',
  parts: [],
}

const withParts = {
  ...project,
  parts: [{ qty: '1', item: 'INMP441 I2S mic', est: '150-300', note: '' }],
}

describe('ProjectDetail', () => {
  it('shows the title, status and body', () => {
    render(<ProjectDetail project={project} section={section} />)
    expect(screen.getByRole('heading', { name: 'A project' })).toBeInTheDocument()
    expect(screen.getByText('Active')).toBeInTheDocument()
    expect(screen.getByText('body')).toBeVisible()
  })

  it('leaves the parts table out for a project with no parts', () => {
    render(<ProjectDetail project={project} section={section} />)
    expect(screen.queryByRole('heading', { name: 'Parts' })).not.toBeInTheDocument()
  })

  it('calls onToggleInList with the project id when the checkbox is ticked', async () => {
    const onToggleInList = vi.fn()
    render(
      <ProjectDetail project={withParts} section={section} listIds={new Set()} onToggleInList={onToggleInList} />,
    )

    await userEvent.click(screen.getByLabelText(/add to shopping list/i))

    expect(onToggleInList).toHaveBeenCalledWith('a-project')
  })

  const withOptions = {
    ...project,
    parts: [
      { qty: '1', item: 'Charger', est: '200', note: '' },
      { qty: '1', item: 'Robot', est: '6000', note: '', group: 'Option 1 - robot' },
      { qty: '1', item: 'Motor', est: '400', note: '', group: 'Option 2 - pulley' },
    ],
  }

  it('gives each option its own checkbox, keyed by project and option', async () => {
    const onToggleInList = vi.fn()
    render(
      <ProjectDetail project={withOptions} section={section} listIds={new Set()} onToggleInList={onToggleInList} />,
    )

    expect(screen.queryByLabelText('Add to shopping list')).not.toBeInTheDocument()
    await userEvent.click(screen.getByLabelText('Add Option 2 - pulley to shopping list'))

    expect(onToggleInList).toHaveBeenCalledWith('a-project#Option 2 - pulley')
  })

  it('keeps the whole-project checkbox while an old whole-project pick is on the list', () => {
    render(
      <ProjectDetail project={withOptions} section={section} listIds={new Set(['a-project'])} onToggleInList={() => {}} />,
    )
    expect(screen.getByLabelText('Add to shopping list')).toBeChecked()
  })
})
