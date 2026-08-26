// bodyHtml comes from parseProjects(), which only ever runs on this repo's
// own PROJECTS.md - trusted content, not user input, so rendering it
// directly is fine.
export function ProjectCard({ project, isOpen, onToggle }) {
  return (
    <details
      className="project-card"
      open={isOpen}
      onToggle={(e) => onToggle(project.id, e.target.open)}
    >
      <summary>{project.title}</summary>
      <div
        className="project-body"
        dangerouslySetInnerHTML={{ __html: project.bodyHtml }}
      />
    </details>
  )
}
