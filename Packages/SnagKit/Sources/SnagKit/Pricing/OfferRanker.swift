import Foundation

/// An offer with the shopper's best applicable discount folded in.
public struct RankedOffer: Hashable, Sendable, Identifiable {
    public var offer: Offer
    public var bestDiscount: DiscountSuggestion?
    public var allDiscounts: [DiscountSuggestion]
    public var effectivePrice: Double
    public var isBest: Bool

    public var id: String { offer.id }
    public var estimatedSaving: Double { offer.totalPrice - effectivePrice }
}

public enum OfferRanker {
    public struct Options: Sendable {
        public var eligibilities: Set<Eligibility>
        public var region: Region
        public var savedCodes: [SavedCode]
        public var knownMerchants: Set<String>
        public var includeUsed: Bool
        /// Only show offers with a discount the shopper qualifies for.
        public var onlyWithDiscounts: Bool
        /// Restrict to offers that apply a discount from one of these groups.
        public var eligibilityFilter: Set<Eligibility>

        public init(
            eligibilities: Set<Eligibility> = [],
            region: Region = .us,
            savedCodes: [SavedCode] = [],
            knownMerchants: Set<String> = [],
            includeUsed: Bool = false,
            onlyWithDiscounts: Bool = false,
            eligibilityFilter: Set<Eligibility> = []
        ) {
            self.eligibilities = eligibilities
            self.region = region
            self.savedCodes = savedCodes
            self.knownMerchants = knownMerchants
            self.includeUsed = includeUsed
            self.onlyWithDiscounts = onlyWithDiscounts
            self.eligibilityFilter = eligibilityFilter
        }
    }

    public static func rank(_ offers: [Offer], currency: String, options: Options, catalog: DiscountCatalog = .standard) -> [RankedOffer] {
        let candidates = PriceAnalyzer.comparableOffers(offers.filter { $0.channel == .online }, currency: currency, includeUsed: options.includeUsed)

        var ranked: [RankedOffer] = candidates.map { offer in
            let discounts = DiscountMatcher.suggestions(
                for: offer,
                eligibilities: options.eligibilities,
                region: options.region,
                savedCodes: options.savedCodes,
                knownMerchants: options.knownMerchants,
                catalog: catalog
            )
            let best = discounts.max { $0.estimatedSaving(on: offer.price) < $1.estimatedSaving(on: offer.price) }
            let saving = best?.estimatedSaving(on: offer.price) ?? 0
            return RankedOffer(offer: offer, bestDiscount: saving > 0 ? best : nil, allDiscounts: discounts, effectivePrice: offer.totalPrice - saving, isBest: false)
        }

        if options.onlyWithDiscounts {
            ranked = ranked.filter { $0.bestDiscount != nil }
        }
        if !options.eligibilityFilter.isEmpty {
            ranked = ranked.filter { r in
                r.allDiscounts.contains { !$0.isLookupHint && ($0.eligibility.map(options.eligibilityFilter.contains) ?? false) }
            }
        }

        ranked.sort {
            if abs($0.effectivePrice - $1.effectivePrice) > 0.004 { return $0.effectivePrice < $1.effectivePrice }
            // Prefer offers we know are in stock and recently updated.
            let a = ($0.offer.inStock ?? true ? 0 : 1, -($0.offer.updatedAt?.timeIntervalSince1970 ?? 0))
            let b = ($1.offer.inStock ?? true ? 0 : 1, -($1.offer.updatedAt?.timeIntervalSince1970 ?? 0))
            return a < b
        }
        if !ranked.isEmpty { ranked[0].isBest = true }
        return ranked
    }
}
