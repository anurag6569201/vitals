import Combine
import SwiftUI

enum VitalsPreferenceMigration {
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard Bundle.main.bundleIdentifier == "com.anuragsingh.vitals" else { return }
        let marker = "vitals.migratedFromLegacyBundle.v1"
        guard !defaults.bool(forKey: marker) else { return }
        let oldDefaults = UserDefaults(suiteName: "anurag.Vitals")
        for key in ["vitals.configuration.v1", "vitals.hiddenMenuApps.v1",
                    "vitals.hiddenSystemItems.v1", "vitals.hubOrder.v1",
                    "vitals.profiles.v1", "vitals.activeProfile.v1",
                    "accent", "menuPrimary", "menuSecondary", "showNetwork",
                    "showCPU", "showMemory", "showBattery"] {
            if defaults.object(forKey: key) == nil, let saved = oldDefaults?.object(forKey: key) {
                defaults.set(saved, forKey: key)
            }
        }
        defaults.set(true, forKey: marker)
    }
}

enum MetricKind: String, Codable, CaseIterable, Identifiable {
    case download, upload, cpu, memory, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: "Download"
        case .upload: "Upload"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .battery: "Battery"
        }
    }

    var shortLabel: String {
        switch self {
        case .download: "↓"
        case .upload: "↑"
        case .cpu: "CPU"
        case .memory: "MEM"
        case .battery: "BAT"
        }
    }

    var symbol: String {
        switch self {
        case .download: "arrow.down.left"
        case .upload: "arrow.up.right"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .battery: "battery.100percent"
        }
    }
}

enum MetricPlacement: String, Codable, CaseIterable, Identifiable {
    case menuBar, panel, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .menuBar: "Bar + panel"
        case .panel: "Panel only"
        case .hidden: "Hidden"
        }
    }
}

enum MenuDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case compact, descriptive
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case mint, blue, orange
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .mint: Color(red: 0.30, green: 0.91, blue: 0.71)
        case .blue: Color(red: 0.44, green: 0.68, blue: 1.00)
        case .orange: Color(red: 1.00, green: 0.67, blue: 0.42)
        }
    }
}

enum QuickAction: String, Codable, CaseIterable, Identifiable {
    case activityMonitor, systemSettings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .activityMonitor: "Activity Monitor"
        case .systemSettings: "System Settings"
        }
    }
    var symbol: String {
        switch self {
        case .activityMonitor: "waveform.path.ecg.rectangle"
        case .systemSettings: "gearshape"
        }
    }
}

struct MetricPreference: Codable, Identifiable, Equatable {
    var kind: MetricKind
    var placement: MetricPlacement
    var id: MetricKind { kind }
}

struct VitalsConfiguration: Codable, Equatable {
    var metrics: [MetricPreference] = [
        .init(kind: .download, placement: .menuBar),
        .init(kind: .upload, placement: .panel),
        .init(kind: .cpu, placement: .menuBar),
        .init(kind: .memory, placement: .panel),
        .init(kind: .battery, placement: .panel)
    ]
    var theme: AccentTheme = .mint
    var style: MenuDisplayStyle = .compact
    var showIcon = true
    var showHubPreview = true
    var smartPriority = true
    var quickActions: [QuickAction] = [.activityMonitor, .systemSettings]

    private enum CodingKeys: String, CodingKey {
        case metrics, theme, style, showIcon, showHubPreview, smartPriority, quickActions
    }

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metrics = try container.decodeIfPresent([MetricPreference].self, forKey: .metrics) ?? metrics
        theme = try container.decodeIfPresent(AccentTheme.self, forKey: .theme) ?? theme
        style = try container.decodeIfPresent(MenuDisplayStyle.self, forKey: .style) ?? style
        showIcon = try container.decodeIfPresent(Bool.self, forKey: .showIcon) ?? showIcon
        showHubPreview = try container.decodeIfPresent(Bool.self, forKey: .showHubPreview) ?? showHubPreview
        smartPriority = try container.decodeIfPresent(Bool.self, forKey: .smartPriority) ?? smartPriority
        quickActions = try container.decodeIfPresent([QuickAction].self, forKey: .quickActions) ?? quickActions
    }

    var menuMetrics: [MetricKind] {
        metrics.filter { $0.placement == .menuBar }.map(\.kind)
    }

    var panelMetrics: [MetricKind] {
        metrics.filter { $0.placement != .hidden }.map(\.kind)
    }
}

enum LayoutPreset: String, CaseIterable, Identifiable {
    case balanced, network, performance, minimal
    var id: String { rawValue }
    var title: String { self == .minimal ? "Hub only" : rawValue.capitalized }

    var metrics: [MetricPreference] {
        let order: [MetricKind]
        let bar: Set<MetricKind>
        switch self {
        case .balanced:
            order = [.download, .upload, .cpu, .memory, .battery]
            bar = [.download, .cpu]
        case .network:
            order = [.download, .upload, .cpu, .memory, .battery]
            bar = [.download, .upload]
        case .performance:
            order = [.cpu, .memory, .battery, .download, .upload]
            bar = [.cpu, .memory]
        case .minimal:
            order = [.download, .upload, .cpu, .memory, .battery]
            bar = []
        }
        return order.map { .init(kind: $0, placement: bar.contains($0) ? .menuBar : .panel) }
    }
}

@MainActor
final class VitalsConfigurationStore: ObservableObject {
    @Published private(set) var configuration: VitalsConfiguration {
        didSet { save() }
    }
    @Published private(set) var message: String?

    private let storageKey = "vitals.configuration.v1"

    init(defaults: UserDefaults = .standard) {
        VitalsPreferenceMigration.migrateIfNeeded(defaults: defaults)
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(VitalsConfiguration.self, from: data) {
            configuration = Self.validated(saved)
        } else {
            configuration = Self.migrated(from: defaults)
        }
    }

    func placement(for kind: MetricKind) -> MetricPlacement {
        configuration.metrics.first { $0.kind == kind }?.placement ?? .panel
    }

    func setPlacement(_ placement: MetricPlacement, for kind: MetricKind) {
        if placement == .menuBar,
           self.placement(for: kind) != .menuBar,
           configuration.menuMetrics.count >= 3 {
            message = "Keep up to three readings in the menu bar. Move one to the panel first."
            return
        }
        var updated = configuration
        guard let index = updated.metrics.firstIndex(where: { $0.kind == kind }) else { return }
        updated.metrics[index].placement = placement
        configuration = updated
        message = nil
    }

    func move(_ kind: MetricKind, by offset: Int) {
        var updated = configuration
        guard let index = updated.metrics.firstIndex(where: { $0.kind == kind }),
              updated.metrics.indices.contains(index + offset) else { return }
        updated.metrics.swapAt(index, index + offset)
        configuration = updated
        message = nil
    }

    func apply(_ preset: LayoutPreset) {
        var updated = configuration
        updated.metrics = preset.metrics
        configuration = updated
        message = nil
    }

    func restore(_ saved: VitalsConfiguration) {
        configuration = Self.validated(saved)
        message = nil
    }

    func setTheme(_ theme: AccentTheme) {
        var updated = configuration
        updated.theme = theme
        configuration = updated
    }

    func setStyle(_ style: MenuDisplayStyle) {
        var updated = configuration
        updated.style = style
        configuration = updated
    }

    func setShowIcon(_ show: Bool) {
        var updated = configuration
        updated.showIcon = show
        configuration = updated
    }

    func setShowHubPreview(_ show: Bool) {
        var updated = configuration
        updated.showHubPreview = show
        configuration = updated
    }

    func setSmartPriority(_ enabled: Bool) {
        var updated = configuration
        updated.smartPriority = enabled
        configuration = updated
    }

    func setQuickAction(_ action: QuickAction, enabled: Bool) {
        var updated = configuration
        updated.quickActions.removeAll { $0 == action }
        if enabled { updated.quickActions.append(action) }
        configuration = updated
    }

    func menuMetrics(priority: MetricKind?) -> [MetricKind] {
        var visible = configuration.menuMetrics
        if configuration.smartPriority,
           let priority,
           !visible.isEmpty,
           placement(for: priority) != .hidden,
           !visible.contains(priority) {
            visible.removeLast()
            visible.insert(priority, at: 0)
        }
        return visible
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func validated(_ configuration: VitalsConfiguration) -> VitalsConfiguration {
        var result = configuration
        var seen = Set<MetricKind>()
        result.metrics = configuration.metrics.filter { seen.insert($0.kind).inserted }
        for kind in MetricKind.allCases where !seen.contains(kind) {
            result.metrics.append(.init(kind: kind, placement: .panel))
        }
        var barCount = 0
        for index in result.metrics.indices where result.metrics[index].placement == .menuBar {
            barCount += 1
            if barCount > 3 { result.metrics[index].placement = .panel }
        }
        result.quickActions = Array(Set(result.quickActions)).sorted { $0.rawValue < $1.rawValue }
        return result
    }

    private static func migrated(from defaults: UserDefaults) -> VitalsConfiguration {
        var result = VitalsConfiguration()
        if let oldTheme = defaults.string(forKey: "accent").flatMap(AccentTheme.init(rawValue:)) {
            result.theme = oldTheme
        }
        let oldPrimary = defaults.string(forKey: "menuPrimary").flatMap(MetricKind.init(rawValue:))
        let oldSecondary = defaults.string(forKey: "menuSecondary").flatMap(MetricKind.init(rawValue:))
        if oldPrimary != nil || oldSecondary != nil {
            let selected = Set([oldPrimary, oldSecondary].compactMap { $0 })
            result.metrics = result.metrics.map {
                .init(kind: $0.kind, placement: selected.contains($0.kind) ? .menuBar : .panel)
            }
        }
        for (key, kinds) in [
            ("showNetwork", [MetricKind.download, .upload]),
            ("showCPU", [.cpu]),
            ("showMemory", [.memory]),
            ("showBattery", [.battery])
        ] {
            if defaults.object(forKey: key) as? Bool == false {
                for index in result.metrics.indices where kinds.contains(result.metrics[index].kind) {
                    result.metrics[index].placement = .hidden
                }
            }
        }
        return validated(result)
    }
}
