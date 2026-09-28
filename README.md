# Vitals

Vitals is a macOS menu-bar hub. On macOS 27, it can discover and hide real menu-bar icons from third-party apps and selected Apple system controls, while keeping those icons reachable from one Vitals popup. It also shows live network, CPU, memory, and battery readings.

Vitals also opens a small dashboard window and appears in the Dock. This is a recovery path if macOS hides or clips its menu-bar item: click the Dock icon to reopen the window. Close the window to keep Vitals running in the menu bar.

The popup groups app shortcuts and system controls above compact live readings. Its menu-bar item can preview a few hub icons beside your chosen stats; click Vitals to open the shortcuts. Turn **Preview hub icons in menu bar** off in Customize if you prefer a readings-only status item. The number of icon previews adapts to the space used by your selected stats.

## Try icon control

1. Build and launch Vitals, then click its menu-bar item.
2. Click **Enable Accessibility** and grant the exact Vitals copy you launched access in System Settings → Privacy & Security → **Device Control and Data Access** (macOS 27). If it is not listed, click **Add** and select that app. An older Vitals build being enabled does not grant this copy access. Return to Vitals; it now checks automatically, or click **Check again**. If macOS still reports no access, quit and reopen this Vitals copy. Keep it in a stable location after granting access.
3. In **Customize Vitals → Your menu-bar icons**, use the switches to hide third-party apps or selected Apple controls. Hidden items appear in the Vitals hub automatically. Star a visible app to keep a shortcut in the hub too; use the arrows to set hub order.
4. Click an app tile in the hub to open its menu using Accessibility. A hidden system control is revealed before Vitals tries to open it. If an item cannot be opened automatically, Vitals reveals it and tells you to click it in the menu bar.
5. Save the current icon choices, hub order, readings, and appearance as a named layout in **Customize Vitals → Saved menu-bar layouts**. Switch layouts from the Vitals popup; edit a layout and click **Update** to overwrite it. Unsaved changes are marked.
6. Use **Reveal all icons** to temporarily show everything, **Hide selected icons** to reapply your choices, or **Reset icons** to clear the current icon choices. Quitting Vitals restores all icons.

Preferences are saved locally. An app switch affects all menu-bar icons owned by that app; if it owns multiple icons, each gets its own hub tile. Clock and Control Center are deliberately protected. You can reorder shortcuts *inside Vitals*; the Mac's physical menu-bar order remains under macOS control (hold ⌘ and drag an icon in the menu bar).

## Live readings and customization

Vitals shows network download/upload rates, approximate CPU and memory use, and battery level. Click the sliders button to open **Customize Vitals**, where you can choose placement, order, appearance, presets (including **Hub only**, which removes readings from Vitals' menu-bar label), accent, quick actions, and optional launch at login. This window is separate from the menu-bar popup and saves changes immediately.

## Compatibility and limitations

- Icon hiding requires macOS 27, Accessibility access, and a private Apple framework (`MenuBarClientCore`). The app resolves the framework at runtime and reports if it is unavailable. Because Apple can change this API, icon hiding is an experimental feature and cannot be promised across future macOS updates.
- The icon-control build is unsandboxed and is not suitable for Mac App Store distribution as-is. The live-readings portion supports macOS 14 or newer.
- Launch at login uses Apple's Service Management framework. If macOS says approval is required, enable Vitals in System Settings → General → Login Items. Keep the app in a stable location, ideally Applications, before enabling this.
- macOS's underlying assessment-mode restriction can block Notification Center. Vitals temporarily lifts it when you hover over the clock; click **Reveal all icons** or quit Vitals if that does not work on your setup.
- Vitals never turns off Wi-Fi, Bluetooth, or another system feature; it only changes menu-bar visibility.
- Network readings are transfer rates from active non-loopback interfaces, not an internet speed test. Multiple active interfaces or VPNs can double-count some traffic. Memory use is approximate. No telemetry is sent anywhere.

## Build

Open `Vitals.xcodeproj` in Xcode and run the `Vitals` scheme. The dashboard window opens automatically; the same controls are available from the Vitals menu-bar item. There are no package dependencies. A stable signing identity is recommended because macOS may forget Accessibility access when an ad-hoc or unsigned build changes.

The menu-bar hiding bridge is adapted from [MenuBarHider](https://github.com/happy666End/MenuBarHider) under the MIT license; see `THIRD_PARTY_NOTICES.md`.
