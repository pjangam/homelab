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
      <ProjectDetail project={withParts} section={section} inList={false} onToggleInList={onToggleInList} />,
    )

    await userEvent.click(screen.getByLabelText(/add to shopping list/i))

    expect(onToggleInList).toHaveBeenCalledWith('a-project')
  })
})
