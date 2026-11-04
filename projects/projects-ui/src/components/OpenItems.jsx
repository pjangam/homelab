// Open items: each entry's "#### Open items" checklist (see parseProjects).
// Shown first in a project's detail, and gathered across every open project
// into one panel above the panes, so "what is waiting, and on whom" reads at
// a glance instead of from the bottom of a long Next step paragraph.

import { collectOpenItems } from '../lib/openItems'

function ItemText({ item }) {
  return (
    <>
      {item.when && <span className="open-item-when">{item.when}</span>}
      {/* Inline html from this repo's own PROJECTS.md - trusted, see ProjectDetail. */}
      <span className="open-item-text" dangerouslySetInnerHTML={{ __html: item.html }} />
    </>
  )
}

// The checklist at the top of one project's detail.
export function ProjectOpenItems({ items }) {
  if (!items?.length) return null
  return (
    <section className="open-items project-open-items" aria-label="Open items">
      <h3>Open items</h3>
      <ul>
        {items.map((item, i) => (
          <li key={i} className={item.done ? 'open-item done' : 'open-item'}>
            <span className="owner-tag" data-owner={item.owner?.toLowerCase() ?? 'none'}>
              {item.owner ?? '—'}
            </span>
            <ItemText item={item} />
          </li>
        ))}
      </ul>
    </section>
  )
}

export function OpenItemsOverview({ sections, onSelect, open, onToggleOpen }) {
  const groups = collectOpenItems(sections)
  const count = groups.reduce((n, g) => n + g.items.length, 0)
  if (count === 0) return null

  return (
    <aside className="open-items open-items-overview" aria-label="Open items across projects">
      <details open={open} onToggle={(e) => onToggleOpen(e.currentTarget.open)}>
        <summary>
          <h2><span aria-hidden="true">📋</span> Open items</h2>
          <span className="open-items-summary">
            {groups.map((g) => `${g.owner ?? 'unassigned'} ${g.items.length}`).join(' · ')}
          </span>
        </summary>
        <div className="open-items-body">
          {groups.map((group) => (
            <section key={group.owner ?? ''} className="open-items-group">
              <h3>
                <span className="owner-tag" data-owner={group.owner?.toLowerCase() ?? 'none'}>
                  {group.owner ?? 'Unassigned'}
                </span>
              </h3>
              <ul>
                {group.items.map((item, i) => (
                  <li key={`${item.project.id}-${i}`} className="open-item">
                    <ItemText item={item} />
                    <button type="button" className="open-item-project" onClick={() => onSelect(item.project.id)}>
                      {item.project.priority && (
                        <span className="priority-badge" data-priority={item.project.priority}>
                          {item.project.priority}
                        </span>
                      )}
                      {item.project.title}
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
      </details>
    </aside>
  )
}
