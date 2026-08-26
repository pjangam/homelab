import { useMemo, useState } from 'react'
import { useProjects } from './hooks/useProjects'
import { StatusSection } from './components/StatusSection'
import './App.css'

function matchesSearch(project, term) {
  if (!term) return true
  const haystack = `${project.title} ${project.bodyHtml}`.toLowerCase()
  return haystack.includes(term.toLowerCase())
}

export default function App() {
  const { status, sections, error } = useProjects()
  const [search, setSearch] = useState('')
  const [disabledStatuses, setDisabledStatuses] = useState(() => new Set())
  const [openIds, setOpenIds] = useState(() => new Set())

  const visibleSections = useMemo(
    () =>
      sections
        .filter((section) => !disabledStatuses.has(section.id))
        .map((section) => ({
          ...section,
          projects: section.projects.filter((project) => matchesSearch(project, search)),
        }))
        .filter((section) => section.projects.length > 0),
    [sections, disabledStatuses, search],
  )

  function toggleStatus(id) {
    setDisabledStatuses((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function toggleProject(id, isOpen) {
    setOpenIds((prev) => {
      const next = new Set(prev)
      if (isOpen) next.add(id)
      else next.delete(id)
      return next
    })
  }

  function expandAll() {
    setOpenIds(new Set(sections.flatMap((section) => section.projects.map((p) => p.id))))
  }

  function collapseAll() {
    setOpenIds(new Set())
  }

  return (
    <div className="app">
      <header>
        <h1>Homelab Projects</h1>
        <p className="subtitle">Live view of PROJECTS.md</p>
      </header>

      {status === 'loading' && <p className="status-message">Loading…</p>}
      {status === 'error' && (
        <p className="status-message error">Couldn&rsquo;t load PROJECTS.md: {error.message}</p>
      )}

      {status === 'ready' && (
        <>
          <div className="controls">
            <div className="chips">
              {sections.map((section) => {
                const active = !disabledStatuses.has(section.id)
                return (
                  <button
                    key={section.id}
                    type="button"
                    aria-pressed={active}
                    className={`chip${active ? ' chip-active' : ''}`}
                    data-status={section.id}
                    onClick={() => toggleStatus(section.id)}
                  >
                    {section.emoji} {section.label}
                  </button>
                )
              })}
            </div>
            <input
              type="search"
              placeholder="Search projects…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <div className="expand-controls">
              <button type="button" onClick={expandAll}>Expand all</button>
              <button type="button" onClick={collapseAll}>Collapse all</button>
            </div>
          </div>

          <main>
            {visibleSections.map((section) => (
              <StatusSection
                key={section.id}
                section={section}
                openIds={openIds}
                onToggleProject={toggleProject}
              />
            ))}
            {visibleSections.length === 0 && (
              <p className="status-message">No projects match.</p>
            )}
          </main>
        </>
      )}
    </div>
  )
}
