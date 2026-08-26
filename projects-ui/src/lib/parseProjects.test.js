import { describe, it, expect } from 'vitest'
import { parseProjects } from './parseProjects'

const SAMPLE = `# Projects

Intro paragraph, not part of any section.

---

## 🟢 Active

### First project
**Why:** it matters.
**State:** in progress.

### Second project
Some body text.

---

## 💡 Backlog ideas

### Someday idea
Not started.
`

describe('parseProjects', () => {
  it('groups projects under their status section', () => {
    const sections = parseProjects(SAMPLE)
    expect(sections).toHaveLength(2)
    expect(sections[0].projects).toHaveLength(2)
    expect(sections[1].projects).toHaveLength(1)
  })

  it('splits the emoji from the section label', () => {
    const [active, backlog] = parseProjects(SAMPLE)
    expect(active.emoji).toBe('🟢')
    expect(active.label).toBe('Active')
    expect(backlog.emoji).toBe('💡')
    expect(backlog.label).toBe('Backlog ideas')
  })

  it('captures project titles in order', () => {
    const [active] = parseProjects(SAMPLE)
    expect(active.projects.map((p) => p.title)).toEqual([
      'First project',
      'Second project',
    ])
  })

  it('renders each project body to html', () => {
    const [active] = parseProjects(SAMPLE)
    expect(active.projects[0].bodyHtml).toContain('<strong>Why:</strong>')
    expect(active.projects[1].bodyHtml).toContain('Some body text.')
  })

  it('gives every section and project a stable, url-safe id', () => {
    const [active] = parseProjects(SAMPLE)
    expect(active.id).toBe('active')
    expect(active.projects[0].id).toBe('first-project')
  })

  it('ignores content before the first status heading', () => {
    const sections = parseProjects(SAMPLE)
    const allTitles = sections.flatMap((s) => s.projects.map((p) => p.title))
    expect(allTitles).not.toContain('Projects')
  })

  it('returns an empty list for markdown with no status headings', () => {
    expect(parseProjects('# Just a title\n\nSome text.\n')).toEqual([])
  })
})
