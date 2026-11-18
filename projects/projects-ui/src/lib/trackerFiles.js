// Projects live one per file in tracker/<slug>.md (since 2026-11-18), each
// starting "# Title" followed by its Status/Priority/Cost/Effort lines. The
// parser was written for the old single PROJECTS.md, so the files are joined
// back into that shape - "## Projects" and one "### Title" entry per file -
// and parseProjects() reads it unchanged. Project ids stay slugs of the title,
// so shopping-list picks saved in the browser survive the move.

// nginx's `autoindex_format json` listing: [{ name, type, ... }, ...]
export function trackerFileNames(listing) {
  return listing
    .filter((entry) => entry.type === 'file' && entry.name.endsWith('.md') && entry.name !== 'README.md')
    .map((entry) => entry.name)
    .sort()
}

export function combineTrackerFiles(texts) {
  const entries = texts.map((text) => (text.startsWith('# ') ? `##${text}` : text).replace(/\n+$/, '\n'))
  return ['## Projects', '', ...entries].join('\n')
}
