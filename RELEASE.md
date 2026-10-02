# Shipping Vitals — checklist

> **Plan (3 Oct 2026): two editions.** Mac App Store (sandboxed) + the full version downloaded from vitalsformac.com (Developer ID, notarized, `scripts/release.sh`). The full version is unlocked by the key that comes with an App Store purchase; Lemon Squeezy (section 2) is optional.
> Follow **Two editions › App Store submission checklist** below. Menu-bar live readings are a Pro feature.

Things marked **you** need your accounts, money or identity; everything else is scripted.

## 1. Accounts (one-time)

- [ ] **you** — Apple Developer Program ($99/yr) on the team in Xcode (`X5H55SY52K`). A free "Personal Team"
      can't notarize. Check at developer.apple.com/account.
- [ ] **you** — Xcode › Settings › Accounts › Manage Certificates › **+ Developer ID Application**.
- [ ] **you** — Create an app-specific password at account.apple.com, then run once:
      ```
      xcrun notarytool store-credentials vitals-notary --apple-id <you> --team-id X5H55SY52K --password <app-specific-password>
      ```
- [ ] **you** — Lemon Squeezy store (merchant of record: handles VAT/GST, pays out to you). Confirm payouts work for your country.
      Create product **Vitals Pro**, price **$9.99** (single payment), enable **License keys**,
      activation limit **1** (one key, one Mac — same rule as App Store keys). Copy the checkout link.
- [ ] Put the checkout link (and optionally your store id) in `Vitals/Licensing/LicenseManager.swift` → `LicenseConfig`.

## 2. Website + downloads

- [ ] Create a GitHub repo, push this branch, enable **GitHub Pages** from `/site`.
      (Or any static host. A custom domain like `getvitals.app` helps trust and SEO.)
- [x] Site domain is vitalsformac.com (UpdateChecker, release.sh, LicenseConfig, site/src/config.js).
- [ ] Upload DMGs to **GitHub Releases**; host `latest.json` next to the site.

## 3. Each release

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in Xcode.
2. `scripts/release.sh` → signed, notarized, stapled `Vitals-x.y.z.dmg` + `latest.json`.
3. Test the DMG on a second Mac or a fresh user account (Gatekeeper should open it with no warnings).
4. Upload DMG + `latest.json`. Existing users see "Vitals x.y.z is available" in the popover.

## 4. Pre-launch QA (30 minutes)

- [ ] First launch shows Welcome; icon appears; popover opens; Settings open from the gear and by re-opening the app.
- [ ] `yes > /dev/null &` twice (then `killall yes`) → after ~3 min a "yes is working hard" alert appears (Balanced).
- [ ] Quit button on a real app (e.g. open Chess, then trigger) asks it to quit.
- [ ] Lock the screen for 15+ minutes on battery → unlock → "While you were away" card.
- [ ] `caffeinate -i` running while locked on battery for 15 min → "caffeinate is keeping your Mac awake".
- [ ] Trial countdown, license activation with a Lemon Squeezy test-mode key, deactivation.
- [ ] Light + dark menu bar; notch MacBook with many icons (macOS 27 overflow chevron keeps Vitals reachable).
- [ ] Free Up Space: open from the popover; allow the Downloads/Desktop/Documents prompts; every category
      finishes; select an item → Move to Trash → it appears in the Trash and can be put back.
- [ ] Duplicates: copy a 50 MB file to two folders → both show, newest marked KEEP, the other pre-selected.
- [ ] App icon shows in Finder, the Dock (while Settings is open) and the About tab.
- [ ] Menu Bar tab → Allow Accessibility → icons listed → switch one off → it disappears and shows under
      "Menu bar" in the popover → click it there and its menu opens → quit Vitals → every icon is back.
- [ ] Hover over the clock while icons are hidden → Notification Center still opens.
- [ ] Alerts arrive as macOS notifications (hover › Options shows Snooze / Always ignore); turn notifications off for Vitals in System Settings → the cards come back inside the popover.
- [ ] On Screen pin (Pro): pin from the popover's pin button → drag to each edge and corner (snaps; left/right edge = column); right-click menu; Settings › On Screen preview click-to-place; Lock in place lets clicks through; every theme; quit Vitals → pin goes away.
- [ ] Where your data went: popover section counts up; "See the full breakdown" window; 7/30 days locked on Free; VPN on → VPN row appears and totals don't double.
- [ ] Energy check: Vitals itself should sit well under 1% CPU in Activity Monitor when the popover is closed.

## 5. Distribution channels (in order)

1. **Direct** (your site + Lemon Squeezy) — full-featured build, you keep ~90%.
2. **Setapp** — apply at setapp.com/developers; they accept non-sandboxed apps and pay per active use.
3. **Mac App Store "Vitals Lite"** (optional) — sandboxed build: system-wide alerts, heat, memory, disk,
   away reports without per-app blame. Good for discovery; link to the full version from the website.

## Two editions (App Store + direct)

Same code, two builds:

| | Scheme | Archive config | Sandbox | Extra |
|---|---|---|---|---|
| **App Store** | `Vitals App Store` | `AppStore` | Yes (`Config/AppStore.entitlements`) | StoreKit purchase + $0 trial item |
| **Direct (full)** | `Vitals` | `Release` | No | Icon hiding, per-app energy, Quit, whole-Mac scan, Lemon Squeezy |

Code switch: `#if APPSTORE` / `Edition.isAppStore` (App/AppSettings.swift). The App Store build
contains no private-framework code.

### App Store submission checklist
1. App Store Connect › Vitals › **In-App Purchases** › create two **Non-Consumable** items:
   - `com.anuragsingh.vitals.pro` — "Vitals Pro", price **$9.99** (App Store Connect › Pricing: USD 9.99; let Apple set other countries).
   - `com.anuragsingh.vitals.trial` — reference name and display name **"7-day Trial"** (Apple requires
     the "XX-day Trial" naming), price **Free**. (Guideline 3.1.1: time-limited trials of non-subscription
     apps must use a $0 item, and the app must state the length, what locks afterwards and the price
     before the trial starts. Settings › Pro shows this under the trial button.)
   Add a review screenshot for each (Settings › Pro tab).
2. **App Privacy**: Purchases › Purchase History only (App Functionality, not linked, no tracking). Full copy-paste listing: `AppStore/listing.md`.
3. **Category**: Utilities. Age rating: 4+.
4. Screenshots (1280×800 or 2880×1800): popover, menu-bar readings with colors, Free Up Space,
   battery forecast, Settings › Menu Bar.
5. Privacy policy URL + support URL (the `site/` pages work).
6. Xcode: scheme **Vitals App Store**, destination **Any Mac**, Product › Archive ›
   Validate App, then Distribute App › App Store Connect › Upload.
7. In App Store Connect choose the build, attach both in-app purchases to the version, submit.
8. Review notes (paste as is):
   "Vitals is a menu-bar utility (no Dock icon). After the welcome window, click the pulse icon in the menu bar to open it.
   Permissions, each asked only after the user acts:
   • Network (outgoing connections): used only by the optional "Ping" reading, which times a TCP connection to captive.apple.com. Off unless the user adds Ping to the pin or menu bar. Hotspot detection uses NWPathMonitor (no traffic).
   • Notifications: requested when the user leaves 'Notify me about real problems' ticked on the welcome screen, or turns it on in Settings. Health alerts are delivered as local notifications (no push, no server). Notifications never advertise Pro (guideline 4.5.4): Pro teasers appear only inside the app's own menu.
   • Open at login: off by default; the user can turn it on in the welcome screen or Settings (SMAppService).
   • Files: Free Up Space explains what it does, then shows the standard folder picker so the user can choose their home folder
     (user-selected read-write + security-scoped bookmark). Files are only moved to the Trash when the user selects them and confirms.
   No data leaves the Mac. No account, no analytics.
   In-app purchases: '7-day Trial' ($0 non-consumable) starts a trial of all Pro features; 'Vitals Pro' ($9.99 non-consumable) unlocks them permanently.
   Both are in Settings › Pro, with Restore Purchase."

## Licenses across editions (App Store purchase → key for the direct build)

**Rule:** buy once in the Mac App Store → Pro on every Mac with that Apple Account (Apple handles it) **plus one
license key** that unlocks the direct-download build on **one Mac at a time**. Refunds revoke the key automatically.

How it works (code: `site/api/`, `Vitals/Licensing/LicenseManager.swift`):
1. App Store build › Settings › Pro › **Show My License Key** sends the StoreKit 2 transaction (`jwsRepresentation`,
   signed by Apple) to `POST /api/license/claim`. The server verifies the x5c chain up to Apple Root CA G3 (pinned by
   SHA-256), the ES256 signature, bundle id and product id, then stores `claim:<originalTransactionId> → key`
   (one key per purchase; asking again returns the same key).
2. Direct build › Settings › Pro › paste key → `POST /api/license/activate {key, machine}`. `machine` = SHA-256 of the
   Mac's hardware UUID + salt (the real id never leaves the Mac). Max 1 machine per key; a 2nd Mac gets a clear
   "remove it on the other Mac first" message. The server returns an Ed25519-signed token the app verifies offline.
3. Every 14 days the direct build calls `/api/license/validate`; only an explicit "invalid" removes Pro (offline is fine).
4. `/api/apple/notifications` (App Store Server Notifications V2) marks keys revoked on REFUND/REVOKE, and re-enables
   them on REFUND_REVERSED.

**Set-up (once, ~15 minutes) — you:**
1. Cloudflare (see `site/README.md`): `npx wrangler login`, `npx wrangler d1 create vitals-licenses` (paste the id into
   `site/wrangler.toml`), `npm run db:migrate`, `npx wrangler pages project create vitals`.
2. `node scripts/license-keys.js` → `npx wrangler pages secret put LICENSE_SIGNING_KEY --project-name vitals`; paste the
   printed public key into `LicenseConfig.licensePublicKey`. Never commit the private key.
3. Set `LicenseConfig.licenseServer` to `https://<your-domain>/api` and deploy `site/` (`npm run deploy`).
4. App Store Connect › App Information › **App Store Server Notifications** › Production and Sandbox URL:
   `https://<your-domain>/api/apple/notifications`, Version 2.
5. Test: sandbox-buy Pro in the App Store build → Show My License Key → paste into the direct build on another Mac.

**App Review notes for this:** the key is part of what the user bought in the App Store (allowed under 3.1.3(b),
multiplatform). The App Store build never links to or mentions buying anywhere else, and shows the key only after
purchase.

**App Privacy (App Store Connect):** declare **Purchases › Purchase History** — used for App Functionality, not linked
to identity, not used for tracking. Sent only when the user taps "Show My License Key".

## Pricing (single source of truth)

| | App Store | Direct (Lemon Squeezy) |
|---|---|---|
| Download | Free | Free |
| Trial | 7 days, starts with the $0 `com.anuragsingh.vitals.trial` item | 7 days, starts on first launch |
| Vitals Pro | **$9.99 once** — non-consumable `com.anuragsingh.vitals.pro` | **$9.99 once** — license key, 1 Mac |
| You receive (approx.) | ~$5.09 (Small Business Program, 15%) | ~$5.19 (5% + $0.50 fee) |

- Enrol in the App Store **Small Business Program** (App Store Connect › Agreements) for 15% instead of 30%.
- In the app: `LicenseConfig.displayPrice` = "$9.99" (fallback text); the App Store shows its localized price.
- After the trial the app keeps working with the free features; Pro features show a PRO badge and the upgrade button.
