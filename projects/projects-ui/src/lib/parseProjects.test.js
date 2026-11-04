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

describe('priorities', () => {
  const PRIORITISED = `## 💡 Backlog ideas

### Low one
**Priority:** P3

**Why:** later.

### Untagged one
No priority line.

### Urgent one
**Priority:** P1

Do it now.

### Middle one
**Priority:** p2

Soon.

### Another low one
**Priority:** P3

Also later.
`

  it('reads the priority and keeps the line out of the body', () => {
    const [section] = parseProjects(PRIORITISED)
    const urgent = section.projects.find((p) => p.title === 'Urgent one')
    expect(urgent.priority).toBe('P1')
    expect(urgent.bodyHtml).not.toMatch(/Priority/)
    expect(urgent.bodyHtml).toMatch(/Do it now/)
  })

  it('sorts P1, P2, P3, then untagged, keeping file order within a priority', () => {
    const [section] = parseProjects(PRIORITISED)
    expect(section.projects.map((p) => p.title)).toEqual([
      'Urgent one',
      'Middle one',
      'Low one',
      'Another low one',
      'Untagged one',
    ])
    expect(section.projects[4].priority).toBeNull()
  })
})

describe('status lines', () => {
  const FLAT = `# Projects

---

## Projects

### Shipped thing
**Status:** Done

It works.

### Urgent idea
**Status:** Backlog
**Priority:** P1

Soon.

### Running thing
**Status:** Active
**Priority:** P2
**Why:** straight on, no blank line.

### Dropped thing
**Status:** Closed

Decided against.

### Typo thing
**Status:** Actve

Oops.

### Forgotten thing
No status line at all.
`

  it('groups by the Status line, in the fixed status order', () => {
    const groups = parseProjects(FLAT)
    expect(groups.map((g) => g.label)).toEqual([
      'Active',
      'Backlog ideas',
      'Closed (not acting)',
      'Done',
      'Actve',
      'Projects',
    ])
    expect(groups[0].id).toBe('active')
    expect(groups[1].projects[0].title).toBe('Urgent idea')
  })

  it('reads status and priority from one paragraph and keeps them out of the body', () => {
    const [active, backlog] = parseProjects(FLAT)
    expect(backlog.projects[0].priority).toBe('P1')
    expect(backlog.projects[0].bodyHtml).not.toMatch(/Status|Priority/)
    expect(active.projects[0].priority).toBe('P2')
    expect(active.projects[0].bodyHtml).toContain('<strong>Why:</strong> straight on')
    expect(active.projects[0].bodyHtml).not.toMatch(/Status|Priority/)
  })

  it('lets a Status line override the heading a project sits under', () => {
    const groups = parseProjects('## 💡 Backlog ideas\n\n### Moved on\n**Status:** Done\n\nFinished.\n')
    expect(groups.map((g) => g.label)).toEqual(['Done'])
  })

  it('does not treat a Status mention later in the body as the status', () => {
    const groups = parseProjects('## 🟢 Active\n\n### Thing\nBody.\n\n**Status:** Done\n')
    expect(groups.map((g) => g.label)).toEqual(['Active'])
  })
})

describe('open items', () => {
  const WITH_ITEMS = `## Projects

### Diwali lights
**Status:** Active
**Priority:** P1

#### Open items
- [ ] **Pramod:** cover the socket box
- [ ] **Together, 2026-11-04 21:00:** tune the mic, see \`diwali_wled.sh\`
- [x] **Claude:** sunset automation
- [ ] no owner given

**Why:** festival.

#### Log
- 2026-11-03: strip lights.

### No checklist
**Status:** Backlog

**Why:** someday.
`

  const [active, backlog] = parseProjects(WITH_ITEMS)
  const diwali = active.projects[0]

  it('reads the checklist with owner, when and done', () => {
    expect(diwali.openItems.map(({ owner, when, done }) => ({ owner, when, done }))).toEqual([
      { owner: 'Pramod', when: null, done: false },
      { owner: 'Together', when: '2026-11-04 21:00', done: false },
      { owner: 'Claude', when: null, done: true },
      { owner: null, when: null, done: false },
    ])
  })

  it('renders item text as inline html without the owner prefix', () => {
    expect(diwali.openItems[0].html).toBe('cover the socket box')
    expect(diwali.openItems[1].html).toContain('<code>diwali_wled.sh</code>')
  })

  it('keeps the checklist out of the body but not what follows it', () => {
    expect(diwali.bodyHtml).not.toContain('Open items')
    expect(diwali.bodyHtml).not.toContain('cover the socket box')
    expect(diwali.bodyHtml).toContain('<strong>Why:</strong>')
    expect(diwali.bodyHtml).toContain('Log')
    expect(diwali.bodyHtml).toContain('strip lights')
  })

  it('still reads status and priority when the checklist comes first', () => {
    expect(diwali.status).toBe('Active')
    expect(diwali.priority).toBe('P1')
  })

  it('gives an entry without a checklist an empty list', () => {
    expect(backlog.projects[0].openItems).toEqual([])
  })
})
