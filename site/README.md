# Vitals website + license server (Cloudflare)

- **Site:** React 19 + Vite, prerendered to static HTML (`/`, `/support`, `/privacy` work without JavaScript).
- **License server:** Cloudflare Pages Functions in `functions/api/`, shared code in `server/license.js`,
  storage in **D1** (`migrations/`). The signing key is the secret `LICENSE_SIGNING_KEY`.
- **Fill in once:** `src/config.js` → `APP_STORE_URL`, `SUPPORT_EMAIL`.

```bash
npm install
npm run dev               # site only, http://localhost:5173
npm run db:migrate:local  # once, creates the local test database
npm run preview           # site + license API + local D1, http://localhost:8788
npm run deploy            # build and upload to Cloudflare Pages
```

## Cloudflare setup (vitalsformac.com)
Done: D1 database `vitals-licenses` with tables (id in `wrangler.toml`).

Everything else is one command, run on your Mac from the Vitals folder (safe to re-run):
```bash
bash site/scripts/cloudflare-setup.sh
```
It signs in (browser tab → Allow), creates the Pages project, puts a fresh license signing key into a
Cloudflare secret (the public half goes into `LicenseManager.swift`), deploys, attaches
vitalsformac.com + www, and checks the live API. Afterwards: commit the updated `LicenseManager.swift`.

Left for the dashboard: Email › Email Routing › forward support@vitalsformac.com to your inbox.
App Store Connect: Server Notifications V2 URL `https://vitalsformac.com/api/apple/notifications`,
Support URL `/support`, Privacy URL `/privacy`. Updates later: `npm run deploy`.

## API (all POST, JSON)
| Path | Body | Returns |
|---|---|---|
| `/api/license/claim` | `{ transaction }` (StoreKit 2 JWS) | `{ key }` — one key per purchase |
| `/api/license/activate` | `{ key, machine, name }` | `{ token }` — one Mac per key, 409 if in use |
| `/api/license/validate` | `{ key, machine }` | `{ valid, reason? }` |
| `/api/license/deactivate` | `{ key, machine }` | `{ ok }` |
| `/api/apple/notifications` | App Store Server Notification V2 | refunds revoke the key, reversals restore it |
