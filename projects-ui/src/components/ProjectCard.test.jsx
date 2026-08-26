import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { ProjectCard } from './ProjectCard'

const project = {
  id: 'a-project',
  title: 'A project',
  bodyHtml: '<p>Some <strong>body</strong>.</p>',
}

describe('ProjectCard', () => {
  it('shows the title as the summary', () => {
    render(<ProjectCard project={project} isOpen={false} onToggle={() => {}} />)
    expect(screen.getByText('A project')).toBeInTheDocument()
  })

  it('renders the body html only when open', () => {
    const { rerender } = render(
      <ProjectCard project={project} isOpen={false} onToggle={() => {}} />,
    )
    expect(screen.queryByText('body')).not.toBeVisible()

    rerender(<ProjectCard project={project} isOpen onToggle={() => {}} />)
    expect(screen.getByText('body')).toBeVisible()
  })

  it('calls onToggle with the project id and new open state on click', async () => {
    const onToggle = vi.fn()
    render(<ProjectCard project={project} isOpen={false} onToggle={onToggle} />)

    await userEvent.click(screen.getByText('A project'))

    expect(onToggle).toHaveBeenCalledWith('a-project', true)
  })
})
