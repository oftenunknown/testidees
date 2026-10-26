import Foundation
import StoreKit

/// Snag Premium via StoreKit 2 auto-renewable subscriptions.
@Observable
final class EntitlementManager {
    static let productIDs = ["snag.premium.monthly", "snag.premium.yearly"]
    private static let cacheKey = "premiumCached"

    /// Last known state, for background tasks that can't await StoreKit.
    static var cachedPremium: Bool { UserDefaults.standard.bool(forKey: cacheKey) }

    private(set) var isSubscribed = false
    private(set) var products: [Product] = []
    private(set) var isTestEnvironment = false
    private var updates: Task<Void, Never>?

    init() {
        isSubscribed = Self.cachedPremium
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
    }

    func start() async {
        await refresh()
        if let result = try? await AppTransaction.shared, case .verified(let app) = result {
            isTestEnvironment = app.environment == .sandbox || app.environment == .xcode
        }
        #if DEBUG
        isTestEnvironment = true
        #endif
        products = (try? await Product.products(for: Self.productIDs)) ?? []
    }

    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
        UserDefaults.standard.set(active, forKey: Self.cacheKey)
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
