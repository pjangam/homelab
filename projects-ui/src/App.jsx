import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { useProjects } from './hooks/useProjects'
import { StatusSection } from './components/StatusSection'
import { ProjectDetail } from './components/ProjectDetail'
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
function usePersistedState(key, fallback, fromJson = (v) => v, toJson = (v) => v) {
  const [value, setValue] = useState(() => {
    try {
      const stored = localStorage.getItem(key)
      return stored === null ? fallback : fromJson(JSON.parse(stored))
    } catch {
      return fallback // private window, cleared storage, blocked site data
    }
  })

  useEffect(() => {
    try {
      localStorage.setItem(key, JSON.stringify(toJson(value)))
    } catch {
      // Not being able to persist is not a reason to break the page.
    }
  }, [key, value])

  return [value, setValue]
}

function usePersistedSet(key) {
  return usePersistedState(key, new Set(), (list) => new Set(list), (set) => [...set])
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
  const [selectedId, setSelectedId] = useState(null)
  const listScrollY = useRef(0)
  const detailRef = useRef(null)
  const [listIds, setListIds] = usePersistedSet('projects-ui:shopping-list')
  const [checkedItems, setCheckedItems] = usePersistedSet('projects-ui:shopping-checked')
  // Remembered like the list itself: whether it was left open in the shop or
  // tucked away at the desk.
  const [listOpen, setListOpen] = usePersistedState('projects-ui:shopping-open', true)

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

  // Resolved against what is visible, so a search or status filter that hides
  // the selected project empties the detail pane rather than leaving it
  // showing something the list no longer has.
  const selectedSection = visibleSections.find((section) =>
    section.projects.some((p) => p.id === selectedId),
  )
  const selectedProject = selectedSection?.projects.find((p) => p.id === selectedId)
  const view = selectedProject?.id ?? null

  // Each new selection starts at the top of its detail. On a phone the list
  // and the detail take turns on one page, so going back also puts the list
  // back where it was rather than at the top.
  useLayoutEffect(() => {
    if (detailRef.current) detailRef.current.scrollTop = 0
    document.documentElement.scrollTop = view ? 0 : listScrollY.current
  }, [view])

  function select(id) {
    if (!view) listScrollY.current = window.scrollY
    setSelectedId(id)
  }

  function toggleStatus(id) {
    toggleInSet(setDisabledStatuses, id)
  }

  function clearList() {
    setListIds(new Set())
    setCheckedItems(new Set())
  }

  return (
    <div className="app" data-view={view ? 'detail' : 'list'}>
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
          </div>

          {selectedProjects.length > 0 && (
            <ShoppingList
              projects={selectedProjects}
              merged={merged}
              checked={checkedItems}
              onToggleItem={(item) => toggleInSet(setCheckedItems, item)}
              onClear={clearList}
              open={listOpen}
              onToggleOpen={setListOpen}
            />
          )}

          <div className="panes">
            <nav className="list-pane" aria-label="Projects">
              {visibleSections.map((section) => (
                <StatusSection
                  key={section.id}
                  section={section}
                  selectedId={view}
                  onSelect={select}
                />
              ))}
              {visibleSections.length === 0 && (
                <p className="status-message">No projects match.</p>
              )}
            </nav>

            <main className="detail-pane" ref={detailRef}>
              {view && (
                <button type="button" className="back-button" onClick={() => setSelectedId(null)}>
                  ← All projects
                </button>
              )}
              {selectedProject && (
                <ProjectDetail
                  project={selectedProject}
                  section={selectedSection}
                  inList={listIds.has(selectedProject.id)}
                  onToggleInList={(id) => toggleInSet(setListIds, id)}
                />
              )}
              {!view && <p className="detail-placeholder">Pick a project from the list.</p>}
            </main>
          </div>
        </>
      )}
    </div>
  )
}
