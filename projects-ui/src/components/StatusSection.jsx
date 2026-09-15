// One status group in the left-hand list: titles only. The body lives in the
// detail pane, so a long entry never pushes the rest of the list off screen.
export function StatusSection({ section, selectedId, onSelect }) {
  return (
    <section className="status-section" data-status={section.id}>
      <h2>
        <span aria-hidden="true">{section.emoji}</span> {section.label}
      </h2>
      <ul className="project-list">
        {section.projects.map((project) => (
          <li key={project.id}>
            <button
              type="button"
              className="project-link"
              aria-current={project.id === selectedId ? 'true' : undefined}
              onClick={() => onSelect(project.id)}
            >
              <span className="project-link-title">{project.title}</span>
              {project.parts?.length > 0 && (
                <span className="parts-badge">{project.parts.length} parts</span>
              )}
            </button>
          </li>
        ))}
      </ul>
    </section>
  )
}
