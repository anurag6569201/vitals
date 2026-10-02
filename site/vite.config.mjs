import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';

// Three real pages (/, /support, /privacy), each prerendered to static HTML by
// scripts/prerender.mjs, then hydrated by React. App Review and search engines get
// full HTML without running JavaScript.
export default defineConfig(({ isSsrBuild }) => ({
  plugins: [react()],
  build: isSsrBuild
    ? { rollupOptions: { output: { entryFileNames: '[name].mjs' } } }
    : {
        outDir: 'dist',
        rollupOptions: {
          input: {
            index: resolve(import.meta.dirname, 'index.html'),
            support: resolve(import.meta.dirname, 'support.html'),
            privacy: resolve(import.meta.dirname, 'privacy.html'),
          },
        },
      },
}));
