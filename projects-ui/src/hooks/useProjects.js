import { useEffect, useState } from 'react'
import { parseProjects } from '../lib/parseProjects'

export function useProjects(url = '/PROJECTS.md') {
  const [state, setState] = useState({ status: 'loading', sections: [], error: null })

  useEffect(() => {
    let cancelled = false

    fetch(url)
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Failed to load ${url}: ${response.status}`)
        }
        return response.text()
      })
      .then((text) => {
        if (cancelled) return
        setState({ status: 'ready', sections: parseProjects(text), error: null })
      })
      .catch((error) => {
        if (cancelled) return
        setState({ status: 'error', sections: [], error })
      })

    return () => {
      cancelled = true
    }
  }, [url])

  return state
}
