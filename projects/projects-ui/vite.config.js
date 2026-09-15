/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  // Served both directly on :8125 and reverse-proxied under /projects via
  // Caddy (see ../Caddyfile) - base must match the proxied path so built
  // asset URLs (and useProjects.js's default fetch of PROJECTS.md) resolve
  // correctly through the proxy, not just when hit directly on :8125.
  base: '/projects/',
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: './src/setupTests.js',
    globals: true,
  },
})
