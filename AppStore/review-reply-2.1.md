Hello App Review team,

Thank you for reviewing Vitals. Here is the information you asked for. The screen recording is attached; it was captured on a MacBook Air running the latest macOS.

1. Screen recording
Attached. It starts by launching Vitals, then shows the menu-bar popover with disk, CPU, memory and network readings, a low-disk-space alert, Free Up Space and Space Map, the Battery window, the On Screen pin, and finally Settings > Pro: starting the 7-day trial and buying Vitals Pro (sandbox account), plus Restore Purchase.

2. Purpose and audience
I built Vitals because of my own Mac. It has a small drive, and when I run development servers they quietly fill the disk. I only found out when the Mac froze or slowed to a crawl, with no warning. Then I had to dig through System Settings > Storage to guess what was taking space and how much I needed to free. The same with the CPU stuck at 100% or the Wi-Fi: I often couldn't tell whether something was eating the CPU or whether the network was even working.

macOS doesn't warn you before these problems hit, so Vitals acts as a "check-engine light" in the menu bar:
- Disk: warns when free space is running low, before the Mac stalls, and Free Up Space / Space Map show exactly what is using the space and how much can be safely cleared (files only ever go to the Trash).
- CPU, memory and heat: tells you when the Mac is under sustained load or memory pressure, in plain English, with what to do next.
- Network: shows at a glance whether the connection is working, plus live download/upload speed and Wi-Fi signal, so you're not left wondering if the Wi-Fi is down.
- Battery: health, cycles and how long the charge will last.
It stays quiet when everything is fine and only notifies when something actually needs attention.

Audience: everyday Mac users, students and developers, especially on smaller-storage MacBooks, who want to catch storage, CPU and network problems early without opening Activity Monitor or System Settings.

3. Setup and main features
No account or login is needed. Launch the app and it appears in the menu bar as a pulse icon; click it to open the popover with the readings.
- Free Up Space and Space Map: popover > "Free up space". The first scan asks the user to choose the folder to scan (standard macOS open panel, App Sandbox).
- Battery window: popover > "Battery health".
- On Screen pin: Settings > On Screen.
- Alerts: Settings > Alerts.
No sample files or credentials are required.

4. External services
- Apple StoreKit / In-App Purchase for payments.
- Optional "Ping" reading (off by default) that times a request to Apple's captive.apple.com.
- Our own server, vitalsformac.com (hosted on Cloudflare), is contacted only if a Pro buyer taps "Show My License Key" in Settings > Pro. The app sends the signed App Store transaction so the server can return a license key for the buyer's own use of Vitals on another Mac. Nothing else is sent.
Vitals has no accounts, analytics, ads, tracking or AI services.

5. Regional differences
None. Vitals works the same in every region. The interface is in English.

6. Regulated industry / third-party material
Not applicable. Vitals is not in a regulated industry and contains no third-party protected material.

7. In-App Purchase
Two non-consumable items, both in Settings > Pro (also reachable from "Try Pro free" at the bottom of the popover):
- "7-day Trial" ($0): unlocks every Pro feature for 7 days. When it ends, the Pro features lock again and the free features keep working. Nothing is charged automatically.
- "Vitals Pro" ($9.99, one-time): unlocks Pro permanently: live readings in the menu bar, fast-drain battery alerts and the battery planner, 7- and 30-day data history, the full "While you were away" report, one-click clearing and full app removal in Free Up Space, and the full On Screen pin.
"Restore Purchase" is on the same screen. There are no subscriptions.

Thank you,
Anurag Singh
