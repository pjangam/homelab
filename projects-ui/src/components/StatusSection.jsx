import { ProjectCard } from './ProjectCard'

export function StatusSection({ section, openIds, onToggleProject }) {
  return (
    <section className="status-section" data-status={section.id}>
      <h2>
        <span aria-hidden="true">{section.emoji}</span> {section.label}
      </h2>
      <div className="project-list">
        {section.projects.map((project) => (
          <ProjectCard
            key={project.id}
            project={project}
            isOpen={openIds.has(project.id)}
            onToggle={onToggleProject}
          />
        ))}
      </div>
    </section>
  )
}
