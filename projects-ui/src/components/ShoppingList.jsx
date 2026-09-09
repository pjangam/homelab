import { formatRange } from '../lib/parts'

// The merged list for a shop trip. Rendered as a panel rather than a route so
// it can sit alongside the projects it came from - the phone is in one hand
// and the parts bin in the other.
export function ShoppingList({ projects, merged, checked, onToggleItem, onClear }) {
  const shared = merged.rows.filter((row) => row.sharedBy.length > 1)

  return (
    <aside className="shopping-list" aria-label="Shopping list">
      <header className="shopping-list-header">
        <h2>Shopping list</h2>
        <button type="button" onClick={onClear}>Clear</button>
      </header>

      <p className="shopping-list-projects">
        {projects.map((p) => p.title).join(' · ')}
      </p>

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
        Estimated total: <strong>{formatRange(merged.total.low, merged.total.high)}</strong>
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
    </aside>
  )
}
