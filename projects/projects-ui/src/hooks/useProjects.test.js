import { describe, it, expect, vi, afterEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { useProjects } from './useProjects'
import { mockTracker } from '../test/mockTracker'

describe('useProjects', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('starts in a loading state', () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(new Promise(() => {}))) // never resolves
    const { result } = renderHook(() => useProjects())
    expect(result.current.status).toBe('loading')
  })

  it('lists tracker/, fetches every project file and parses them', async () => {
    const fetch = mockTracker({
      'a.md': '# A project\n**Status:** Active\n\nSome text.\n',
      'b.md': '# B project\n**Status:** Backlog\n\nMore.\n',
      'README.md': '# Tracker\nNot a project.\n',
    })
    const { result } = renderHook(() => useProjects('/projects/tracker/'))

    await waitFor(() => expect(result.current.status).toBe('ready'))
    expect(fetch).toHaveBeenCalledWith('/projects/tracker/')
    expect(fetch).toHaveBeenCalledWith('/projects/tracker/a.md')
    expect(fetch).not.toHaveBeenCalledWith('/projects/tracker/README.md')
    const titles = result.current.sections.flatMap((s) => s.projects.map((p) => p.title))
    expect(titles).toEqual(['A project', 'B project'])
  })

  it('surfaces an error when the listing is not ok', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 404 }))
    const { result } = renderHook(() => useProjects())

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error).toBeInstanceOf(Error)
  })

  it('surfaces an error when one project file fails', async () => {
    const fetch = mockTracker({ 'a.md': '# A\n' })
    fetch.mockImplementationOnce(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve([{ name: 'gone.md', type: 'file' }]) }),
    )
    const { result } = renderHook(() => useProjects('/t/'))

    await waitFor(() => expect(result.current.status).toBe('error'))
  })

  it('surfaces an error when fetch itself rejects', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('network down')))
    const { result } = renderHook(() => useProjects())

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error.message).toBe('network down')
  })
})
