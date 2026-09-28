import AppKit
import Combine
import Foundation

/// Minimal update check for the direct-download build (the App Store handles its own updates).
/// Reads a tiny JSON file you host, e.g. on GitHub Pages:
/// { "version": "1.0.1", "url": "https://…/Vitals-1.0.1.dmg", "notes": "Fixes…" }
@MainActor
final class UpdateChecker: ObservableObject {
    static let feedURL = URL(string: "https://REPLACE-WITH-YOUR-SITE/vitals/latest.json")!

    struct Release: Decodable {
        let version: String
        let url: URL
        let notes: String?
    }

    @Published private(set) var available: Release?
    private var lastCheck: Date?

    func checkIfNeeded() {
        guard !SystemSampler.isSandboxed, !Self.feedURL.absoluteString.contains("REPLACE") else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 86_400 { return }
        lastCheck = Date()
        Task {
            guard let response = try? await URLSession.shared.data(from: Self.feedURL),
                  let release = try? JSONDecoder().decode(Release.self, from: response.0) else { return }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            if release.version.compare(current, options: .numeric) == .orderedDescending {
                available = release
            }
        }
    }

    func openDownload() {
        if let url = available?.url { NSWorkspace.shared.open(url) }
    }
}
