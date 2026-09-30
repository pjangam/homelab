import { marked } from 'marked'
import { parseParts } from './parts'

function slugify(text) {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\w]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

// Status and priority are lines of their own straight under a project's
// heading, so moving a project is a one-line diff rather than moving the
// whole block between sections:
//
//   ### Some project
//   **Status:** Backlog
//   **Priority:** P1
//
// A project without a Status line falls back to the "## ..." heading it sits
// under, which is how the file was organised before these lines existed.
const META_LINE = /^\*\*(Status|Priority):\*\*\s*(.*?)\s*$/i
const PRIORITY_VALUE = /^P[1-3]$/i
export const PRIORITIES = ['P1', 'P2', 'P3']

// Display order of the groups. `id` is kept equal to what the old section
// headings slugified to, so the CSS hooks and chips carry on unchanged.
export const STATUSES = [
  { key: 'active', id: 'active', emoji: '🟢', label: 'Active' },
  { key: 'parked', id: 'parked', emoji: '🟡', label: 'Parked' },
  { key: 'backlog', id: 'backlog-ideas', emoji: '💡', label: 'Backlog ideas' },
  { key: 'closed', id: 'closed-not-acting', emoji: '⚪', label: 'Closed (not acting)' },
  { key: 'done', id: 'done', emoji: '✅', label: 'Done' },
]

// "Backlog", "backlog ideas", "Closed (not acting)" all resolve by first word.
function findStatus(text) {
  const word = text.trim().toLowerCase().split(/[^a-z]+/)[0]
  return STATUSES.find((status) => status.key === word)
}

// Most urgent first; a project with no priority (Done, Closed) sorts last.
function priorityRank(project) {
  const i = PRIORITIES.indexOf(project.priority)
  return i === -1 ? PRIORITIES.length : i
}

// Peels Status/Priority lines off the start of a project's first paragraph.
// Returns the markdown left over (usually none), or null if the paragraph
// does not start with one - then it is ordinary body text.
function takeMeta(project, paragraph) {
  const lines = paragraph.raw.replace(/\n+$/, '').split('\n')
  let taken = 0
  for (const line of lines) {
    const match = line.match(META_LINE)
    if (!match) break
    const [, field, value] = match
    if (field.toLowerCase() === 'priority' && PRIORITY_VALUE.test(value)) {
      project.priority = value.toUpperCase()
    } else if (field.toLowerCase() === 'status') {
      project.status = value
    }
    taken++
  }
  if (taken === 0) return null
  return lines.slice(taken).join('\n')
}

function slugifyGroup(label) {
  return slugify(label) || 'no-status'
}

// PROJECTS.md structure: "### Project name" entries, each followed by
// free-form markdown until the next heading, grouped by their Status line.
// Content before the first "##" (the file's own title/intro) is
// intentionally dropped - it's not a project.
export function parseProjects(markdown) {
  const tokens = marked.lexer(markdown)
  const projects = []
  let heading = null
  let currentProject = null

  for (const token of tokens) {
    if (token.type === 'heading' && token.depth === 2) {
      heading = token.text
      currentProject = null
    } else if (token.type === 'heading' && token.depth === 3 && heading !== null) {
      currentProject = {
        id: slugify(token.text),
        title: token.text,
        heading,
        status: null,
        priority: null,
        tokens: [],
        parts: [],
      }
      projects.push(currentProject)
    } else if (currentProject && token.type === 'code' && token.lang === 'parts') {
      // Held out of the body deliberately: a parts block is data, and gets
      // rendered as a table plus a shopping-list checkbox rather than as the
      // raw code block marked would otherwise produce.
      currentProject.parts.push(...parseParts(token.text))
    } else if (currentProject && token.type === 'paragraph' && currentProject.tokens.length === 0) {
      // Held out too: status and priority are shown as a group and a badge.
      const rest = takeMeta(currentProject, token)
      if (rest === null) currentProject.tokens.push(token)
      else if (rest.trim()) currentProject.tokens.push(...marked.lexer(rest))
    } else if (currentProject) {
      currentProject.tokens.push(token)
    }
  }

  // Known statuses in their fixed order, then anything else (a typo'd status,
  // or a project under a non-status heading) in the order first seen, so a
  // mistake shows up as its own group rather than vanishing.
  const groups = STATUSES.map(({ key, ...status }) => ({ ...status, projects: [] }))
  for (const project of projects) {
    const label = project.status ?? project.heading
    const known = findStatus(label) ?? (project.status ? null : findStatus(project.heading))
    let group = known && groups[STATUSES.indexOf(known)]
    if (!group) {
      const id = slugifyGroup(label)
      group = groups.find((g) => g.id === id)
      if (!group) {
        group = { id, emoji: '❔', label: label || 'No status', projects: [] }
        groups.push(group)
      }
    }
    project.bodyHtml = marked.parser(project.tokens)
    delete project.tokens
    delete project.heading
    group.projects.push(project)
  }

  for (const group of groups) {
    // Stable sort, so equal priorities keep their order in the file.
    group.projects.sort((a, b) => priorityRank(a) - priorityRank(b))
  }
  return groups.filter((group) => group.projects.length > 0)
}
