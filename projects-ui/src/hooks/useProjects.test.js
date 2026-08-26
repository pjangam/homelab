import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { useProjects } from './useProjects'

const MARKDOWN = `## 🟢 Active\n\n### A project\nSome text.\n`

describe('useProjects', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn())
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('starts in a loading state', () => {
    fetch.mockReturnValue(new Promise(() => {})) // never resolves
    const { result } = renderHook(() => useProjects())
    expect(result.current.status).toBe('loading')
  })

  it('parses the fetched markdown into sections on success', async () => {
    fetch.mockResolvedValue({ ok: true, text: () => Promise.resolve(MARKDOWN) })
    const { result } = renderHook(() => useProjects())

    await waitFor(() => expect(result.current.status).toBe('ready'))
    expect(result.current.sections).toHaveLength(1)
    expect(result.current.sections[0].projects[0].title).toBe('A project')
  })

  it('surfaces an error when the response is not ok', async () => {
    fetch.mockResolvedValue({ ok: false, status: 404, text: () => Promise.resolve('') })
    const { result } = renderHook(() => useProjects())

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error).toBeInstanceOf(Error)
  })

  it('surfaces an error when fetch itself rejects', async () => {
    fetch.mockRejectedValue(new Error('network down'))
    const { result } = renderHook(() => useProjects())

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error.message).toBe('network down')
  })

  it('fetches the given url', () => {
    fetch.mockReturnValue(new Promise(() => {}))
    renderHook(() => useProjects('/custom.md'))
    expect(fetch).toHaveBeenCalledWith('/custom.md')
  })
})
