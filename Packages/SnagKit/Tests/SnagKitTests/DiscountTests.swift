import Foundation
import Testing
@testable import SnagKit

@Suite("Discounts")
struct DiscountTests {
    let nike = Offer(id: "n", merchant: "Nike", merchantDomain: "https://www.nike.com/t/shoe", price: 120, shipping: 0, currency: "USD", source: "test")
    let other = Offer(id: "o", merchant: "Shoe Shop", merchantDomain: "shoeshop.com", price: 115, shipping: 0, currency: "USD", source: "test")

    @Test func normalizesDomains() {
        #expect(nike.merchantDomain == "nike.com")
        #expect(Offer.normalizedDomain("WWW.Apple.com/uk") == "apple.com")
    }

    @Test func studentDiscountAppliesAtNike() {
        let s = DiscountMatcher.suggestions(for: nike, eligibilities: [.student], region: .us, savedCodes: [])
        #expect(s.contains { $0.eligibility == .student && $0.estimatedFraction == 0.10 })
    }

    @Test func noSchemeDiscountWithoutEligibility() {
        let s = DiscountMatcher.suggestions(for: nike, eligibilities: [], region: .us, savedCodes: [])
        #expect(s.isEmpty)
    }

    @Test func savedCodeComesFirstWhenItSavesMost() {
        let code = SavedCode(code: "welcome20", merchantDomain: "nike.com", source: .manual, lastSaving: 24)
        let s = DiscountMatcher.suggestions(for: nike, eligibilities: [.student], region: .us, savedCodes: [code])
        #expect(s.first?.savedCode?.code == "WELCOME20")
    }

    @Test func expiredCodesAreSkipped() {
        let code = SavedCode(code: "OLD", merchantDomain: "nike.com", source: .manual, expiresAt: Date(timeIntervalSince1970: 0))
        let s = DiscountMatcher.suggestions(for: nike, eligibilities: [], region: .us, savedCodes: [code])
        #expect(s.isEmpty)
    }

    @Test func nhsProgramsOnlyInUK() {
        let uk = DiscountCatalog.standard.programs(for: .nhs, in: .uk).map(\.id)
        let us = DiscountCatalog.standard.programs(for: .nhs, in: .us)
        #expect(uk.contains("bluelightcard"))
        #expect(uk.contains("hsd"))
        #expect(us.isEmpty)
    }

    @Test func nhsWorkerGetsProgramSearchLinks() {
        let s = DiscountMatcher.suggestions(for: other, eligibilities: [.nhs], region: .uk, savedCodes: [])
        #expect(s.contains { $0.program?.id == "bluelightcard" && $0.url != nil })
    }

    @Test func welcomeOfferOnlyForNewMerchants() {
        let fresh = DiscountMatcher.suggestions(for: other, eligibilities: [.newCustomer], region: .us, savedCodes: [])
        let known = DiscountMatcher.suggestions(for: other, eligibilities: [.newCustomer], region: .us, savedCodes: [], knownMerchants: ["shoeshop.com"])
        #expect(fresh.count == 1)
        #expect(known.isEmpty)
    }

    @Test func rankingUsesEffectivePrice() {
        // Nike is $5 dearer, but a 10% student discount makes it cheaper.
        let ranked = OfferRanker.rank([nike, other], currency: "USD", options: .init(eligibilities: [.student], region: .us))
        #expect(ranked.first?.offer.merchant == "Nike")
        #expect(ranked.first?.isBest == true)
        #expect(abs((ranked.first?.effectivePrice ?? 0) - 108) < 0.01)
    }

    @Test func filterToEligibilityGroup() {
        let ranked = OfferRanker.rank([nike, other], currency: "USD", options: .init(eligibilities: [.student, .military], region: .us, eligibilityFilter: [.military]))
        #expect(ranked.map(\.offer.merchant) == ["Nike"])
    }
}
