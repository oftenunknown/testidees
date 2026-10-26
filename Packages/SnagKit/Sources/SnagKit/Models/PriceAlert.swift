import Foundation

/// What the user wants to be told about.
public struct PriceAlertRule: Codable, Hashable, Sendable {
    public enum Trigger: Codable, Hashable, Sendable {
        /// Fire when the best price is at or below this amount.
        case targetPrice(Double)
        /// Fire when the best price is this fraction (0.15 = 15%) below the baseline.
        case percentDrop(Double)
        /// Fire on any meaningful drop below the baseline.
        case anyDrop
        /// Fire when the price beats everything we've recorded.
        case allTimeLow
    }

    public var trigger: Trigger
    /// Best price when the alert was created; drops are measured from here.
    public var baselinePrice: Double
    public var currency: String
    public var isEnabled: Bool
    /// Price at the last notification, so we only re-alert on a further drop.
    public var lastNotifiedPrice: Double?
    public var lastNotifiedAt: Date?

    public init(
        trigger: Trigger,
        baselinePrice: Double,
        currency: String,
        isEnabled: Bool = true,
        lastNotifiedPrice: Double? = nil,
        lastNotifiedAt: Date? = nil
    ) {
        self.trigger = trigger
        self.baselinePrice = baselinePrice
        self.currency = currency
        self.isEnabled = isEnabled
        self.lastNotifiedPrice = lastNotifiedPrice
        self.lastNotifiedAt = lastNotifiedAt
    }

    /// The price at which this rule fires, when it has a fixed one.
    public var thresholdPrice: Double? {
        switch trigger {
        case .targetPrice(let p): p
        case .percentDrop(let f): baselinePrice * (1 - f)
        case .anyDrop: baselinePrice * (1 - AlertEvaluator.minimumMeaningfulDrop)
        case .allTimeLow: nil
        }
    }

    /// Sensible default when someone taps "Watch" with no further input:
    /// tell me when it's 10% cheaper than now.
    public static func smartDefault(currentBest: Double, currency: String) -> PriceAlertRule {
        PriceAlertRule(trigger: .percentDrop(0.10), baselinePrice: currentBest, currency: currency)
    }
}

public enum AlertDecision: Equatable, Sendable {
    case none
    case fire(price: Double, dropFraction: Double, reason: Reason)

    public enum Reason: String, Sendable {
        case reachedTarget, droppedByPercent, dropped, allTimeLow
    }
}

public enum AlertEvaluator {
    /// Ignore wobbles smaller than this when deciding a price "dropped".
    public static let minimumMeaningfulDrop = 0.02
    /// After notifying, only notify again if the price falls this much further.
    public static let renotifyStep = 0.01

    public static func evaluate(
        _ rule: PriceAlertRule,
        currentBest: Double,
        history: [PricePoint]
    ) -> AlertDecision {
        guard rule.isEnabled, currentBest > 0, rule.baselinePrice > 0 else { return .none }

        if let last = rule.lastNotifiedPrice, currentBest > last * (1 - renotifyStep) {
            return .none
        }

        let drop = (rule.baselinePrice - currentBest) / rule.baselinePrice

        switch rule.trigger {
        case .targetPrice(let target):
            return currentBest <= target ? .fire(price: currentBest, dropFraction: drop, reason: .reachedTarget) : .none
        case .percentDrop(let fraction):
            return drop >= fraction ? .fire(price: currentBest, dropFraction: drop, reason: .droppedByPercent) : .none
        case .anyDrop:
            return drop >= minimumMeaningfulDrop ? .fire(price: currentBest, dropFraction: drop, reason: .dropped) : .none
        case .allTimeLow:
            let previousLow = history.map(\.price).min() ?? rule.baselinePrice
            return currentBest < previousLow * (1 - renotifyStep / 2)
                ? .fire(price: currentBest, dropFraction: drop, reason: .allTimeLow)
                : .none
        }
    }
}
