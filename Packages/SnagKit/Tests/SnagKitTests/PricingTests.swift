import Foundation
import Testing
@testable import SnagKit

@Suite("GTIN")
struct GTINTests {
    @Test func validatesCheckDigits() {
        #expect(GTIN.isValid("885909950805"))      // UPC-A
        #expect(GTIN.isValid("3017620422003"))     // EAN-13
        #expect(GTIN.isValid("96385074"))          // EAN-8
        #expect(!GTIN.isValid("885909950806"))
    }

    @Test func normalizesAndStripsJunk() {
        #expect(GTIN.normalize(" 8 85909-950805 ") == "885909950805")
        #expect(GTIN.normalize("12345") == nil)
        #expect(GTIN.normalize("") == nil)
    }

    @Test func expandsUPCE() {
        // Classic examples: 01234565 (UPC-E) -> 012345000065
        #expect(GTIN.expandUPCE("01234565") == "012345000065")
        #expect(GTIN.normalize("01234565", isUPCE: true) == "012345000065")
        #expect(GTIN.expandUPCE("0654321") != nil)
    }

    @Test func matchesAcrossLengths() {
        #expect(GTIN.sameItem("885909950805", "0885909950805"))
        #expect(!GTIN.sameItem("885909950805", "3017620422003"))
    }

    @Test func detectsBooks() {
        #expect(GTIN.isBook("9780306406157"))
        #expect(!GTIN.isBook("3017620422003"))
    }
}

@Suite("Price verdict")
struct PriceAnalyzerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func offers(_ prices: [Double], currency: String = "USD") -> [Offer] {
        prices.enumerated().map { Offer(id: "\($0.offset)", merchant: "Shop \($0.offset)", merchantDomain: "shop\($0.offset).com", price: $0.element, shipping: 0, currency: currency, updatedAt: now, source: "test") }
    }

    @Test func greatWhenMatchingBestOnline() {
        let v = PriceAnalyzer.verdict(userPrice: 100, currency: "USD", offers: offers([99, 110, 120, 125]), now: now)
        #expect(v.level == .great)
        #expect(v.bestOffer?.price == 99)
        #expect(abs(v.potentialSaving - 1) < 0.001)
    }

    @Test func highWhenWellAboveMarket() {
        let v = PriceAnalyzer.verdict(userPrice: 160, currency: "USD", offers: offers([99, 110, 120, 125]), now: now)
        #expect(v.level == .high)
        #expect(v.potentialSaving > 60)
        #expect(v.position > 0.9)
    }

    @Test func fairAroundMedian() {
        let v = PriceAnalyzer.verdict(userPrice: 118, currency: "USD", offers: offers([99, 110, 120, 125]), now: now)
        #expect(v.level == .fair)
    }

    @Test func stealBelowEverything() {
        let history = [PricePoint(date: now, price: 105), PricePoint(date: now, price: 101)]
        let v = PriceAnalyzer.verdict(userPrice: 89, currency: "USD", offers: offers([99, 110, 120]), history: history, now: now)
        #expect(v.level == .steal)
        #expect(v.level.isBuySignal)
    }

    @Test func ignoresAccessoriesAndOtherCurrencies() {
        var list = offers([499, 510, 529, 540, 12]) // the $12 "offer" is a phone case
        list.append(Offer(merchant: "UK shop", price: 300, currency: "GBP", source: "test"))
        let comparable = PriceAnalyzer.comparableOffers(list, currency: "USD")
        #expect(comparable.count == 4)
        #expect(!comparable.contains { $0.price == 12 })
    }

    @Test func unknownWithNoData() {
        let v = PriceAnalyzer.verdict(userPrice: 10, currency: "USD", offers: [], now: now)
        #expect(v.level == .unknown)
        #expect(v.confidence == 0)
    }

    @Test func staleOffersLowerConfidence() {
        let fresh = PriceAnalyzer.verdict(userPrice: 10, currency: "USD", offers: offers([10, 11, 12, 13]), now: now)
        let old = offers([10, 11, 12, 13]).map { var o = $0; o.updatedAt = now.addingTimeInterval(-200 * 86_400); return o }
        let stale = PriceAnalyzer.verdict(userPrice: 10, currency: "USD", offers: old, now: now)
        #expect(stale.confidence < fresh.confidence)
    }
}

@Suite("Price alerts")
struct AlertTests {
    @Test func targetPrice() {
        let rule = PriceAlertRule(trigger: .targetPrice(80), baselinePrice: 100, currency: "USD")
        #expect(AlertEvaluator.evaluate(rule, currentBest: 85, history: []) == .none)
        if case .fire(let price, let drop, let reason) = AlertEvaluator.evaluate(rule, currentBest: 79, history: []) {
            #expect(price == 79)
            #expect(abs(drop - 0.21) < 0.0001)
            #expect(reason == .reachedTarget)
        } else {
            Issue.record("expected alert to fire")
        }
    }

    @Test func percentDrop() {
        let rule = PriceAlertRule(trigger: .percentDrop(0.15), baselinePrice: 200, currency: "USD")
        #expect(AlertEvaluator.evaluate(rule, currentBest: 175, history: []) == .none)
        #expect(AlertEvaluator.evaluate(rule, currentBest: 169, history: []) != .none)
    }

    @Test func doesNotRepeatAtSamePrice() {
        var rule = PriceAlertRule(trigger: .anyDrop, baselinePrice: 50, currency: "USD")
        #expect(AlertEvaluator.evaluate(rule, currentBest: 45, history: []) != .none)
        rule.lastNotifiedPrice = 45
        #expect(AlertEvaluator.evaluate(rule, currentBest: 45, history: []) == .none)
        #expect(AlertEvaluator.evaluate(rule, currentBest: 44.9, history: []) == .none)
        #expect(AlertEvaluator.evaluate(rule, currentBest: 42, history: []) != .none)
    }

    @Test func allTimeLow() {
        let rule = PriceAlertRule(trigger: .allTimeLow, baselinePrice: 50, currency: "USD")
        let history = [PricePoint(date: .now, price: 48), PricePoint(date: .now, price: 46)]
        #expect(AlertEvaluator.evaluate(rule, currentBest: 47, history: history) == .none)
        #expect(AlertEvaluator.evaluate(rule, currentBest: 44, history: history) != .none)
    }

    @Test func disabledNeverFires() {
        let rule = PriceAlertRule(trigger: .anyDrop, baselinePrice: 50, currency: "USD", isEnabled: false)
        #expect(AlertEvaluator.evaluate(rule, currentBest: 10, history: []) == .none)
    }

    @Test func smartDefaultIsTenPercent() {
        let rule = PriceAlertRule.smartDefault(currentBest: 200, currency: "GBP")
        #expect(rule.thresholdPrice == 180)
    }
}

@Suite("Price history")
struct HistoryTests {
    @Test func skipsDuplicatePoints() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var h: [PricePoint] = []
        h = PriceHistory.appending(PricePoint(date: t0, price: 10), to: h)
        h = PriceHistory.appending(PricePoint(date: t0.addingTimeInterval(3600), price: 10), to: h)
        h = PriceHistory.appending(PricePoint(date: t0.addingTimeInterval(7200), price: 9), to: h)
        #expect(h.count == 2)
    }

    @Test func detectsFallingTrendAndAdvice() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let points = (0..<8).map { PricePoint(date: t0.addingTimeInterval(Double($0) * 7 * 86_400), price: 100 - Double($0) * 4) }
        let summary = PriceHistory.summary(points, window: 90, now: t0.addingTimeInterval(60 * 86_400))
        #expect(summary.trend == .falling)
        #expect(summary.lowest == 72)
        #expect(summary.advice == .buyNow)
    }
}

@Suite("Shelf tag OCR")
struct PriceTagTests {
    @Test func picksNowPriceOverWas() {
        let text = "Bose QC Headphones\nWas $349.00\nNow $279.99"
        #expect(PriceTagParser.bestPrice(in: text, defaultCurrency: "USD")?.amount == 279.99)
    }

    @Test func ignoresUnitPrices() {
        let text = "Nutella 400g\n£3.50\n£8.75/kg"
        let best = PriceTagParser.bestPrice(in: text, defaultCurrency: "GBP")
        #expect(best?.amount == 3.5)
        #expect(best?.currency == "GBP")
    }

    @Test func handlesPenceAndEuroComma() {
        #expect(PriceTagParser.bestPrice(in: "Banana 99p", defaultCurrency: "GBP")?.amount == 0.99)
        #expect(PriceTagParser.bestPrice(in: "€ 3,49", defaultCurrency: "EUR")?.amount == 3.49)
    }

    @Test func thousandsSeparator() {
        #expect(PriceTagParser.bestPrice(in: "MacBook Pro $1,999.00", defaultCurrency: "USD")?.amount == 1999)
    }

    @Test func ignoresBareNumbers() {
        #expect(PriceTagParser.bestPrice(in: "Aisle 12 Pack of 6", defaultCurrency: "USD") == nil)
    }
}
