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
      Create product **Vitals Pro**, price $12.99 (launch: $9.99 with a discount code), enable **License keys**,
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
- [ ] Energy check: Vitals itself should sit well under 1% CPU in Activity Monitor when the popover is closed.

## 5. Distribution channels (in order)

1. **Direct** (your site + Lemon Squeezy) — full-featured build, you keep ~90%.
2. **Setapp** — apply at setapp.com/developers; they accept non-sandboxed apps and pay per active use.
3. **Mac App Store "Vitals Lite"** (optional) — sandboxed build: system-wide alerts, heat, memory, disk,
   away reports without per-app blame. Good for discovery; link to the full version from the website.
