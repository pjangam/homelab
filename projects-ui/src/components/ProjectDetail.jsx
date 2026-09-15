import { formatRange, parseCost } from '../lib/parts'

// bodyHtml comes from parseProjects(), which only ever runs on this repo's
// own PROJECTS.md - trusted content, not user input, so rendering it
// directly is fine.
export function ProjectDetail({ project, section, inList, onToggleInList }) {
  const hasParts = project.parts?.length > 0

  return (
    <article className="project-detail" data-status={section.id}>
      <p className="detail-status">
        <span aria-hidden="true">{section.emoji}</span> {section.label}
      </p>
      <h2>{project.title}</h2>
      <div
        className="project-body"
        dangerouslySetInnerHTML={{ __html: project.bodyHtml }}
      />

      {hasParts && (
        <div className="parts">
          <div className="parts-header">
            <h3>Parts</h3>
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
    </article>
  )
}
