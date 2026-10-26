import Foundation
import SwiftData
import SnagKit

/// Sample content for screenshots, UI tests and "Load sample data".
enum DemoData {
    struct SampleScan {
        var title: String
        var code: String
        var shelfPrice: Double
    }

    static func sampleScans(currency: String) -> [SampleScan] {
        currency == "GBP"
            ? [SampleScan(title: "Nutella 400g", code: "3017620422003", shelfPrice: 3.85),
               SampleScan(title: "iPhone case", code: "885909950805", shelfPrice: 49)]
            : [SampleScan(title: "Nutella 400g", code: "3017620422003", shelfPrice: 4.99),
               SampleScan(title: "Apple iPhone", code: "885909950805", shelfPrice: 129)]
    }

    static func seed(into context: ModelContext, model: AppModel) {
        let currency = model.settings.currency
        let now = Date.now
        func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }
        func offers(_ prices: [(String, String, Double)]) -> [Offer] {
            prices.map { Offer(merchant: $0.0, merchantDomain: $0.1, price: $0.2, shipping: 0, currency: currency,
                               url: URL(string: "https://\($0.1)"), updatedAt: days(0.2), source: "demo") }
        }

        let items: [(Product, [Offer], [Double], PriceAlertRule.Trigger)] = [
            (Product(id: "demo-headphones", title: "Wireless Noise Cancelling Headphones", brand: "Sony", category: "Electronics > Audio",
                     imageURLs: [], source: .demo),
             offers([("Amazon", "amazon.com", 279), ("Best Buy", "bestbuy.com", 299), ("Target", "target.com", 309)]),
             [349, 349, 329, 319, 329, 299, 289, 279], .percentDrop(0.15)),
            (Product(id: "demo-sneakers", title: "Air Max Running Shoes", brand: "Nike", category: "Apparel > Shoes",
                     imageURLs: [], source: .demo),
             offers([("Nike", "nike.com", 140), ("Foot Locker", "footlocker.com", 135), ("JD Sports", "jdsports.com", 129)]),
             [150, 150, 145, 145, 140, 135, 129], .targetPrice(120)),
            (Product(id: "demo-coffee", title: "Espresso Machine with Milk Frother", brand: "Breville", category: "Home > Kitchen",
                     imageURLs: [], source: .demo),
             offers([("Williams Sonoma", "williams-sonoma.com", 499), ("Amazon", "amazon.com", 529)]),
             [599, 579, 549, 549, 529, 499], .anyDrop),
            (Product(id: "demo-lego", title: "Botanical Collection Building Set", brand: "LEGO", category: "Toys",
                     imageURLs: [], source: .demo),
             offers([("LEGO", "lego.com", 59.99), ("Walmart", "walmart.com", 54.99)]),
             [59.99, 59.99, 57.99, 54.99], .allTimeLow),
        ]

        for (product, productOffers, prices, trigger) in items {
            let id = product.id
            if (try? context.fetch(FetchDescriptor<WishItem>(predicate: #Predicate { $0.productID == id })).first) != nil { continue }
            let item = WishItem(product: product, offers: productOffers, currency: currency)
            item.history = prices.enumerated().map { PricePoint(date: days(Double(prices.count - $0.offset) * 4), price: $0.element) }
            item.addedPrice = prices.first
            item.alert = PriceAlertRule(trigger: trigger, baselinePrice: prices.first ?? 0, currency: currency)
            context.insert(item)
        }

        if (try? context.fetchCount(FetchDescriptor<RecipientRecord>())) == 0 {
            let sam = RecipientProfile(
                name: "Sam", relationship: .bestFriend, ageBand: .thirties,
                interests: [WeightedInterest(.coffee, weight: 1), WeightedInterest(.hiking, weight: 0.8), WeightedInterest(.vinyl, weight: 0.6)],
                aesthetics: [.minimal, .natural], budgetMin: 30, budgetMax: 90, currency: currency, occasion: .birthday,
                occasionDate: Calendar.current.date(byAdding: .day, value: 12, to: now)
            )
            let record = RecipientRecord(profile: sam)
            record.ideas = GiftRecommender.recommend(for: sam, from: model.persona.completeness > 0 ? model.persona : samplePersona, count: 4)
            context.insert(record)
            context.insert(RecipientRecord(profile: RecipientProfile(
                name: "Mum", relationship: .parent, ageBand: .sixtyPlus,
                interests: [WeightedInterest(.gardening, weight: 1), WeightedInterest(.reading, weight: 0.7), WeightedInterest(.tea, weight: 0.6)],
                aesthetics: [.cozy], budgetMin: 40, budgetMax: 120, currency: currency, occasion: .mothersDay
            )))
        }

        if model.persona.completeness == 0 {
            model.persona = samplePersona
        }

        if (try? context.fetchCount(FetchDescriptor<ScanRecord>())) == 0 {
            let nutella = Product(gtin: "3017620422003", title: "Nutella · 400 g", brand: "Ferrero", source: .demo)
            context.insert(ScanRecord(product: nutella, code: nutella.gtin, userPrice: currency == "GBP" ? 3.85 : 4.99, bestPrice: currency == "GBP" ? 3.10 : 4.29, currency: currency, verdict: .fair))
        }
        try? context.save()
    }

    static var samplePersona: PersonaProfile {
        let quiz = PersonaQuiz.standard.evaluate([
            "saturday": ["outside"], "surprise": ["surprise"], "souvenir": ["memory"], "splurge": ["experience"],
            "love": ["time"], "aesthetic": ["natural", "minimal"], "passions": ["p-outdoors", "p-coffee", "p-music"],
        ])
        return PersonaProfile(
            displayName: "You", traits: quiz.traits, interests: quiz.interests, aesthetics: quiz.aesthetics,
            summary: "You give the kind of gifts that turn into stories — plans, places and things that get people outside.",
            signature: "Your gifts feel like an invitation.",
            sources: [.quiz]
        )
    }
}
