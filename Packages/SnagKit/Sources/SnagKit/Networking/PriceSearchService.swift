import Foundation

/// One entry point for "what is this and where is it cheapest?". Queries every
/// configured source in parallel and merges the answers.
public struct PriceSearchService: Sendable {
    public var upc: UPCItemDBClient
    public var food: OpenFoodFactsClient
    public var openPrices: OpenPricesClient
    public var backend: SnagBackendClient?

    public init(
        upc: UPCItemDBClient = UPCItemDBClient(),
        food: OpenFoodFactsClient = OpenFoodFactsClient(),
        openPrices: OpenPricesClient = OpenPricesClient(),
        backend: SnagBackendClient? = nil
    ) {
        self.upc = upc
        self.food = food
        self.openPrices = openPrices
        self.backend = backend
    }

    public struct Result: Sendable, Hashable {
        public var product: Product
        public var offers: [Offer]
        /// Sources that failed, so the UI can say "some prices may be missing".
        public var degradedSources: [String]
    }

    /// Barcode scan → product + offers.
    public func lookup(code: String, isUPCE: Bool = false, region: Region) async throws -> Result {
        guard let gtin = GTIN.normalize(code, isUPCE: isUPCE) else { throw LookupError.invalidCode }

        async let upcResult = capture { try await upc.lookup(gtin: gtin) }
        async let foodResult = capture { try await food.lookup(gtin: gtin) }
        async let shelfResult = capture { try await openPrices.recentPrices(gtin: gtin, currency: region.currencyCode, countryCode: region == .uk ? "GB" : region == .us ? "US" : nil) }

        let (u, f, s) = await (upcResult, foodResult, shelfResult)
        var degraded: [String] = []

        var product: Product
        var offers: [Offer] = []
        switch (u, f) {
        case (.success(let r), _):
            product = r.product
            offers += r.offers
            if case .success(let foodProduct) = f, product.imageURLs.isEmpty { product.imageURLs = foodProduct.imageURLs }
        case (.failure(let error), .success(let foodProduct)):
            product = foodProduct
            if case LookupError.rateLimited = error { degraded.append("UPCitemdb") }
        case (.failure(let e1), .failure):
            throw e1
        }

        switch s {
        case .success(let shelf): offers += shelf
        case .failure: degraded.append("Open Prices")
        }

        if let backend {
            let query = product.searchQuery
            switch await capture({ try await backend.offers(query: query, gtin: gtin, region: region) }) {
            case .success(let live): offers += live
            case .failure: degraded.append("Live shopping search")
            }
        }

        return Result(product: product, offers: Self.dedupe(offers), degradedSources: degraded)
    }

    /// Keyword search (photo recognition, gift ideas) → best matching products.
    public func search(query: String, region: Region, limit: Int = 6) async throws -> [Result] {
        var results: [Result] = []
        var degraded: [String] = []

        switch await capture({ try await upc.search(query) }) {
        case .success(let found):
            results = found.prefix(limit).map { Result(product: $0.product, offers: Self.dedupe($0.offers), degradedSources: []) }
        case .failure:
            degraded.append("UPCitemdb")
        }

        if let backend {
            if case .success(let live) = await capture({ try await backend.offers(query: query, gtin: nil, region: region) }), !live.isEmpty {
                let product = Product(title: query, imageURLs: [], source: .backend)
                results.insert(Result(product: product, offers: Self.dedupe(live), degradedSources: []), at: 0)
            }
        }

        if results.isEmpty, !degraded.isEmpty { throw LookupError.rateLimited(retryAfter: nil) }
        return results.map { var r = $0; r.degradedSources = degraded; return r }
    }

    /// Re-prices a watched product (background refresh).
    public func refreshOffers(for product: Product, region: Region) async -> [Offer] {
        var offers: [Offer] = []
        if let gtin = product.gtin {
            if case .success(let r) = await capture({ try await upc.lookup(gtin: gtin) }) { offers += r.offers }
        } else if product.source != .demo {
            // Found by name: re-run the search and keep only the same product.
            let query = product.searchQuery
            if case .success(let found) = await capture({ try await upc.search(query) }),
               let match = Self.bestTitleMatch(for: product, in: found) {
                offers += match.offers
            }
        }
        if let backend, case .success(let live) = await capture({ try await backend.offers(query: product.searchQuery, gtin: product.gtin, region: region) }) {
            offers += live
        }
        return Self.dedupe(offers)
    }

    /// The search result that is clearly the same product, if any.
    static func bestTitleMatch(for product: Product, in results: [ProductLookupResult]) -> ProductLookupResult? {
        let target = titleTokens(product.title)
        guard !target.isEmpty else { return nil }
        let scored = results.map { result -> (ProductLookupResult, Double) in
            let tokens = titleTokens(result.product.title)
            let overlap = Double(target.intersection(tokens).count) / Double(target.union(tokens).count)
            return (result, overlap)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 else { return nil }
        return best.0
    }

    static func titleTokens(_ title: String) -> Set<String> {
        Set(title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 })
    }

    /// One offer per merchant + condition, keeping the cheapest, freshest one.
    public static func dedupe(_ offers: [Offer]) -> [Offer] {
        var best: [String: Offer] = [:]
        for offer in offers {
            let key = (offer.merchantDomain ?? offer.merchant.lowercased()) + "|" + offer.condition.rawValue + "|" + offer.channel.rawValue + "|" + (offer.location ?? "")
            if let existing = best[key] {
                let cheaper = offer.totalPrice < existing.totalPrice - 0.004
                let samePriceNewer = abs(offer.totalPrice - existing.totalPrice) <= 0.004 && (offer.updatedAt ?? .distantPast) > (existing.updatedAt ?? .distantPast)
                if cheaper || samePriceNewer { best[key] = offer }
            } else {
                best[key] = offer
            }
        }
        return best.values.sorted { $0.totalPrice < $1.totalPrice }
    }

    private func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Swift.Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
