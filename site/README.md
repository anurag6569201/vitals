# Vitals website

React 19 + Vite, prerendered to static HTML (so `/`, `/support` and `/privacy` work without JavaScript),
plus the license server in `api/` (Vercel serverless functions, unchanged).

```bash
npm install
npm run dev      # http://localhost:5173 (api/ isn't served here — use `vercel dev` for that)
npm run build    # → dist/
```

**Fill in once:** `src/config.js` → `APP_STORE_URL` and `SUPPORT_EMAIL`.

## Layout
- `index.html`, `support.html`, `privacy.html` — page shells (title, meta); React renders into `#root`.
- `src/pages/` — the three pages. `src/sections/` — home page sections.
- `src/data.js` — readings, pin shapes, themes and presets (mirrors `Vitals/App/PinSettings.swift`).
- `scripts/prerender.mjs` — renders each page to HTML after the build.
- `public/` — icons, copied as-is.

## Deploy (Vercel)
Root directory: `site`. `vercel.json` sets the Vite build and output; `/api/*` keeps working as before.
