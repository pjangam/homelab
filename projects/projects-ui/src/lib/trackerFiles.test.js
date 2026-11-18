import { describe, it, expect } from 'vitest'
import { combineTrackerFiles, trackerFileNames } from './trackerFiles'
import { parseProjects } from './parseProjects'

describe('trackerFileNames', () => {
  it('keeps project .md files, sorted, and drops README.md and directories', () => {
    const listing = [
      { name: 'b.md', type: 'file' },
      { name: 'README.md', type: 'file' },
      { name: 'a.md', type: 'file' },
      { name: 'images', type: 'directory' },
      { name: 'notes.txt', type: 'file' },
    ]
    expect(trackerFileNames(listing)).toEqual(['a.md', 'b.md'])
  })
})

describe('combineTrackerFiles', () => {
  it('joins files into the one-file shape parseProjects reads', () => {
    const md = combineTrackerFiles([
      '# One\n**Status:** Active\n**Priority:** P2\n**Cost:** ₹1,500-2,500\n**Effort:** ~2 weekends\n\n#### Open items\n- [ ] **Claude:** do it\n\nBody one.\n',
      '# Two\n**Status:** Done\n**Actual cost:** ₹900\n\n#### Log\n- 2026-11-18: done\n',
    ])
    const groups = parseProjects(md)
    const [one] = groups.find((g) => g.id === 'active').projects
    expect(one).toMatchObject({
      id: 'one', title: 'One', status: 'Active', priority: 'P2', cost: '₹1,500-2,500', effort: '~2 weekends',
    })
    expect(one.openItems).toHaveLength(1)
    expect(one.bodyHtml).toContain('Body one.')
    expect(one.bodyHtml).not.toContain('Cost')
    const [two] = groups.find((g) => g.id === 'done').projects
    expect(two.actualCost).toBe('₹900')
    expect(two.bodyHtml).toContain('<h4>Log</h4>')
  })

  it('leaves a # inside a project body alone', () => {
    const md = combineTrackerFiles(['# One\n**Status:** Active\n\n```sh\n# a comment\n```\n'])
    expect(parseProjects(md)[0].projects[0].bodyHtml).toContain('# a comment')
  })
})
