import { marked } from 'marked'
import { parseParts } from './parts'

function slugify(text) {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\w]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

// Headings in PROJECTS.md always look like "🟢 Active" - emoji, space, label.
function splitEmoji(text) {
  const spaceIndex = text.indexOf(' ')
  if (spaceIndex === -1) return { emoji: '', label: text }
  return { emoji: text.slice(0, spaceIndex), label: text.slice(spaceIndex + 1) }
}

// A project's priority is its own paragraph, "**Priority:** P1", straight
// under the heading. Lower number = more urgent.
const PRIORITY_LINE = /^\*\*Priority:\*\*\s*(P[1-3])\s*$/i
export const PRIORITIES = ['P1', 'P2', 'P3']

// Most urgent first; a project with no priority (Done, Closed) sorts last.
function priorityRank(project) {
  const i = PRIORITIES.indexOf(project.priority)
  return i === -1 ? PRIORITIES.length : i
}

// PROJECTS.md structure: "## <emoji> Status" sections, each containing
// "### Project name" entries followed by free-form markdown until the next
// heading. Content before the first "##" (the file's own title/intro) is
// intentionally dropped - it's not a project.
export function parseProjects(markdown) {
  const tokens = marked.lexer(markdown)
  const sections = []
  let currentSection = null
  let currentProject = null

  for (const token of tokens) {
    if (token.type === 'heading' && token.depth === 2) {
      const { emoji, label } = splitEmoji(token.text)
      currentSection = { id: slugify(token.text), emoji, label, projects: [] }
      sections.push(currentSection)
      currentProject = null
    } else if (token.type === 'heading' && token.depth === 3 && currentSection) {
      currentProject = {
        id: slugify(token.text),
        title: token.text,
        priority: null,
        tokens: [],
        parts: [],
      }
      currentSection.projects.push(currentProject)
    } else if (currentProject && token.type === 'code' && token.lang === 'parts') {
      // Held out of the body deliberately: a parts block is data, and gets
      // rendered as a table plus a shopping-list checkbox rather than as the
      // raw code block marked would otherwise produce.
      currentProject.parts.push(...parseParts(token.text))
    } else if (
      currentProject &&
      token.type === 'paragraph' &&
      PRIORITY_LINE.test(token.raw.trim())
    ) {
      // Held out of the body too: it is shown as a badge, not as text.
      currentProject.priority = token.raw.trim().match(PRIORITY_LINE)[1].toUpperCase()
    } else if (currentProject) {
      currentProject.tokens.push(token)
    }
  }

  for (const section of sections) {
    for (const project of section.projects) {
      project.bodyHtml = marked.parser(project.tokens)
      delete project.tokens
    }
    // Stable sort, so equal priorities keep their order in the file.
    section.projects.sort((a, b) => priorityRank(a) - priorityRank(b))
  }

  return sections
}
