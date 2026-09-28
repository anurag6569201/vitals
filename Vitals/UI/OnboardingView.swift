import Combine
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: VitalsModel
    let done: () -> Void
    @State private var launchAtLogin = true
    @State private var notifications = true

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.green.gradient).frame(width: 72, height: 72)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Vitals watches your Mac so you don't have to")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Like a check-engine light: quiet when all is well, clear when it isn't.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                row("waveform.path.ecg", "Quiet until it matters",
                    "One small icon in your menu bar. It only changes color when something needs you.")
                row("text.bubble", "Tells you why, in plain English",
                    "“Chrome has used 180% CPU for 12 minutes” — not a wall of graphs.")
                row("hand.tap", "Fixes in one click",
                    "Quit the app to blame, snooze, or ignore it for good.")
                row("moon.stars", "Knows what happened while you were away",
                    "Find out why your battery dropped overnight.")
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Open Vitals when I log in", isOn: $launchAtLogin)
                Toggle("Notify me about real problems", isOn: $notifications)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)

            Button {
                LaunchAtLogin.set(launchAtLogin)
                model.settings.notificationsEnabled = notifications
                if notifications { Notifier.requestPermission() }
                done()
            } label: {
                Text("Start Watching").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text("Look for \(Image(systemName: "waveform.path.ecg")) in your menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 460)
    }

    private func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
