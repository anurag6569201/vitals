# Shipping Vitals — checklist

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
      Create product **Vitals Pro**, price **$5.99** (single payment), enable **License keys**,
      activation limit 3. Copy the checkout link.
- [ ] Put the checkout link (and optionally your store id) in `Vitals/Licensing/LicenseManager.swift` → `LicenseConfig`.

## 2. Website + downloads

- [ ] Create a GitHub repo, push this branch, enable **GitHub Pages** from `/site`.
      (Or any static host. A custom domain like `getvitals.app` helps trust and SEO.)
- [ ] Replace `REPLACE-WITH-YOUR-SITE` in `Vitals/Licensing/UpdateChecker.swift`, `scripts/release.sh`, and `site/`.
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
   - `com.anuragsingh.vitals.pro` — "Vitals Pro", price **$5.99** (App Store Connect › Pricing: USD 5.99; let Apple set other countries).
   - `com.anuragsingh.vitals.trial` — "14-Day Free Trial", price **Free**. (Guideline 3.1.1:
     time-limited trials of non-subscription apps must use a $0 item.)
   Add a review screenshot for each (Settings › Pro tab).
2. **App Privacy**: "Data Not Collected".
3. **Category**: Utilities. Age rating: 4+.
4. Screenshots (1280×800 or 2880×1800): popover, menu-bar readings with colors, Free Up Space,
   battery forecast, Settings › Menu Bar.
5. Privacy policy URL + support URL (the `site/` pages work).
6. Xcode: scheme **Vitals App Store**, destination **Any Mac**, Product › Archive ›
   Validate App, then Distribute App › App Store Connect › Upload.
7. In App Store Connect choose the build, attach both in-app purchases to the version, submit.
8. Review notes: "Menu-bar utility (LSUIElement). Click the icon in the menu bar to open it.
   Free Up Space asks the user to choose their home folder (security-scoped bookmark); files
   are only moved to the Trash on request."

## Pricing (single source of truth)

| | App Store | Direct (Lemon Squeezy) |
|---|---|---|
| Download | Free | Free |
| Trial | 14 days, starts with the $0 `com.anuragsingh.vitals.trial` item | 14 days, starts on first launch |
| Vitals Pro | **$5.99 once** — non-consumable `com.anuragsingh.vitals.pro` | **$5.99 once** — license key, 3 Macs |
| You receive (approx.) | ~$5.09 (Small Business Program, 15%) | ~$5.19 (5% + $0.50 fee) |

- Enrol in the App Store **Small Business Program** (App Store Connect › Agreements) for 15% instead of 30%.
- In the app: `LicenseConfig.displayPrice` = "$5.99" (fallback text); the App Store shows its localized price.
- After the trial the app keeps working with the free features; Pro features show a PRO badge and the upgrade button.
