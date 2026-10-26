import Foundation

public enum Relationship: String, Codable, CaseIterable, Sendable, Identifiable {
    case partner, parent, sibling, child, grandparent, friend, bestFriend, colleague, boss, teacher, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .partner: "Partner"
        case .parent: "Parent"
        case .sibling: "Sibling"
        case .child: "Child"
        case .grandparent: "Grandparent"
        case .friend: "Friend"
        case .bestFriend: "Best friend"
        case .colleague: "Colleague"
        case .boss: "Boss"
        case .teacher: "Teacher"
        case .other: "Someone else"
        }
    }

    /// How personal a gift can comfortably be (0 = keep it neutral).
    public var intimacy: Double {
        switch self {
        case .partner: 1
        case .bestFriend, .parent, .child, .sibling, .grandparent: 0.8
        case .friend: 0.6
        case .other: 0.4
        case .colleague, .teacher: 0.25
        case .boss: 0.15
        }
    }
}

public enum AgeBand: String, Codable, CaseIterable, Sendable, Identifiable {
    case kid, teen, twenties, thirties, forties, fifties, sixtyPlus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .kid: "Under 13"
        case .teen: "Teen"
        case .twenties: "20s"
        case .thirties: "30s"
        case .forties: "40s"
        case .fifties: "50s"
        case .sixtyPlus: "60+"
        }
    }

    public var isAdult: Bool { self != .kid && self != .teen }
}

public enum Occasion: String, Codable, CaseIterable, Sendable, Identifiable {
    case birthday, anniversary, christmas, valentines, mothersDay, fathersDay, graduation, wedding, housewarming, newBaby, thankYou, justBecause

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .birthday: "Birthday"
        case .anniversary: "Anniversary"
        case .christmas: "Holidays"
        case .valentines: "Valentine's Day"
        case .mothersDay: "Mother's Day"
        case .fathersDay: "Father's Day"
        case .graduation: "Graduation"
        case .wedding: "Wedding"
        case .housewarming: "Housewarming"
        case .newBaby: "New baby"
        case .thankYou: "Thank you"
        case .justBecause: "Just because"
        }
    }

    public var symbol: String {
        switch self {
        case .birthday: "birthday.cake.fill"
        case .anniversary: "heart.circle.fill"
        case .christmas: "snowflake"
        case .valentines: "heart.fill"
        case .mothersDay, .fathersDay: "figure.and.child.holdinghands"
        case .graduation: "graduationcap.fill"
        case .wedding: "sparkles"
        case .housewarming: "house.fill"
        case .newBaby: "stroller.fill"
        case .thankYou: "hands.clap.fill"
        case .justBecause: "gift.fill"
        }
    }

    /// Occasions where something romantic or deeply personal fits.
    public var isRomantic: Bool { self == .anniversary || self == .valentines }
}

/// Someone the user buys gifts for.
public struct RecipientProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var relationship: Relationship
    public var ageBand: AgeBand?
    public var interests: [WeightedInterest]
    public var aesthetics: [Aesthetic]
    /// Optional slider-based read on their personality.
    public var traits: PersonaTraits?
    public var dislikes: [String]
    public var notes: String
    public var budgetMin: Double
    public var budgetMax: Double
    public var currency: String
    public var occasion: Occasion
    public var occasionDate: Date?
    public var pastGifts: [String]
    public var signals: [String]
    public var sources: Set<SignalSource>

    public init(
        id: UUID = UUID(),
        name: String,
        relationship: Relationship = .friend,
        ageBand: AgeBand? = nil,
        interests: [WeightedInterest] = [],
        aesthetics: [Aesthetic] = [],
        traits: PersonaTraits? = nil,
        dislikes: [String] = [],
        notes: String = "",
        budgetMin: Double = 20,
        budgetMax: Double = 75,
        currency: String = "USD",
        occasion: Occasion = .birthday,
        occasionDate: Date? = nil,
        pastGifts: [String] = [],
        signals: [String] = [],
        sources: Set<SignalSource> = []
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.ageBand = ageBand
        self.interests = interests
        self.aesthetics = aesthetics
        self.traits = traits
        self.dislikes = dislikes
        self.notes = notes
        self.budgetMin = budgetMin
        self.budgetMax = budgetMax
        self.currency = currency
        self.occasion = occasion
        self.occasionDate = occasionDate
        self.pastGifts = pastGifts
        self.signals = signals
        self.sources = sources
    }

    public var budgetMid: Double { (budgetMin + budgetMax) / 2 }

    /// Days until the occasion, if it has a date in the future.
    public func daysUntilOccasion(from now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let occasionDate else { return nil }
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: occasionDate)
        let days = calendar.dateComponents([.day], from: start, to: end).day
        return days.flatMap { $0 >= 0 ? $0 : nil }
    }
}

/// A recommendation, from the AI or from the built-in catalog.
public struct GiftIdea: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case object, experience, consumable, subscription, personalised

        public var title: String {
            switch self {
            case .object: "Thing"
            case .experience: "Experience"
            case .consumable: "Treat"
            case .subscription: "Subscription"
            case .personalised: "Personalised"
            }
        }

        public var symbol: String {
            switch self {
            case .object: "shippingbox.fill"
            case .experience: "ticket.fill"
            case .consumable: "takeoutbag.and.cup.and.straw.fill"
            case .subscription: "arrow.triangle.2.circlepath"
            case .personalised: "signature"
            }
        }
    }

    public enum Origin: String, Codable, Sendable {
        case onDeviceAI, cloudAI, catalog
    }

    public var id: UUID
    public var title: String
    public var pitch: String
    /// Why it suits the recipient.
    public var whyThem: String
    /// How it reflects the giver — the part that makes it feel "from you".
    public var whyYou: String
    public var kind: Kind
    public var interests: [Interest]
    public var estimatedPrice: Double?
    public var currency: String
    /// What to type into a shop's search box to find it.
    public var searchQuery: String
    public var personalTouch: String?
    public var cardMessage: String?
    /// 0–1 how unexpected-but-right it is.
    public var delight: Double
    /// 0–1 model/heuristic confidence that it fits.
    public var fit: Double
    public var origin: Origin

    public init(
        id: UUID = UUID(),
        title: String,
        pitch: String,
        whyThem: String,
        whyYou: String,
        kind: Kind,
        interests: [Interest] = [],
        estimatedPrice: Double? = nil,
        currency: String,
        searchQuery: String,
        personalTouch: String? = nil,
        cardMessage: String? = nil,
        delight: Double = 0.5,
        fit: Double = 0.5,
        origin: Origin
    ) {
        self.id = id
        self.title = title
        self.pitch = pitch
        self.whyThem = whyThem
        self.whyYou = whyYou
        self.kind = kind
        self.interests = interests
        self.estimatedPrice = estimatedPrice
        self.currency = currency
        self.searchQuery = searchQuery
        self.personalTouch = personalTouch
        self.cardMessage = cardMessage
        self.delight = min(1, max(0, delight))
        self.fit = min(1, max(0, fit))
        self.origin = origin
    }
}
