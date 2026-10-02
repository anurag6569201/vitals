# Vitals — App Store Connect listing (copy and paste)

## New App (My Apps › + › New App)
| Field | Value |
|---|---|
| Platform | macOS |
| Name (≤30) | **Vitals: Mac Health Monitor** — fallbacks if taken: `Vitals – Health for Mac`, `Vitals for Mac` |
| Primary language | English (U.S.) |
| Bundle ID | com.anuragsingh.vitals |
| SKU | VITALS-MAC-001 |
| User access | Full Access |

## App Information
| Field | Value |
|---|---|
| Subtitle (≤30) | The check-engine light for Mac |
| Category | Utilities · secondary: Productivity |
| Content rights | Does not contain third-party content |
| Age rating | 4+ (answer "None" / "No" to everything) |
| App Store Server Notifications | Production **and** Sandbox URL: `https://vitalsformac.com/api/apple/notifications` · Version 2 |

## Pricing and Availability
Price: **Free** (USD 0). Availability: all countries.

## In-App Purchases (Monetization › In-App Purchases › +) — both **Non-Consumable**
| | Vitals Pro | 7-day Trial |
|---|---|---|
| Reference name | Vitals Pro | 7-day Trial |
| Product ID | com.anuragsingh.vitals.pro | com.anuragsingh.vitals.trial |
| Price | USD 9.99 | Free (USD 0) |
| Family Sharing | Off | Off |
| Display name (≤30) | Vitals Pro | 7-day Trial |
| Description (≤45) | Every Pro feature, once. No subscription. | Try every Pro feature free for 7 days. |
| Review screenshot | Settings › Pro tab (same image for both) | |
| Review notes | Unlocks all Pro features permanently. Bought once. | Starts a 7-day trial of all Pro features. Price $0. When it ends, Pro features lock and the free features keep working. The length, what locks, and the Pro price are shown before the trial starts (Settings › Pro). |

## App Privacy (App Privacy › Get Started)
- "Do you or your third-party partners collect data from this app?" → **Yes**
- Data type: **Purchases › Purchase History** only
  - Used for: **App Functionality**
  - Linked to the user's identity: **No**
  - Used for tracking: **No**
- Privacy Policy URL: `https://vitalsformac.com/privacy`
(Why: "Show My License Key" sends Apple's signed purchase record to our license server to issue the key.)

## Version 1.0 — Mac App page
**Promotional text (≤170)**
Your Mac, without the guesswork. Vitals stays quiet in the menu bar and tells you in plain English when something's wrong — and what to do about it.

**Description**
Vitals is the check-engine light for your Mac.

It sits quietly in your menu bar and stays silent while everything is fine. When your Mac runs hot, runs out of memory, runs low on disk space, or drains its battery faster than usual, Vitals sends a normal Mac notification that says what's happening, why it matters and what to do — then gets out of the way.

ALERTS THAT DON'T NAG
• Heat, memory pressure, low disk space and restart reminders
• Waits until a problem has lasted long enough to matter — pick Relaxed, Balanced or Sensitive
• Snooze or "Always ignore" right from the notification
• No notification ever tries to sell you anything

FREE UP SPACE
• See exactly what's filling your disk: old downloads, installers, large files, duplicates, app caches, developer build folders, old screenshots and iPhone updates
• Space Map: a picture of your home folder — click any block to look inside
• Remove apps together with the settings and caches they leave behind
• Everything is explained, your own files are never pre-selected, and things only ever go to the Trash

BATTERY
• "Lasts until…" forecast in plain English
• "Will my battery last until 6 PM?" planner, with Low Power Mode advice
• Battery health and charge cycles, with a daily history so you can see how it ages
• "While you were away": how long your Mac really slept and whether the drop was normal

ON-SCREEN PIN AND MENU-BAR READINGS
• Pin live readings anywhere on screen — six shapes, nine readable themes, one-click presets
• Sixteen readings: CPU, GPU, memory, swap, battery, power draw, battery health, disk free, disk activity, network speed, data today, Wi-Fi signal, ping, refresh rate, uptime and world clock

WHERE YOUR DATA WENT
• Hour-by-hour data use for up to 31 days, by connection
• Hotspot data guard warns you before you blow through your iPhone's hotspot allowance

ALSO
• Shortcuts actions: How Is My Mac Doing, How Much Data Did I Use Today, Keep My Mac Awake, Show or Hide the Pin
• Keep Awake and a global keyboard shortcut

PRIVATE BY DESIGN
No account, no analytics, no tracking. Everything Vitals reads stays on your Mac.

FREE, WITH VITALS PRO
Alerts, Free Up Space scanning, the Space Map, battery forecast and health, hotspot guard and today's data use are free. Vitals Pro is $9.99 once — no subscription — and adds live menu-bar readings, every pin style, the battery planner and fast-drain alerts, one-click clearing and complete app removal, 7- and 30-day data history and full "While you were away" reports. Try every Pro feature free for 7 days.

**Keywords (≤100, no spaces after commas)**
system monitor,battery health,cpu,temperature,disk cleaner,storage,memory,menubar,uninstaller,wifi

**Support URL** `https://vitalsformac.com/support`
**Marketing URL** `https://vitalsformac.com`
**Copyright** 2026 Anurag Singh

**Screenshots** (2880×1800 or 1440×900; 1–10): popover with an alert · Free Up Space + Space Map · battery window · on-screen pin · data usage window · Settings › Pro

## App Review Information
Sign-in required: **No**. Contact: your name, phone, support@vitalsformac.com.

**Notes (paste as is)**
Vitals is a menu-bar utility (no Dock icon). After the welcome window, click the pulse icon in the menu bar to open it.

Permissions, each asked only after the user acts:
• Notifications: requested from the welcome screen or Settings. Health alerts are local notifications (no push). Notifications never advertise Pro (guideline 4.5.4); Pro teasers appear only inside the app's own menu.
• Files: Free Up Space explains what it does, then shows the standard folder picker so the user can choose their home folder (user-selected read-write + security-scoped bookmark). To move apps to the Trash, the user is asked once to choose the Applications folder the same way. Files are only moved to the Trash after the user selects them and confirms.
• Open at login: off by default (SMAppService).
• Network (outgoing): used only by (1) the optional "Ping" reading, which times a connection to captive.apple.com, and (2) "Show My License Key" in Settings › Pro, see below.

In-app purchases (Settings › Pro, with Restore Purchase): "7-day Trial" ($0 non-consumable) starts a trial of all Pro features; "Vitals Pro" ($9.99 non-consumable) unlocks them permanently.

License key (guideline 3.1.3(b), multiplatform): after buying Vitals Pro in the App Store, the user can choose "Show My License Key". The app sends the StoreKit 2 signed transaction to our server (vitalsformac.com), which verifies Apple's signature and returns one key that unlocks the same purchase in Vitals' direct-download edition. The App Store build never links to or mentions buying outside the App Store, and the key is shown only after an App Store purchase.

No account, no analytics, no tracking.
