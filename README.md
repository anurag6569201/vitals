# Vitals

**The check-engine light for your Mac.**

Vitals lives in your menu bar as one small pulse icon and stays quiet while everything is fine.
When something actually needs you, it says what's wrong in plain English and offers a one-click fix:

- **Runaway apps** — "Google Chrome has used 180% CPU for 12 minutes across 14 processes." → *Quit Chrome*
- **Heat** — macOS is throttling; here's the app causing it.
- **Memory pressure** — your Mac is swapping; here's who's using the memory.
- **Fast battery drain** *(Pro)* — "You're losing 28% an hour; biggest drain: Zoom."
- **Apps keeping your Mac awake** *(Pro)* — "Teams kept your Mac awake for 3h while you were away."
- **Low disk space** and a gentle **restart reminder**.
- **While you were away** *(Pro)* — after you unlock: "Away 7h 12m · lost 23% — more than it should. Your Mac never slept: Zoom kept it awake."

- **Will my battery last?** *(Pro)* — when you'll run out, and the smallest set of apps to quit to make it to the time you need.
- **Leaving Check** *(Pro)* — right after you unplug, warns if an app would keep your Mac awake and hot in your bag.
- **Free Up Space** — finds what's eating your disk, for everyone, not just developers: large files (with last-opened dates), old downloads, installers and already-unzipped archives, old screenshots and recordings, true duplicates (verified by full hash), apps you haven't opened in 3 months, app caches and leftovers of deleted apps, developer junk, old iPhone updates, and the Trash. Everything goes to the Trash, never straight to deletion. Reviewing is free; one-click clearing is Pro.

Plus a compact live dashboard (CPU, memory, battery draw, disk, network, uptime) and the apps using your Mac right now.

## How it works

| Layer | Files | Notes |
|---|---|---|
| Core (pure Swift) | `Vitals/Core/` | Models, detectors, `HealthEngine` (hysteresis, snooze, ignore, Pro gating, learns your normal drain), `AwayTracker`, plain-English `Knowledge` about macOS processes. No AppKit. |
| Platform | `Vitals/Platform/` | `ProcessSampler` (libproc: per-app CPU, energy, memory, helpers rolled up into their app), `SystemSampler` (CPU, memory pressure, swap, thermal state, battery + watts, disk, network, power assertions), actions, presence (lock/sleep). |
| App | `Vitals/App/` | `VitalsModel` (5 s sampling, 2 s while open, 10 s while away), status item, windows, settings persistence. |
| UI | `Vitals/UI/` | SwiftUI popover, settings, onboarding. |
| Licensing | `Vitals/Licensing/` | 14-day trial, Lemon Squeezy license keys (direct build) or StoreKit 2 (App Store build), update check. |

## Builds

- **Direct (default)** — unsandboxed, Developer ID signed + notarized. Full features. `scripts/release.sh`.
- **Mac App Store (optional, later)** — turn on App Sandbox (`ENABLE_APP_SANDBOX = YES`) and add the
  `com.anuragsingh.vitals.pro` in-app purchase. Vitals detects the sandbox at runtime: per-app details and
  one-click Quit are unavailable there (Apple blocks them), everything system-wide keeps working.

Requires macOS 14+. No dependencies. Open `Vitals.xcodeproj` and run.

## Privacy

Everything stays on the Mac. No analytics. The only network calls are license activation and the daily update check.

## Labs

`Labs/` keeps the earlier experimental menu-bar icon-hiding bridge (private `MenuBarClientCore` API, macOS 27),
adapted from MenuBarHider (MIT). It is **not** compiled into Vitals.

See `RELEASE.md` to ship and `MARKETING.md` for positioning and launch copy.
