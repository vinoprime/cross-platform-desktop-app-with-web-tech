import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  base: './',
  server: {
    port: 5173,
  },
  build: {
    outDir: 'dist/MyAppName',
    emptyOutDir: true,
  },
})
