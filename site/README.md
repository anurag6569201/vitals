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
Done: D1 database `vitals-licenses` created with tables (id in `wrangler.toml`).

Remaining, in the Cloudflare dashboard (no command line needed):
1. Workers & Pages › Create › Pages › **Connect to Git** › repo `vitals` · Root directory `site` ·
   Build command `npm run build` · Output `dist`. Pushes to `main` deploy automatically; the D1
   binding comes from `wrangler.toml`.
2. Run `node ../scripts/license-keys.js`. Project › Settings › Variables and Secrets › add **Secret**
   `LICENSE_SIGNING_KEY` (Production and Preview) = the private key. Paste the public key into
   `Vitals/Licensing/LicenseManager.swift` › `licensePublicKey`. Retry the latest deployment.
3. Project › Custom domains › add `vitalsformac.com` (and `www.vitalsformac.com`).
4. Email › Email Routing › route `support@vitalsformac.com` to your inbox.
5. App Store Connect › App Information › App Store Server Notifications (V2, Production and Sandbox):
   `https://vitalsformac.com/api/apple/notifications`. Support URL `https://vitalsformac.com/support`,
   Privacy Policy URL `https://vitalsformac.com/privacy`.

Command-line alternative: `npx wrangler login`, `npx wrangler pages secret put LICENSE_SIGNING_KEY --project-name vitals`, `npm run deploy`.

## API (all POST, JSON)
| Path | Body | Returns |
|---|---|---|
| `/api/license/claim` | `{ transaction }` (StoreKit 2 JWS) | `{ key }` — one key per purchase |
| `/api/license/activate` | `{ key, machine, name }` | `{ token }` — one Mac per key, 409 if in use |
| `/api/license/validate` | `{ key, machine }` | `{ valid, reason? }` |
| `/api/license/deactivate` | `{ key, machine }` | `{ ok }` |
| `/api/apple/notifications` | App Store Server Notification V2 | refunds revoke the key, reversals restore it |
