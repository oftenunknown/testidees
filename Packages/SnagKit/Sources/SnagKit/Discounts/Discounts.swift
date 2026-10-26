import Foundation

/// Groups a shopper can belong to that unlock discounts.
public enum Eligibility: String, Codable, CaseIterable, Sendable, Identifiable {
    case student
    case nhs
    case healthcare
    case blueLight
    case military
    case teacher
    case senior
    case youth
    case newCustomer
    case keyWorker

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .student: "Student"
        case .nhs: "NHS staff"
        case .healthcare: "Healthcare worker"
        case .blueLight: "Emergency services"
        case .military: "Military & veterans"
        case .teacher: "Teacher"
        case .senior: "Senior (60+)"
        case .youth: "Under 26"
        case .newCustomer: "New customer"
        case .keyWorker: "Key worker"
        }
    }

    public var symbol: String {
        switch self {
        case .student: "graduationcap.fill"
        case .nhs: "cross.case.fill"
        case .healthcare: "stethoscope"
        case .blueLight: "light.beacon.max.fill"
        case .military: "star.fill"
        case .teacher: "book.closed.fill"
        case .senior: "figure.walk"
        case .youth: "sparkles"
        case .newCustomer: "gift.fill"
        case .keyWorker: "wrench.and.screwdriver.fill"
        }
    }

    /// Groups that make sense in a region. New-customer offers apply everywhere.
    public static func relevant(in region: Region) -> [Eligibility] {
        switch region {
        case .uk: [.newCustomer, .student, .nhs, .blueLight, .military, .teacher, .youth, .senior, .keyWorker]
        case .us: [.newCustomer, .student, .military, .teacher, .healthcare, .blueLight, .senior]
        case .eu, .other: [.newCustomer, .student, .youth, .teacher, .senior]
        }
    }
}

/// A verification service or scheme that issues discount codes or links.
public struct DiscountProgram: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var eligibility: [Eligibility]
    public var regions: [Region]
    public var homepage: URL
    /// Page where a verified member generates a code for a given merchant, if
    /// the program has a predictable one.
    public var codeLookupTemplate: String?
    public var blurb: String

    public init(id: String, name: String, eligibility: [Eligibility], regions: [Region], homepage: URL, codeLookupTemplate: String? = nil, blurb: String) {
        self.id = id
        self.name = name
        self.eligibility = eligibility
        self.regions = regions
        self.homepage = homepage
        self.codeLookupTemplate = codeLookupTemplate
        self.blurb = blurb
    }

    /// Search URL for this merchant on the program's site.
    public func lookupURL(for merchant: String) -> URL? {
        guard let template = codeLookupTemplate else { return nil }
        let q = merchant.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? merchant
        return URL(string: template.replacingOccurrences(of: "{q}", with: q))
    }
}

/// A known discount at a specific merchant.
public struct MerchantDiscount: Codable, Hashable, Sendable, Identifiable {
    public enum Mechanism: String, Codable, Sendable {
        /// A code entered at checkout.
        case code
        /// Price drops automatically once your account is verified.
        case verifiedAccount
        /// A separate storefront (e.g. education store).
        case dedicatedStore
    }

    public var id: String { "\(merchantDomain)|\(eligibility.rawValue)|\(programID ?? "direct")" }
    public var merchantDomain: String
    public var merchantName: String
    public var eligibility: Eligibility
    public var programID: String?
    public var mechanism: Mechanism
    /// Typical saving as a fraction. Always treated as an estimate in the UI.
    public var typicalFraction: Double?
    public var url: URL?
    public var note: String?

    public init(merchantDomain: String, merchantName: String, eligibility: Eligibility, programID: String? = nil, mechanism: Mechanism, typicalFraction: Double? = nil, url: URL? = nil, note: String? = nil) {
        self.merchantDomain = Offer.normalizedDomain(merchantDomain)
        self.merchantName = merchantName
        self.eligibility = eligibility
        self.programID = programID
        self.mechanism = mechanism
        self.typicalFraction = typicalFraction
        self.url = url
        self.note = note
    }
}

/// A code the user saved, captured from a page, or that worked before.
public struct SavedCode: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var code: String
    public var merchantDomain: String?
    public var eligibility: Eligibility?
    public var source: Source
    public var expiresAt: Date?
    public var lastWorkedAt: Date?
    public var lastSaving: Double?
    public var failures: Int

    public enum Source: String, Codable, Sendable { case manual, captured, program, welcome }

    public init(id: UUID = UUID(), code: String, merchantDomain: String? = nil, eligibility: Eligibility? = nil, source: Source, expiresAt: Date? = nil, lastWorkedAt: Date? = nil, lastSaving: Double? = nil, failures: Int = 0) {
        self.id = id
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.merchantDomain = merchantDomain.map(Offer.normalizedDomain)
        self.eligibility = eligibility
        self.source = source
        self.expiresAt = expiresAt
        self.lastWorkedAt = lastWorkedAt
        self.lastSaving = lastSaving
        self.failures = failures
    }

    public func isUsable(at date: Date = .now) -> Bool {
        if let expiresAt, expiresAt < date { return false }
        return failures < 3
    }
}
