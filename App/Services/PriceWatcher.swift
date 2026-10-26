import BackgroundTasks
import Foundation
import SwiftData
import SnagKit

/// Keeps watched prices fresh. Runs when the app opens and opportunistically
/// in the background (iOS decides exactly when). With the optional Snag
/// server configured, the server also checks around the clock and pushes.
enum PriceWatcher {
    static let refreshTaskID = "com.oftenunknown.snag.price-refresh"

    /// Ask iOS to wake us again. Premium checks more often.
    static func scheduleNextRefresh(premium: Bool) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: premium ? 60 * 60 : 3 * 60 * 60)
        Task { try? await BGTaskScheduler.shared.submitTaskRequest(request) }
    }

    struct Outcome {
        var checked = 0
        var drops = 0
    }

    /// Re-prices watched items, records history and fires alerts.
    @discardableResult
    static func refresh(
        context: ModelContext,
        search: PriceSearchService,
        region: Region,
        limit: Int = 20,
        minimumAge: TimeInterval = 30 * 60,
        notify: Bool = true
    ) async -> Outcome {
        var outcome = Outcome()
        let descriptor = FetchDescriptor<WishItem>(predicate: #Predicate { !$0.isPurchased })
        guard let items = try? context.fetch(descriptor) else { return outcome }
        let due = items
            .filter { ($0.lastCheckedAt ?? .distantPast) < Date(timeIntervalSinceNow: -minimumAge) }
            .sorted { ($0.lastCheckedAt ?? .distantPast) < ($1.lastCheckedAt ?? .distantPast) }
            .prefix(limit)

        for item in due {
            if Task.isCancelled { break }
            let product = item.product
            let previousHistory = item.history
            let offers = await search.refreshOffers(for: product, region: region)
            item.apply(offers: offers, at: .now)
            outcome.checked += 1

            guard var rule = item.alert, let best = item.bestPrice else { continue }
            let decision = AlertEvaluator.evaluate(rule, currentBest: best, history: previousHistory)
            if case .fire(let price, let drop, let reason) = decision {
                outcome.drops += 1
                rule.lastNotifiedPrice = price
                rule.lastNotifiedAt = .now
                item.alert = rule
                item.lastAlertAt = .now
                if notify {
                    await Notifier.postPriceDrop(
                        item: product.title, productID: item.productID, price: price, currency: item.currency,
                        merchant: item.bestMerchant, dropFraction: drop, url: item.bestURLString.flatMap(URL.init(string:)), reason: reason
                    )
                }
            }
        }
        try? context.save()
        return outcome
    }

    /// Entry point for the BGAppRefreshTask.
    static func runBackgroundRefresh(container: ModelContainer) async {
        let settings = AppSettings()
        let context = ModelContext(container)
        let search = AppModel.makeSearchService(settings: settings)
        await refresh(context: context, search: search, region: settings.region, limit: 12, minimumAge: 20 * 60)
        scheduleNextRefresh(premium: settings.testerPremium || EntitlementManager.cachedPremium)
    }
}
