import Foundation

/// Summary statistics over a product's recorded best prices.
public struct PriceHistorySummary: Hashable, Sendable {
    public var current: Double?
    public var lowest: Double?
    public var highest: Double?
    public var average: Double?
    public var lowestDate: Date?
    public var trend: Trend
    /// How the current price compares with the window's range (0 = at the low).
    public var positionInRange: Double?

    public enum Trend: String, Sendable {
        case falling, rising, steady, unknown
    }

    /// Plain-language buying advice derived from where today's price sits.
    public var advice: Advice {
        guard let positionInRange else { return .notEnoughData }
        if positionInRange <= 0.1 { return .buyNow }
        if trend == .falling { return .wait }
        if positionInRange >= 0.6 { return .wait }
        return .reasonable
    }

    public enum Advice: String, Sendable {
        case buyNow, reasonable, wait, notEnoughData
    }
}

public enum PriceHistory {
    /// Appends a point unless it repeats the previous price within `minimumGap`.
    /// Keeps charts readable when background checks run often.
    public static func appending(
        _ point: PricePoint,
        to history: [PricePoint],
        minimumGap: TimeInterval = 6 * 3600,
        limit: Int = 500
    ) -> [PricePoint] {
        var result = history.sorted { $0.date < $1.date }
        if let last = result.last,
           abs(last.price - point.price) < 0.005,
           point.date.timeIntervalSince(last.date) < minimumGap {
            return result
        }
        result.append(point)
        if result.count > limit { result.removeFirst(result.count - limit) }
        return result
    }

    public static func summary(_ history: [PricePoint], window days: Int = 90, now: Date = .now) -> PriceHistorySummary {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let points = history.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        guard let current = points.last?.price else {
            return PriceHistorySummary(current: nil, lowest: nil, highest: nil, average: nil, lowestDate: nil, trend: .unknown, positionInRange: nil)
        }
        let prices = points.map(\.price)
        let lowestPoint = points.min { $0.price < $1.price }
        let lowest = lowestPoint?.price ?? current
        let highest = prices.max() ?? current
        let average = prices.reduce(0, +) / Double(prices.count)
        let position: Double? = points.count >= 2 ? (highest > lowest ? (current - lowest) / (highest - lowest) : 0.5) : nil

        return PriceHistorySummary(
            current: current,
            lowest: lowest,
            highest: highest,
            average: average,
            lowestDate: lowestPoint?.date,
            trend: trend(points),
            positionInRange: position
        )
    }

    /// Least-squares slope over the window, expressed as a fraction of the mean per week.
    static func trend(_ points: [PricePoint]) -> PriceHistorySummary.Trend {
        guard points.count >= 3, let first = points.first?.date else { return .unknown }
        let xs = points.map { $0.date.timeIntervalSince(first) / (7 * 86_400) }
        let ys = points.map(\.price)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        guard den > 0, meanY > 0 else { return .steady }
        let weeklyChange = (num / den) / meanY
        if weeklyChange < -0.01 { return .falling }
        if weeklyChange > 0.01 { return .rising }
        return .steady
    }
}
