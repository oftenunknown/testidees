import Foundation

/// Built-in knowledge of discount schemes. Percentages are typical values for
/// ranking only; the app always labels them as estimates and confirms the real
/// saving at checkout.
public struct DiscountCatalog: Sendable {
    public var programs: [DiscountProgram]
    public var merchantDiscounts: [MerchantDiscount]

    public init(programs: [DiscountProgram], merchantDiscounts: [MerchantDiscount]) {
        self.programs = programs
        self.merchantDiscounts = merchantDiscounts
    }

    public func program(_ id: String?) -> DiscountProgram? {
        guard let id else { return nil }
        return programs.first { $0.id == id }
    }

    public func programs(for eligibility: Eligibility, in region: Region) -> [DiscountProgram] {
        programs.filter { $0.eligibility.contains(eligibility) && $0.regions.contains(region) }
    }

    public func discounts(atDomain domain: String) -> [MerchantDiscount] {
        let d = Offer.normalizedDomain(domain)
        return merchantDiscounts.filter { d == $0.merchantDomain || d.hasSuffix("." + $0.merchantDomain) || $0.merchantDomain.hasPrefix(Self.brandStem(d) + ".") }
    }

    /// "apple.co.uk" and "apple.com" share the stem "apple".
    static func brandStem(_ domain: String) -> String {
        domain.split(separator: ".").first.map(String.init) ?? domain
    }

    private static func url(_ s: String) -> URL { URL(string: s)! }

    private static func search(_ site: String) -> String {
        "https://duckduckgo.com/?q=site%3A\(site)+{q}"
    }

    public static let standard = DiscountCatalog(
        programs: [
            DiscountProgram(id: "unidays", name: "UNiDAYS", eligibility: [.student, .youth], regions: [.uk, .us, .eu, .other],
                            homepage: url("https://www.myunidays.com"), codeLookupTemplate: search("myunidays.com"),
                            blurb: "Free student verification. Generates single-use codes for hundreds of brands."),
            DiscountProgram(id: "studentbeans", name: "Student Beans", eligibility: [.student], regions: [.uk, .us, .eu],
                            homepage: url("https://www.studentbeans.com"), codeLookupTemplate: search("studentbeans.com"),
                            blurb: "Student discount codes, verified with your student email."),
            DiscountProgram(id: "totum", name: "TOTUM", eligibility: [.student], regions: [.uk],
                            homepage: url("https://www.totum.com"), codeLookupTemplate: search("totum.com"),
                            blurb: "UK student discount card with in-store and online offers."),
            DiscountProgram(id: "idme", name: "ID.me Shop", eligibility: [.military, .teacher, .healthcare, .blueLight, .student, .senior], regions: [.us],
                            homepage: url("https://shop.id.me"), codeLookupTemplate: search("shop.id.me"),
                            blurb: "One verified ID for military, teacher, nurse, first-responder and student offers."),
            DiscountProgram(id: "sheerid", name: "SheerID", eligibility: [.student, .military, .teacher, .healthcare, .blueLight], regions: [.us, .uk, .eu],
                            homepage: url("https://www.sheerid.com/shoppers/"),
                            blurb: "Verification many brands use directly on their own checkout."),
            DiscountProgram(id: "bluelightcard", name: "Blue Light Card", eligibility: [.nhs, .blueLight, .military, .keyWorker], regions: [.uk],
                            homepage: url("https://www.bluelightcard.co.uk"), codeLookupTemplate: search("bluelightcard.co.uk"),
                            blurb: "Discounts for NHS, emergency services, social care and armed forces."),
            DiscountProgram(id: "hsd", name: "Health Service Discounts", eligibility: [.nhs], regions: [.uk],
                            homepage: url("https://www.healthservicediscounts.com"), codeLookupTemplate: search("healthservicediscounts.com"),
                            blurb: "Free discount scheme for NHS and healthcare staff."),
            DiscountProgram(id: "dds", name: "Defence Discount Service", eligibility: [.military], regions: [.uk],
                            homepage: url("https://www.defencediscountservice.co.uk"), codeLookupTemplate: search("defencediscountservice.co.uk"),
                            blurb: "Official MOD-endorsed discounts for serving personnel and veterans."),
            DiscountProgram(id: "aarp", name: "AARP Member Advantages", eligibility: [.senior], regions: [.us],
                            homepage: url("https://www.aarp.org/benefits-discounts/"),
                            blurb: "Member discounts for people 50 and over."),
        ],
        merchantDiscounts: [
            MerchantDiscount(merchantDomain: "apple.com", merchantName: "Apple", eligibility: .student, mechanism: .dedicatedStore, typicalFraction: 0.08,
                             note: "Education pricing on Mac and iPad."),
            MerchantDiscount(merchantDomain: "apple.com", merchantName: "Apple", eligibility: .teacher, mechanism: .dedicatedStore, typicalFraction: 0.08,
                             note: "Education pricing for teachers and staff."),
            MerchantDiscount(merchantDomain: "microsoft.com", merchantName: "Microsoft", eligibility: .student, mechanism: .dedicatedStore, typicalFraction: 0.10,
                             note: "Education store pricing on Surface and accessories."),
            MerchantDiscount(merchantDomain: "samsung.com", merchantName: "Samsung", eligibility: .student, mechanism: .dedicatedStore, typicalFraction: 0.10,
                             note: "Education Offers Programme."),
            MerchantDiscount(merchantDomain: "samsung.com", merchantName: "Samsung", eligibility: .nhs, mechanism: .dedicatedStore,
                             note: "Samsung's offers programme includes NHS staff in the UK."),
            MerchantDiscount(merchantDomain: "nike.com", merchantName: "Nike", eligibility: .student, programID: "sheerid", mechanism: .code, typicalFraction: 0.10),
            MerchantDiscount(merchantDomain: "nike.com", merchantName: "Nike", eligibility: .military, programID: "sheerid", mechanism: .code, typicalFraction: 0.10),
            MerchantDiscount(merchantDomain: "nike.com", merchantName: "Nike", eligibility: .teacher, programID: "sheerid", mechanism: .code, typicalFraction: 0.10),
            MerchantDiscount(merchantDomain: "nike.com", merchantName: "Nike", eligibility: .healthcare, programID: "sheerid", mechanism: .code, typicalFraction: 0.10),
            MerchantDiscount(merchantDomain: "asos.com", merchantName: "ASOS", eligibility: .student, programID: "unidays", mechanism: .code, typicalFraction: 0.10),
            MerchantDiscount(merchantDomain: "lenovo.com", merchantName: "Lenovo", eligibility: .student, mechanism: .dedicatedStore,
                             note: "Education store for students and staff."),
            MerchantDiscount(merchantDomain: "dell.com", merchantName: "Dell", eligibility: .student, mechanism: .dedicatedStore,
                             note: "Student pricing on selected laptops."),
        ]
    )
}

/// A discount that could apply to a particular offer for this shopper.
public struct DiscountSuggestion: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var eligibility: Eligibility?
    public var program: DiscountProgram?
    public var savedCode: SavedCode?
    public var estimatedFraction: Double?
    public var mechanism: MerchantDiscount.Mechanism
    public var url: URL?
    public var isEstimate: Bool
    /// Only a pointer to search a program for codes, not a known discount.
    public var isLookupHint: Bool = false

    public func estimatedSaving(on price: Double) -> Double {
        guard let estimatedFraction else { return 0 }
        return (price * estimatedFraction * 100).rounded() / 100
    }
}

public enum DiscountMatcher {
    /// Typical welcome-offer value used to rank new-customer opportunities.
    public static let typicalWelcomeFraction = 0.10

    public static func suggestions(
        for offer: Offer,
        eligibilities: Set<Eligibility>,
        region: Region,
        savedCodes: [SavedCode],
        knownMerchants: Set<String> = [],
        catalog: DiscountCatalog = .standard,
        now: Date = .now
    ) -> [DiscountSuggestion] {
        guard let domain = offer.merchantDomain else { return [] }
        var results: [DiscountSuggestion] = []

        // 1. Codes the user already has for this shop — the fastest win.
        for code in savedCodes where code.isUsable(at: now) {
            guard let codeDomain = code.merchantDomain, codeDomain == domain || domain.hasSuffix("." + codeDomain) else { continue }
            results.append(DiscountSuggestion(
                id: "code-\(code.id)",
                title: "Your code \(code.code)",
                eligibility: code.eligibility,
                program: nil,
                savedCode: code,
                estimatedFraction: code.lastSaving.flatMap { offer.price > 0 ? $0 / offer.price : nil },
                mechanism: .code,
                url: nil,
                isEstimate: code.lastSaving == nil
            ))
        }

        // 2. Merchant-specific schemes the user qualifies for.
        for discount in catalog.discounts(atDomain: domain) where eligibilities.contains(discount.eligibility) {
            let program = catalog.program(discount.programID)
            results.append(DiscountSuggestion(
                id: discount.id,
                title: "\(discount.eligibility.title) discount" + (program.map { " via \($0.name)" } ?? ""),
                eligibility: discount.eligibility,
                program: program,
                savedCode: nil,
                estimatedFraction: discount.typicalFraction,
                mechanism: discount.mechanism,
                url: discount.url ?? program?.lookupURL(for: discount.merchantName),
                isEstimate: true
            ))
        }

        // 3. Welcome offers for shops the user hasn't bought from.
        if eligibilities.contains(.newCustomer), !knownMerchants.contains(domain) {
            results.append(DiscountSuggestion(
                id: "welcome-\(domain)",
                title: "New-customer welcome offer",
                eligibility: .newCustomer,
                program: nil,
                savedCode: nil,
                estimatedFraction: typicalWelcomeFraction,
                mechanism: .code,
                url: nil,
                isEstimate: true
            ))
        }

        // 4. Programs that cover the user's groups in this region, for a code search.
        let covered = Set(results.compactMap(\.eligibility))
        for eligibility in eligibilities.subtracting(covered).subtracting([.newCustomer]).sorted(by: { $0.rawValue < $1.rawValue }) {
            for program in catalog.programs(for: eligibility, in: region) where program.codeLookupTemplate != nil {
                results.append(DiscountSuggestion(
                    id: "search-\(program.id)-\(domain)",
                    title: "Check \(program.name) for \(offer.merchant)",
                    eligibility: eligibility,
                    program: program,
                    savedCode: nil,
                    estimatedFraction: nil,
                    mechanism: .code,
                    url: program.lookupURL(for: offer.merchant),
                    isEstimate: true,
                    isLookupHint: true
                ))
            }
        }

        return results.sorted { ($0.estimatedFraction ?? 0) > ($1.estimatedFraction ?? 0) }
    }
}
