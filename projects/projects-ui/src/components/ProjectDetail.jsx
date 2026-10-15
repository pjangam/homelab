import { formatRange, listKey, parseCost, partGroups } from '../lib/parts'

// bodyHtml comes from parseProjects(), which only ever runs on this repo's
// own PROJECTS.md - trusted content, not user input, so rendering it
// directly is fine.
function PartRow({ row }) {
  const cost = parseCost(row.est)
  return (
    <tr>
      <td className="qty">{row.qty}</td>
      <td>
        {row.item}
        {row.note && <p className="note">{row.note}</p>}
      </td>
      <td className="cost">{cost ? formatRange(cost.low, cost.high) : '—'}</td>
    </tr>
  )
}

export function ProjectDetail({ project, section, listIds = new Set(), onToggleInList }) {
  const hasParts = project.parts?.length > 0
  const groups = partGroups(project.parts)
  const wholeInList = listIds.has(project.id)
  // A list with options gets a checkbox per option instead of one for the
  // lot. The whole-project box stays only to untick a pick made before the
  // project had options.
  const showWholeBox = groups.length === 0 || wholeInList

  return (
    <article className="project-detail" data-status={section.id}>
      <p className="detail-status">
        <span aria-hidden="true">{section.emoji}</span> {section.label}
        {project.priority && (
          <span className="priority-badge" data-priority={project.priority}>
            {project.priority}
          </span>
        )}
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
            {showWholeBox && (
              <label className="parts-add">
                <input
                  type="checkbox"
                  checked={wholeInList}
                  onChange={() => onToggleInList(project.id)}
                />
                Add to shopping list
              </label>
            )}
          </div>
          <table>
            <tbody>
              {project.parts.filter((row) => !row.group).map((row) => (
                <PartRow key={row.item} row={row} />
              ))}
            </tbody>
            {groups.map((group) => (
              <tbody key={group}>
                <tr className="parts-group">
                  <th colSpan={3}>
                    <label className="parts-add">
                      <input
                        type="checkbox"
                        aria-label={`Add ${group} to shopping list`}
                        checked={listIds.has(listKey(project.id, group))}
                        onChange={() => onToggleInList(listKey(project.id, group))}
                      />
                      {group}
                    </label>
                  </th>
                </tr>
                {project.parts.filter((row) => row.group === group).map((row) => (
                  <PartRow key={row.item} row={row} />
                ))}
              </tbody>
            ))}
          </table>
        </div>
      )}
    </article>
  )
}
