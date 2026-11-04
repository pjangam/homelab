// Gathers the open items (see parseProjects) of every open project into
// groups by owner, for the overview panel.

// Owners in the order the overview lists them; anyone else follows in the
// order first seen, then items with no owner.
const OWNER_ORDER = ['pramod', 'together', 'claude']
const CLOSED_SECTIONS = new Set(['done', 'closed-not-acting'])

function ownerRank(owner) {
  if (!owner) return Infinity
  const i = OWNER_ORDER.indexOf(owner.toLowerCase())
  return i === -1 ? OWNER_ORDER.length : i
}

// Every open item across open projects, grouped by owner.
export function collectOpenItems(sections) {
  const groups = new Map()
  for (const section of sections) {
    if (CLOSED_SECTIONS.has(section.id)) continue
    for (const project of section.projects) {
      for (const item of project.openItems ?? []) {
        if (item.done) continue
        const key = item.owner?.toLowerCase() ?? ''
        if (!groups.has(key)) groups.set(key, { owner: item.owner, items: [] })
        groups.get(key).items.push({ ...item, project })
      }
    }
  }
  return [...groups.values()].sort((a, b) => ownerRank(a.owner) - ownerRank(b.owner))
}

