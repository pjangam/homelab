import { vi } from 'vitest'

// Stubs fetch with a tracker/ directory: the JSON listing nginx serves for
// the directory URL, and each file's text for its own URL.
export function mockTracker(files) {
  const fetch = vi.fn((url) => {
    const name = url.split('/').pop()
    if (name === '') {
      const listing = Object.keys(files).map((n) => ({ name: n, type: 'file' }))
      return Promise.resolve({ ok: true, json: () => Promise.resolve(listing) })
    }
    if (!(name in files)) return Promise.resolve({ ok: false, status: 404, text: () => Promise.resolve('') })
    return Promise.resolve({ ok: true, text: () => Promise.resolve(files[name]) })
  })
  vi.stubGlobal('fetch', fetch)
  return fetch
}
