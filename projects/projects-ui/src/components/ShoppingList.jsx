import { formatRange } from '../lib/parts'

// The merged list for a shop trip. Rendered as a panel rather than a route so
// it can sit alongside the projects it came from - the phone is in one hand
// and the parts bin in the other. Collapsible, because above two panes that
// fill the window an open list would squeeze the projects out of view at the
// desk; the summary line still shows the count and total while it is shut.
export function ShoppingList({ projects, merged, checked, onToggleItem, onClear, open, onToggleOpen }) {
  const shared = merged.rows.filter((row) => row.sharedBy.length > 1)
  const total = formatRange(merged.total.low, merged.total.high)

  return (
    <aside className="shopping-list" aria-label="Shopping list">
      <details open={open} onToggle={(e) => onToggleOpen(e.currentTarget.open)}>
        <summary>
          <h2><span aria-hidden="true">🛒</span> Shopping list</h2>
          <span className="shopping-list-summary">
            {merged.rows.length} items · {total}
          </span>
        </summary>

        <div className="shopping-list-body">
          <div className="shopping-list-header">
            <p className="shopping-list-projects">
              {projects.map((p) => p.title).join(' · ')}
            </p>
            <button type="button" onClick={onClear}>Clear</button>
          </div>

          <ul>
            {merged.rows.map((row) => (
              <li key={row.item} className={checked.has(row.item) ? 'got-it' : undefined}>
                <label>
                  <input
                    type="checkbox"
                    checked={checked.has(row.item)}
                    onChange={() => onToggleItem(row.item)}
                  />
                  <span className="qty">{row.qty}</span>
                  <span className="item">{row.item}</span>
                  <span className="cost">{row.cost ? formatRange(row.cost.low, row.cost.high) : '?'}</span>
                  {row.sharedBy.length > 1 && <span className="shared" title={row.sharedBy.join(', ')}>shared</span>}
                </label>
                {row.note && <p className="note">{row.note}</p>}
              </li>
            ))}
          </ul>

          <p className="shopping-list-total">
            Estimated total: <strong>{total}</strong>
          </p>
          {merged.withoutEstimate > 0 && (
            <p className="shopping-list-caveat">
              {merged.withoutEstimate} item(s) have no estimate — this is a floor, not a budget.
            </p>
          )}
          {shared.length > 0 && (
            <p className="shopping-list-caveat">
              Quantities are summed across projects. Check the “shared” items first — one pack may cover both.
            </p>
          )}
        </div>
      </details>
    </aside>
  )
}
