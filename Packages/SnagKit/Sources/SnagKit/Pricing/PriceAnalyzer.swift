import Foundation

/// The answer to "is this a good price?" for a price someone sees in a shop.
public struct PriceVerdict: Hashable, Sendable {
    public enum Level: String, Sendable, CaseIterable, Comparable {
        /// At or below anything we've ever seen.
        case steal
        /// Matches the best price available online right now.
        case great
        /// Cheaper than most places.
        case good
        /// About what everyone charges.
        case fair
        /// Noticeably more than elsewhere.
        case high
        /// Not enough data to judge.
        case unknown

        private var rank: Int {
            switch self {
            case .steal: 0
            case .great: 1
            case .good: 2
            case .fair: 3
            case .high: 4
            case .unknown: 5
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rank < rhs.rank }

        /// Whether buying at this price is a reasonable call.
        public var isBuySignal: Bool { self <= .good }
    }

    public var level: Level
    public var userPrice: Double
    public var currency: String
    public var bestOffer: Offer?
    public var medianPrice: Double?
    public var lowestEver: Double?
    public var highestSeen: Double?
    /// How much cheaper the best alternative is (positive = you could save).
    public var potentialSaving: Double
    /// 0 = cheapest end of the observed range, 1 = most expensive end. For gauges.
    public var position: Double
    /// 0–1 trust in the verdict, from how many fresh data points we had.
    public var confidence: Double
    public var comparableCount: Int

    public var bestPrice: Double? { bestOffer?.totalPrice }

    public var savingFraction: Double {
        guard userPrice > 0 else { return 0 }
        return max(0, potentialSaving) / userPrice
    }
}

public enum PriceAnalyzer {
    /// Offers older than this count for less when judging confidence.
    public static let staleAfterDays = 30.0

    /// Judges `userPrice` against current offers and recorded history.
    /// Offers in other currencies and obvious mismatches (accessories, bundles)
    /// are ignored.
    public static func verdict(
        userPrice: Double,
        currency: String,
        offers: [Offer],
        history: [PricePoint] = [],
        recordedLow: Double? = nil,
        includeUsed: Bool = false,
        now: Date = .now
    ) -> PriceVerdict {
        let comparable = comparableOffers(offers, currency: currency, includeUsed: includeUsed)
        let totals = comparable.map(\.totalPrice).sorted()

        guard !totals.isEmpty || !history.isEmpty else {
            return PriceVerdict(
                level: .unknown, userPrice: userPrice, currency: currency, bestOffer: nil,
                medianPrice: nil, lowestEver: nil, highestSeen: nil, potentialSaving: 0,
                position: 0.5, confidence: 0, comparableCount: 0
            )
        }

        let online = comparable.filter { $0.channel == .online }
        let best = (online.isEmpty ? comparable : online).min { $0.totalPrice < $1.totalPrice }
        let median = totals.isEmpty ? nil : Stats.median(totals)
        let historyPrices = history.map(\.price)
        var everything = totals + historyPrices
        // Data sources' all-time lows are often junk (e.g. a used listing); only
        // trust them when they're within reason of today's prices.
        if let recordedLow, let median, recordedLow >= median * 0.5 { everything.append(recordedLow) }
        let lowestEver = everything.min()
        let highestSeen = everything.max()

        let bestPrice = best?.totalPrice
        let reference = median ?? Stats.median(historyPrices.sorted())

        let level: PriceVerdict.Level
        if let lowestEver, userPrice <= lowestEver * 1.005, everything.count >= 3 {
            level = .steal
        } else if let bestPrice, userPrice <= bestPrice * 1.03 {
            level = .great
        } else if userPrice <= reference * 0.97 {
            level = .good
        } else if userPrice <= max(reference * 1.10, Stats.percentile(totals.isEmpty ? historyPrices.sorted() : totals, 0.75)) {
            level = .fair
        } else {
            level = .high
        }

        let low = min(lowestEver ?? userPrice, userPrice)
        let high = max(highestSeen ?? userPrice, userPrice)
        let position = high > low ? (userPrice - low) / (high - low) : 0.5

        return PriceVerdict(
            level: level,
            userPrice: userPrice,
            currency: currency,
            bestOffer: best,
            medianPrice: median,
            lowestEver: lowestEver,
            highestSeen: highestSeen,
            potentialSaving: bestPrice.map { userPrice - $0 } ?? 0,
            position: min(1, max(0, position)),
            confidence: confidence(offers: comparable, historyCount: history.count, now: now),
            comparableCount: comparable.count
        )
    }

    /// Same currency, condition filter, and outlier rejection around the median
    /// so a $5 case doesn't make a $500 phone look overpriced.
    public static func comparableOffers(_ offers: [Offer], currency: String, includeUsed: Bool = false) -> [Offer] {
        let sameCurrency = offers.filter {
            $0.price > 0
                && ($0.currency.uppercased() == currency.uppercased() || $0.currency.isEmpty)
                && (includeUsed || $0.condition == .new || $0.condition == .unknown)
        }
        guard sameCurrency.count >= 3 else { return sameCurrency }
        let median = Stats.median(sameCurrency.map(\.totalPrice).sorted())
        return sameCurrency.filter { $0.totalPrice >= median * 0.35 && $0.totalPrice <= median * 3 }
    }

    static func confidence(offers: [Offer], historyCount: Int, now: Date) -> Double {
        let fresh = offers.filter { ($0.ageInDays(now: now) ?? 0) <= staleAfterDays }.count
        let stale = offers.count - fresh
        let score = Double(fresh) * 0.18 + Double(stale) * 0.06 + Double(min(historyCount, 10)) * 0.04
        return min(1, score)
    }
}

enum Stats {
    /// Median of an already-sorted array.
    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Linear-interpolated percentile of an already-sorted array.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let rank = p * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }
}
