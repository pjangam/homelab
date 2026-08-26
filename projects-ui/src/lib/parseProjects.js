import { marked } from 'marked'

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
      currentProject = { id: slugify(token.text), title: token.text, tokens: [] }
      currentSection.projects.push(currentProject)
    } else if (currentProject) {
      currentProject.tokens.push(token)
    }
  }

  for (const section of sections) {
    for (const project of section.projects) {
      project.bodyHtml = marked.parser(project.tokens)
      delete project.tokens
    }
  }

  return sections
}
