import { useEffect, useMemo, useState } from 'react'
import { useProjects } from './hooks/useProjects'
import { StatusSection } from './components/StatusSection'
import { ShoppingList } from './components/ShoppingList'
import { mergeParts } from './lib/parts'
import './App.css'

function matchesSearch(project, term) {
  if (!term) return true
  const haystack = `${project.title} ${project.bodyHtml}`.toLowerCase()
  return haystack.includes(term.toLowerCase())
}

// The shopping list is used standing in a shop on a phone, so it has to
// survive a reload and a screen lock. localStorage is per-browser and that is
// exactly right here - this is one person's trip, not shared state.
function usePersistedSet(key) {
  const [value, setValue] = useState(() => {
    try {
      return new Set(JSON.parse(localStorage.getItem(key) ?? '[]'))
    } catch {
      return new Set() // private window, cleared storage, blocked site data
    }
  })

  useEffect(() => {
    try {
      localStorage.setItem(key, JSON.stringify([...value]))
    } catch {
      // Not being able to persist is not a reason to break the page.
    }
  }, [key, value])

  return [value, setValue]
}

function toggleInSet(setter, id) {
  setter((prev) => {
    const next = new Set(prev)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    return next
  })
}

export default function App() {
  const { status, sections, error } = useProjects()
  const [search, setSearch] = useState('')
  const [disabledStatuses, setDisabledStatuses] = useState(() => new Set())
  const [openIds, setOpenIds] = useState(() => new Set())
  const [listIds, setListIds] = usePersistedSet('projects-ui:shopping-list')
  const [checkedItems, setCheckedItems] = usePersistedSet('projects-ui:shopping-checked')

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

  // Selected from every section, not just the visible ones - a status filter
  // or a search term must not silently drop items from the list you are
  // standing in a shop holding.
  const selectedProjects = useMemo(
    () => sections.flatMap((section) => section.projects).filter((p) => listIds.has(p.id)),
    [sections, listIds],
  )
  const merged = useMemo(() => mergeParts(selectedProjects), [selectedProjects])

  function toggleStatus(id) {
    toggleInSet(setDisabledStatuses, id)
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

  function clearList() {
    setListIds(new Set())
    setCheckedItems(new Set())
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

          {selectedProjects.length > 0 && (
            <ShoppingList
              projects={selectedProjects}
              merged={merged}
              checked={checkedItems}
              onToggleItem={(item) => toggleInSet(setCheckedItems, item)}
              onClear={clearList}
            />
          )}

          <main>
            {visibleSections.map((section) => (
              <StatusSection
                key={section.id}
                section={section}
                openIds={openIds}
                onToggleProject={toggleProject}
                listIds={listIds}
                onToggleInList={(id) => toggleInSet(setListIds, id)}
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
