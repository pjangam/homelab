import { formatRange, parseCost } from '../lib/parts'

// bodyHtml comes from parseProjects(), which only ever runs on this repo's
// own PROJECTS.md - trusted content, not user input, so rendering it
// directly is fine.
export function ProjectCard({ project, isOpen, onToggle, inList, onToggleInList }) {
  const hasParts = project.parts?.length > 0

  return (
    <details
      className="project-card"
      open={isOpen}
      onToggle={(e) => onToggle(project.id, e.target.open)}
    >
      <summary>
        {project.title}
        {hasParts && <span className="parts-badge">{project.parts.length} parts</span>}
      </summary>
      <div
        className="project-body"
        dangerouslySetInnerHTML={{ __html: project.bodyHtml }}
      />

      {hasParts && (
        <div className="parts">
          <div className="parts-header">
            <h4>Parts</h4>
            <label className="parts-add">
              <input
                type="checkbox"
                checked={inList}
                onChange={() => onToggleInList(project.id)}
              />
              Add to shopping list
            </label>
          </div>
          <table>
            <tbody>
              {project.parts.map((row) => {
                const cost = parseCost(row.est)
                return (
                  <tr key={row.item}>
                    <td className="qty">{row.qty}</td>
                    <td>
                      {row.item}
                      {row.note && <p className="note">{row.note}</p>}
                    </td>
                    <td className="cost">{cost ? formatRange(cost.low, cost.high) : '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </details>
  )
}
