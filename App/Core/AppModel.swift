import Foundation
import Observation
import SwiftData
import SwiftUI
import SnagKit

enum AppTab: String, Hashable, CaseIterable {
    case today, wishlist, scan, gifts, perks
}

/// What the current window looks like, so views can adapt to iPhone Duo's
/// outer display (vertical side bar), inner display (regular width), the
/// hinge, and big iPhones in landscape.
struct LayoutContext: Equatable {
    enum Hinge: Equatable {
        case none, closed, partiallyOpen, fullyOpen
    }

    var isWide = false
    /// Edge the system put the vertical bar on (Duo outer display), if any.
    var verticalBarEdge: HorizontalEdge?
    var hinge: Hinge = .none
    var hingeAngleDegrees: Double?

    var hasSideBar: Bool { verticalBarEdge != nil }
    /// Phone half-folded and propped up: split content across the fold.
    var isTabletop: Bool { hinge == .partiallyOpen }
}

/// A request to open a shop page in the checkout agent.
struct CheckoutRequest: Identifiable, Hashable {
    var id = UUID()
    var url: URL
    var merchant: String
    var merchantDomain: String?
    var productTitle: String
    var expectedPrice: Double?
    var currency: String
}

/// App-wide state shared by every window.
@Observable
final class AppModel {
    let settings: AppSettings
    let entitlements: EntitlementManager
    let ai = AIService()
    let container: ModelContainer

    var persona: PersonaProfile { didSet { LocalStore.save(persona, named: "persona") } }
    var savedCodes: [SavedCode] { didSet { LocalStore.save(savedCodes, named: "codes") } }

    // Navigation state lives here (not in views) so it survives the layout
    // switch when iPhone Duo folds or unfolds.
    var selectedTab: AppTab = .today
    var wishlistSelection: String?
    var recipientSelection: UUID?
    var checkout: CheckoutRequest?
    var paywallReason: String?
    var toast: (symbol: String, text: String)?
    var layout = LayoutContext()
    var lastForegroundRefresh: Date?
    var apnsToken: String?

    init(container: ModelContainer, settings: AppSettings = AppSettings()) {
        self.container = container
        self.settings = settings
        self.entitlements = EntitlementManager()
        self.persona = LocalStore.load(PersonaProfile.self, named: "persona") ?? PersonaProfile()
        self.savedCodes = LocalStore.load([SavedCode].self, named: "codes") ?? []
    }

    var isPremium: Bool { entitlements.isSubscribed || (settings.testerPremium && entitlements.isTestEnvironment) }

    /// Free tier: watch up to this many items.
    static let freeWatchLimit = 5

    var search: PriceSearchService { Self.makeSearchService(settings: settings) }

    @ObservationIgnored private var searchCache: [String: [PriceSearchService.Result]] = [:]

    /// Keyword search with a session cache, so gift cards don't re-query
    /// shops every time they scroll into view.
    func cachedSearch(_ query: String) async -> [PriceSearchService.Result]? {
        let key = query.lowercased()
        if let cached = searchCache[key] { return cached }
        guard let results = try? await search.search(query: query, region: settings.region, limit: 3) else { return nil }
        searchCache[key] = results
        return results
    }

    static func makeSearchService(settings: AppSettings) -> PriceSearchService {
        let key = settings.upcItemDBKey.trimmingCharacters(in: .whitespaces)
        return PriceSearchService(
            upc: UPCItemDBClient(apiKey: key.isEmpty ? nil : key),
            backend: settings.backendURL.map { SnagBackendClient(baseURL: $0, deviceID: settings.deviceID) }
        )
    }

    var rankingOptions: OfferRanker.Options {
        OfferRanker.Options(
            eligibilities: settings.eligibilities,
            region: settings.region,
            savedCodes: savedCodes,
            knownMerchants: settings.knownMerchants,
            includeUsed: settings.includeUsed
        )
    }

    func showToast(_ text: String, symbol: String = "checkmark.circle.fill") {
        withAnimation(.spring(duration: 0.4)) { toast = (symbol, text) }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }

    // MARK: - Watching

    /// One tap: add to wishlist with a sensible alert.
    @discardableResult
    func watch(product: Product, offers: [Offer], context: ModelContext, recipientID: UUID? = nil) -> WishItem? {
        let id = product.id
        if let existing = try? context.fetch(FetchDescriptor<WishItem>(predicate: #Predicate { $0.productID == id })).first {
            existing.apply(offers: offers, at: .now)
            showToast("Already watching — prices updated")
            return existing
        }
        let watchedCount = (try? context.fetchCount(FetchDescriptor<WishItem>())) ?? 0
        if !isPremium && watchedCount >= Self.freeWatchLimit {
            paywallReason = "Watch unlimited items and get faster price checks with Premium."
            return nil
        }
        let item = WishItem(product: product, offers: offers, currency: settings.currency, recipientID: recipientID)
        if let best = item.bestPrice {
            item.alert = .smartDefault(currentBest: best, currency: settings.currency)
        }
        context.insert(item)
        try? context.save()
        registerServerWatch(item)
        showToast(item.bestPrice == nil ? "Added to wishlist" : "Watching — we'll tell you when it drops 10%", symbol: "bell.badge.fill")
        Task { await Notifier.requestAuthorization() }
        return item
    }

    func registerServerWatch(_ item: WishItem) {
        guard let url = settings.backendURL, let rule = item.alert else { return }
        let client = SnagBackendClient(baseURL: url, deviceID: settings.deviceID)
        let registration = SnagBackendClient.WatchRegistration(
            productID: item.productID, gtin: item.gtin, query: item.product.searchQuery,
            region: settings.region, rule: rule, apnsToken: apnsToken
        )
        Task { try? await client.registerWatch(registration) }
    }

    func refreshWatchedPrices(force: Bool = false) async {
        if !force, let last = lastForegroundRefresh, last > Date(timeIntervalSinceNow: -15 * 60) { return }
        lastForegroundRefresh = .now
        let context = container.mainContext
        let outcome = await PriceWatcher.refresh(context: context, search: search, region: settings.region, minimumAge: force ? 0 : 30 * 60)
        if force {
            showToast(outcome.drops > 0 ? "\(outcome.drops) price drop\(outcome.drops == 1 ? "" : "s")!" : "Checked \(outcome.checked) item\(outcome.checked == 1 ? "" : "s")", symbol: "arrow.clockwise")
        }
        PriceWatcher.scheduleNextRefresh(premium: isPremium)
    }

    // MARK: - Buying

    func buy(_ offer: Offer, productTitle: String) {
        guard let url = offer.url else { return }
        checkout = CheckoutRequest(url: url, merchant: offer.merchant, merchantDomain: offer.merchantDomain, productTitle: productTitle, expectedPrice: offer.totalPrice, currency: offer.currency)
    }

    func recordPurchase(at domain: String?) {
        guard let domain else { return }
        settings.knownMerchants.insert(Offer.normalizedDomain(domain))
    }

    func saveCode(_ code: String, domain: String?, source: SavedCode.Source, saving: Double? = nil) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count >= 3 else { return }
        if let index = savedCodes.firstIndex(where: { $0.code == normalized && $0.merchantDomain == domain.map(Offer.normalizedDomain) }) {
            if let saving {
                savedCodes[index].lastSaving = saving
                savedCodes[index].lastWorkedAt = .now
                savedCodes[index].failures = 0
            }
            return
        }
        savedCodes.append(SavedCode(code: normalized, merchantDomain: domain, source: source, lastWorkedAt: saving == nil ? nil : .now, lastSaving: saving))
    }

    // MARK: - Deep links

    func handle(url: URL) {
        guard url.scheme == "snag" else { return }
        switch url.host() {
        case "scan": selectedTab = .scan
        case "wishlist":
            selectedTab = .wishlist
            wishlistSelection = url.pathComponents.dropFirst().first
        case "gifts": selectedTab = .gifts
        case "perks": selectedTab = .perks
        default: selectedTab = .today
        }
    }

    func openFromNotification(productID: String?, url: URL?, buy: Bool) {
        if buy, let url {
            checkout = CheckoutRequest(url: url, merchant: url.host() ?? "Shop", merchantDomain: url.host(), productTitle: "", expectedPrice: nil, currency: settings.currency)
            return
        }
        selectedTab = .wishlist
        wishlistSelection = productID
    }
}
