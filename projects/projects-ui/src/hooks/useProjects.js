import { useEffect, useState } from 'react'
import { parseProjects } from '../lib/parseProjects'
import { combineTrackerFiles, trackerFileNames } from '../lib/trackerFiles'

async function fetchOk(url, as) {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`Failed to load ${url}: ${response.status}`)
  return as === 'json' ? response.json() : response.text()
}

// One request for nginx's JSON listing of tracker/, then every project file
// in parallel (~115 small files, the same ~640 KB the single file was). Read
// live through the repo bind mount, so an edit shows on the next refresh.
export function useProjects(dir = `${import.meta.env.BASE_URL}tracker/`) {
  const [state, setState] = useState({ status: 'loading', sections: [], error: null })

  useEffect(() => {
    let cancelled = false

    fetchOk(dir, 'json')
      .then((listing) => Promise.all(trackerFileNames(listing).map((name) => fetchOk(dir + name))))
      .then((texts) => {
        if (cancelled) return
        setState({ status: 'ready', sections: parseProjects(combineTrackerFiles(texts)), error: null })
      })
      .catch((error) => {
        if (cancelled) return
        setState({ status: 'error', sections: [], error })
      })

    return () => {
      cancelled = true
    }
  }, [dir])

  return state
}
