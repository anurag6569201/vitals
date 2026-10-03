import Combine
import CryptoKit
import Foundation
import IOKit
import StoreKit

/// Fill these in before release. See RELEASE.md.
enum LicenseConfig {
    /// Mac App Store in-app purchase (non-consumable).
    static let storeKitProductID = "com.anuragsingh.vitals.pro"
    /// Mac App Store free trial: a $0 non-consumable ("Price: Free") that starts the trial clock,
    /// as App Review guideline 3.1.1 requires for time-limited trials of non-subscription apps.
    static let storeKitTrialProductID = "com.anuragsingh.vitals.trial"
    /// Lemon Squeezy checkout link for the direct-download build.
    static let checkoutURL = URL(string: "https://vitals.lemonsqueezy.com/buy/REPLACE-WITH-YOUR-PRODUCT")!
    /// Optional: your Lemon Squeezy store id, to reject keys from other stores.
    static let lemonSqueezyStoreID: Int? = nil
    static let trialDays = 7
    /// Shown until StoreKit reports the localized App Store price. Keep in sync with Lemon Squeezy
    /// and the App Store Connect price (see RELEASE.md › Pricing).
    static let displayPrice = "$9.99"
    /// Vitals license server (site/functions/api on Cloudflare Pages). Issues one key per App Store purchase and
    /// activates keys in the direct edition, one Mac per key.
    static let licenseServer = URL(string: "https://vitalsformac.com/api")!
    /// Ed25519 public key (base64, 32 bytes) from `node scripts/license-keys.js`.
    /// Verifies activation tokens offline.
    static let licensePublicKey = "pJiLuKE5Tj3SMjn34XJPzcCu8ZcULMjzx9ZAYruY1oE="
    static var licenseServerConfigured: Bool {
        !licenseServer.absoluteString.contains("REPLACE") && !licensePublicKey.contains("REPLACE")
    }
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
    /// App Store edition: the license key for using Pro outside the App Store (one Mac).
    @Published private(set) var appStoreKey: String?

    let usesAppStore = Edition.isAppStore
    /// App Store edition: whether the free trial can still be started.
    @Published private(set) var canStartTrial = false

    private let defaults = UserDefaults.standard
    private var updatesTask: Task<Void, Never>?

    private enum Keys {
        static let firstLaunch = "vitals.license.firstLaunch"
        static let licenseKey = "vitals.license.key"
        static let instanceID = "vitals.license.instance"
        static let lastValidated = "vitals.license.lastValidated"
        static let storePro = "vitals.license.storePro"
        static let storeTrialStart = "vitals.license.storeTrialStart"
        static let storeLicenseKey = "vitals.license.storeKey"
        static let activationToken = "vitals.license.token"
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
        appStoreKey = defaults.string(forKey: Keys.storeLicenseKey)
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
        #if DEBUG && APPSTORE
        // Testing the App Store edition from Xcode: launch with `-forcePro` to unlock Pro without
        // a purchase. Never in archived builds (the AppStore configuration has no DEBUG flag).
        if ProcessInfo.processInfo.arguments.contains("-forcePro") {
            state = .pro
            return
        }
        #endif
        let owned = usesAppStore ? defaults.bool(forKey: Keys.storePro) : hasValidDirectLicense
        if owned {
            state = .pro
            return
        }
        let trialStart = usesAppStore ? defaults.object(forKey: Keys.storeTrialStart) as? Date
                                      : defaults.object(forKey: Keys.firstLaunch) as? Date
        guard let first = trialStart else {
            state = .free
            return
        }
        let used = Int(Date().timeIntervalSince(first) / 86_400)
        let left = LicenseConfig.trialDays - used
        state = left > 0 ? .trial(daysLeft: left) : .free
    }

    var priceText: String { storeProduct?.displayPrice ?? LicenseConfig.displayPrice }

    // MARK: Direct (Lemon Squeezy)

    /// Direct edition: a Lemon Squeezy key, or a VITALS- key from an App Store purchase
    /// (verified by its signed activation token).
    private var hasValidDirectLicense: Bool {
        guard let key = licenseKey else { return false }
        guard Self.isVitalsKey(key) else { return true }
        return defaults.string(forKey: Keys.activationToken).map { Self.verify(token: $0, key: key) } ?? false
    }

    static func isVitalsKey(_ key: String) -> Bool { key.uppercased().hasPrefix("VITALS-") }

    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if Self.isVitalsKey(key) {
            await activateVitalsKey(key.uppercased())
            return
        }
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

    private func activateVitalsKey(_ key: String) async {
        guard LicenseConfig.licenseServerConfigured else {
            message = "Licenses from the App Store can't be activated in this build yet."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let (status, json) = try await callServer("license/activate", [
                "key": key, "machine": Self.machineID, "name": Host.current().localizedName ?? "Mac",
            ])
            guard status == 200, let token = json["token"] as? String, Self.verify(token: token, key: key) else {
                message = (json["message"] as? String) ?? "That key couldn't be activated."
                return
            }
            defaults.set(key, forKey: Keys.licenseKey)
            defaults.set(token, forKey: Keys.activationToken)
            defaults.set(Date(), forKey: Keys.lastValidated)
            message = "Thank you! Vitals Pro is unlocked on this Mac."
            refreshState()
        } catch {
            message = "Couldn't reach the license server. Check your connection and try again."
        }
    }

    func deactivate() async {
        if let key = licenseKey, Self.isVitalsKey(key) {
            _ = try? await callServer("license/deactivate", ["key": key, "machine": Self.machineID])
            defaults.removeObject(forKey: Keys.activationToken)
        } else if let key = licenseKey, let instance = defaults.string(forKey: Keys.instanceID) {
            _ = try? await post("deactivate", ["license_key": key, "instance_id": instance])
        }
        defaults.removeObject(forKey: Keys.licenseKey)
        defaults.removeObject(forKey: Keys.instanceID)
        message = "This Mac's license was removed. You can now activate the key on another Mac."
        refreshState()
    }

    /// Re-checks the key every two weeks. Offline is fine: only an explicit "invalid" removes Pro.
    private func revalidateIfNeeded() {
        guard let key = licenseKey else { return }
        let last = defaults.object(forKey: Keys.lastValidated) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 14 * 86_400 else { return }
        if Self.isVitalsKey(key) {
            Task {
                guard let (status, json) = try? await callServer("license/validate", ["key": key, "machine": Self.machineID]),
                      status == 200 else { return }   // offline or server trouble: keep Pro
                if json["valid"] as? Bool == true {
                    defaults.set(Date(), forKey: Keys.lastValidated)
                } else if json["valid"] as? Bool == false {
                    defaults.removeObject(forKey: Keys.licenseKey)
                    defaults.removeObject(forKey: Keys.activationToken)
                    message = json["reason"] as? String == "revoked"
                        ? "This license is no longer valid, so Pro is locked again. Contact support if this looks wrong."
                        : "This Mac's license is no longer active. Activate your key again in Settings › Pro."
                    refreshState()
                }
            }
            return
        }
        guard let instance = defaults.string(forKey: Keys.instanceID) else { return }
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

    // MARK: Vitals license server

    private func callServer(_ path: String, _ body: [String: String]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: LicenseConfig.licenseServer.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    /// An activation token is `base64url(payload).base64url(signature)`, signed by the server's
    /// Ed25519 key. Checks the signature, that it names this key, and this Mac.
    static func verify(token: String, key: String) -> Bool {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 2,
              let payload = base64URL(parts[0]), let signature = base64URL(parts[1]),
              let rawKey = Data(base64Encoded: LicenseConfig.licensePublicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
              publicKey.isValidSignature(signature, for: payload),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return false }
        return (json["key"] as? String) == key.uppercased() && (json["machine"] as? String) == machineID
    }

    private static func base64URL(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    /// A stable, anonymous id for this Mac: SHA-256 of its hardware UUID plus a Vitals salt,
    /// so the real hardware id never leaves the Mac.
    static let machineID: String = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let uuid = (IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String) ?? Host.current().localizedName ?? "unknown"
        let digest = SHA256.hash(data: Data("vitals-license:\(uuid)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

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
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                refreshStoreEntitlement()
                message = "Thank you! Vitals Pro is unlocked — on every Mac signed in to your Apple Account."
            case .success(.unverified):
                message = "The App Store couldn't verify that purchase. Try Restore Purchase in a moment."
            case .pending:
                message = "Waiting for approval (Ask to Buy or a payment check). Pro unlocks automatically once it's approved."
            case .userCancelled:
                message = nil
            @unknown default:
                message = nil
            }
        } catch {
            message = "The purchase didn't go through: \(error.localizedDescription)"
        }
    }

    /// App Store edition: "buys" the $0 trial item, which starts the 7 days.
    func startTrial() async {
        isWorking = true
        defer { isWorking = false }
        guard let product = try? await Product.products(for: [LicenseConfig.storeKitTrialProductID]).first else {
            message = "The App Store isn't available right now."
            return
        }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                refreshStoreEntitlement()
                message = "Your \(LicenseConfig.trialDays)-day trial has started. Everything is unlocked."
            case .pending:
                message = "Waiting for approval. Your trial starts once it's approved."
            default:
                break
            }
        } catch {
            message = "The trial couldn't start. Try again in a moment."
        }
    }

    func restore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AppStore.sync()
        } catch {
            message = "Couldn't reach the App Store. Check your connection and try again."
            return
        }
        let owned = await ownsPro()
        refreshStoreEntitlement()
        message = owned ? "Restored — Vitals Pro is unlocked." : "No Vitals Pro purchase was found for this Apple Account."
    }

    private func ownsPro() async -> Bool {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == LicenseConfig.storeKitProductID, t.revocationDate == nil {
                return true
            }
        }
        return false
    }

    /// App Store edition: get (or re-show) the license key for using Pro outside the App Store.
    /// Sends the Apple-signed purchase record to the license server, which checks Apple's
    /// signature and returns one key per purchase.
    func claimLicenseKey() async {
        guard LicenseConfig.licenseServerConfigured else {
            message = "License keys aren't available yet."
            return
        }
        isWorking = true
        defer { isWorking = false }
        var jws: String?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == LicenseConfig.storeKitProductID, t.revocationDate == nil {
                jws = entitlement.jwsRepresentation
            }
        }
        guard let jws else {
            message = "Buy Vitals Pro first — the key comes with the purchase."
            return
        }
        do {
            let (status, json) = try await callServer("license/claim", ["transaction": jws])
            guard status == 200, let key = json["key"] as? String else {
                message = (json["message"] as? String) ?? "Couldn't get your license key. Try again in a moment."
                return
            }
            defaults.set(key, forKey: Keys.storeLicenseKey)
            appStoreKey = key
            message = nil
        } catch {
            message = "Couldn't reach the license server. Check your connection and try again."
        }
    }

    private func refreshStoreEntitlement() {
        Task {
            var owned = false
            var trialStart: Date?
            for await entitlement in Transaction.currentEntitlements {
                guard case .verified(let transaction) = entitlement, transaction.revocationDate == nil else { continue }
                if transaction.productID == LicenseConfig.storeKitProductID { owned = true }
                if transaction.productID == LicenseConfig.storeKitTrialProductID { trialStart = transaction.purchaseDate }
            }
            if !owned {
                // No longer owned (e.g. Apple reversed the purchase): forget the key shown in Settings.
                defaults.removeObject(forKey: Keys.storeLicenseKey)
                appStoreKey = nil
            }
            defaults.set(owned, forKey: Keys.storePro)
            defaults.set(trialStart, forKey: Keys.storeTrialStart)
            canStartTrial = !owned && trialStart == nil
            refreshState()
        }
    }
}
