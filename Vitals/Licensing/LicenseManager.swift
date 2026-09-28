import Combine
import Foundation
import StoreKit

/// Fill these in before release. See RELEASE.md.
enum LicenseConfig {
    /// Mac App Store in-app purchase (non-consumable).
    static let storeKitProductID = "com.anuragsingh.vitals.pro"
    /// Lemon Squeezy checkout link for the direct-download build.
    static let checkoutURL = URL(string: "https://vitals.lemonsqueezy.com/buy/REPLACE-WITH-YOUR-PRODUCT")!
    /// Optional: your Lemon Squeezy store id, to reject keys from other stores.
    static let lemonSqueezyStoreID: Int? = nil
    static let trialDays = 14
    static let displayPrice = "$12.99"
}

enum LicenseState: Equatable {
    case trial(daysLeft: Int)
    case pro
    case free
}

@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var state: LicenseState = .free
    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published private(set) var storeProduct: Product?

    let usesAppStore = SystemSampler.isSandboxed

    private let defaults = UserDefaults.standard
    private var updatesTask: Task<Void, Never>?

    private enum Keys {
        static let firstLaunch = "vitals.license.firstLaunch"
        static let licenseKey = "vitals.license.key"
        static let instanceID = "vitals.license.instance"
        static let lastValidated = "vitals.license.lastValidated"
        static let storePro = "vitals.license.storePro"
    }

    var isPro: Bool {
        switch state {
        case .pro, .trial: true
        case .free: false
        }
    }

    var licenseKey: String? { defaults.string(forKey: Keys.licenseKey) }

    init() {
        if defaults.object(forKey: Keys.firstLaunch) == nil {
            defaults.set(Date(), forKey: Keys.firstLaunch)
        }
        refreshState()
        if usesAppStore {
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update {
                        await transaction.finish()
                        self?.refreshStoreEntitlement()
                    }
                }
            }
            refreshStoreEntitlement()
            Task { await loadProduct() }
        } else {
            revalidateIfNeeded()
        }
    }

    func refreshState() {
        let owned = usesAppStore ? defaults.bool(forKey: Keys.storePro) : (licenseKey != nil)
        if owned {
            state = .pro
            return
        }
        let first = defaults.object(forKey: Keys.firstLaunch) as? Date ?? Date()
        let used = Int(Date().timeIntervalSince(first) / 86_400)
        let left = LicenseConfig.trialDays - used
        state = left > 0 ? .trial(daysLeft: left) : .free
    }

    var priceText: String { storeProduct?.displayPrice ?? LicenseConfig.displayPrice }

    // MARK: Direct (Lemon Squeezy)

    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let json = try await post("activate", ["license_key": key, "instance_name": Host.current().localizedName ?? "Mac"])
            guard json["activated"] as? Bool == true else {
                message = (json["error"] as? String) ?? "That key couldn't be activated."
                return
            }
            if let required = LicenseConfig.lemonSqueezyStoreID,
               let meta = json["meta"] as? [String: Any], (meta["store_id"] as? Int) != required {
                message = "That key belongs to a different product."
                return
            }
            let instance = (json["instance"] as? [String: Any])?["id"] as? String
            defaults.set(key, forKey: Keys.licenseKey)
            defaults.set(instance, forKey: Keys.instanceID)
            defaults.set(Date(), forKey: Keys.lastValidated)
            message = "Thank you! Vitals Pro is unlocked."
            refreshState()
        } catch {
            message = "Couldn't reach the license server. Check your connection and try again."
        }
    }

    func deactivate() async {
        if let key = licenseKey, let instance = defaults.string(forKey: Keys.instanceID) {
            _ = try? await post("deactivate", ["license_key": key, "instance_id": instance])
        }
        defaults.removeObject(forKey: Keys.licenseKey)
        defaults.removeObject(forKey: Keys.instanceID)
        message = "This Mac's license was removed."
        refreshState()
    }

    /// Re-checks the key every two weeks. Offline is fine: only an explicit "invalid" removes Pro.
    private func revalidateIfNeeded() {
        guard let key = licenseKey, let instance = defaults.string(forKey: Keys.instanceID) else { return }
        let last = defaults.object(forKey: Keys.lastValidated) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 14 * 86_400 else { return }
        Task {
            guard let json = try? await post("validate", ["license_key": key, "instance_id": instance]) else { return }
            if json["valid"] as? Bool == true {
                defaults.set(Date(), forKey: Keys.lastValidated)
            } else if json["valid"] as? Bool == false {
                defaults.removeObject(forKey: Keys.licenseKey)
                refreshState()
            }
        }
    }

    private func post(_ endpoint: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: Mac App Store

    func loadProduct() async {
        storeProduct = try? await Product.products(for: [LicenseConfig.storeKitProductID]).first
    }

    func purchase() async {
        if storeProduct == nil { await loadProduct() }
        guard let product = storeProduct else {
            message = "The App Store isn't available right now."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result, case .verified(let transaction) = verification {
                await transaction.finish()
                refreshStoreEntitlement()
                message = "Thank you! Vitals Pro is unlocked."
            }
        } catch {
            message = "The purchase didn't go through."
        }
    }

    func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        refreshStoreEntitlement()
    }

    private func refreshStoreEntitlement() {
        Task {
            var owned = false
            for await entitlement in Transaction.currentEntitlements {
                if case .verified(let transaction) = entitlement,
                   transaction.productID == LicenseConfig.storeKitProductID,
                   transaction.revocationDate == nil {
                    owned = true
                }
            }
            defaults.set(owned, forKey: Keys.storePro)
            refreshState()
        }
    }
}
