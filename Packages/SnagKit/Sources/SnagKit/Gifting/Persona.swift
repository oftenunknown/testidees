import Foundation

/// Personality and gifting-style dimensions, each 0–1 with 0.5 as neutral.
public struct PersonaTraits: Codable, Hashable, Sendable {
    // Big Five
    public var openness: Double
    public var conscientiousness: Double
    public var extraversion: Double
    public var agreeableness: Double
    public var stability: Double
    // Gifting style
    public var sentimentality: Double
    public var practicality: Double
    public var playfulness: Double
    public var luxury: Double
    public var sustainability: Double
    public var experiential: Double

    public init(
        openness: Double = 0.5, conscientiousness: Double = 0.5, extraversion: Double = 0.5,
        agreeableness: Double = 0.5, stability: Double = 0.5, sentimentality: Double = 0.5,
        practicality: Double = 0.5, playfulness: Double = 0.5, luxury: Double = 0.5,
        sustainability: Double = 0.5, experiential: Double = 0.5
    ) {
        self.openness = openness
        self.conscientiousness = conscientiousness
        self.extraversion = extraversion
        self.agreeableness = agreeableness
        self.stability = stability
        self.sentimentality = sentimentality
        self.practicality = practicality
        self.playfulness = playfulness
        self.luxury = luxury
        self.sustainability = sustainability
        self.experiential = experiential
    }

    public static let neutral = PersonaTraits()

    public enum Key: String, CaseIterable, Codable, Sendable {
        case openness, conscientiousness, extraversion, agreeableness, stability
        case sentimentality, practicality, playfulness, luxury, sustainability, experiential

        public var title: String {
            switch self {
            case .openness: "Curious"
            case .conscientiousness: "Organised"
            case .extraversion: "Outgoing"
            case .agreeableness: "Warm"
            case .stability: "Calm"
            case .sentimentality: "Sentimental"
            case .practicality: "Practical"
            case .playfulness: "Playful"
            case .luxury: "Indulgent"
            case .sustainability: "Eco-minded"
            case .experiential: "Experiences"
            }
        }
    }

    public subscript(key: Key) -> Double {
        get {
            switch key {
            case .openness: openness
            case .conscientiousness: conscientiousness
            case .extraversion: extraversion
            case .agreeableness: agreeableness
            case .stability: stability
            case .sentimentality: sentimentality
            case .practicality: practicality
            case .playfulness: playfulness
            case .luxury: luxury
            case .sustainability: sustainability
            case .experiential: experiential
            }
        }
        set {
            let v = min(1, max(0, newValue))
            switch key {
            case .openness: openness = v
            case .conscientiousness: conscientiousness = v
            case .extraversion: extraversion = v
            case .agreeableness: agreeableness = v
            case .stability: stability = v
            case .sentimentality: sentimentality = v
            case .practicality: practicality = v
            case .playfulness: playfulness = v
            case .luxury: luxury = v
            case .sustainability: sustainability = v
            case .experiential: experiential = v
            }
        }
    }

    /// Strongest deviations from neutral, for summaries like "Curious · Playful".
    public func dominant(_ count: Int = 3) -> [Key] {
        Key.allCases
            .filter { self[$0] > 0.55 }
            .sorted { self[$0] > self[$1] }
            .prefix(count)
            .map { $0 }
    }

    /// Blends towards `other` by `amount` (0 keeps self, 1 takes other).
    public func blended(with other: PersonaTraits, amount: Double) -> PersonaTraits {
        var result = self
        for key in Key.allCases {
            result[key] = self[key] * (1 - amount) + other[key] * amount
        }
        return result
    }
}

public enum Aesthetic: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal, cozy, bold, vintage, techy, natural, luxe, playful

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .minimal: "Minimal"
        case .cozy: "Cosy"
        case .bold: "Bold"
        case .vintage: "Vintage"
        case .techy: "Techy"
        case .natural: "Natural"
        case .luxe: "Luxe"
        case .playful: "Playful"
        }
    }
}

/// A gifting archetype — the headline of someone's persona card.
public struct Archetype: Hashable, Sendable {
    public var id: String
    public var name: String
    public var tagline: String
    public var giftingStyle: String
    public var symbol: String
    /// Hue (0–1) the app uses to tint the persona card.
    public var hue: Double

    static let all: [(Archetype, [PersonaTraits.Key: Double])] = [
        (Archetype(id: "adventurer", name: "The Adventurer", tagline: "Says yes first, plans later.",
                   giftingStyle: "Your gifts are invitations — tickets, trips and things that get people outside.",
                   symbol: "mountain.2.fill", hue: 0.36),
         [.experiential: 1.2, .openness: 0.8, .extraversion: 0.6, .playfulness: 0.3]),
        (Archetype(id: "curator", name: "The Curator", tagline: "Finds the thing before everyone else does.",
                   giftingStyle: "You give beautifully chosen objects with a story behind them.",
                   symbol: "sparkle.magnifyingglass", hue: 0.78),
         [.openness: 1.0, .luxury: 0.6, .conscientiousness: 0.4, .sentimentality: 0.2]),
        (Archetype(id: "sentimentalist", name: "The Sentimentalist", tagline: "Remembers the small things.",
                   giftingStyle: "Your gifts are personal — engraved, handwritten, made to be kept.",
                   symbol: "heart.text.square.fill", hue: 0.95),
         [.sentimentality: 1.3, .agreeableness: 0.8, .stability: 0.2]),
        (Archetype(id: "pragmatist", name: "The Pragmatist", tagline: "If it's not useful, why bother?",
                   giftingStyle: "You give the upgrade people didn't know they needed and will use every day.",
                   symbol: "checkmark.seal.fill", hue: 0.58),
         [.practicality: 1.3, .conscientiousness: 0.9, .luxury: -0.2]),
        (Archetype(id: "entertainer", name: "The Entertainer", tagline: "Brings the fun to every room.",
                   giftingStyle: "Your gifts get a laugh first and become favourites later.",
                   symbol: "party.popper.fill", hue: 0.12),
         [.playfulness: 1.3, .extraversion: 1.0, .openness: 0.3]),
        (Archetype(id: "connoisseur", name: "The Connoisseur", tagline: "Fewer, better things.",
                   giftingStyle: "You give one exceptional thing rather than three good ones.",
                   symbol: "crown.fill", hue: 0.11),
         [.luxury: 1.3, .conscientiousness: 0.5, .practicality: -0.2, .openness: 0.3]),
        (Archetype(id: "conscious", name: "The Conscious Giver", tagline: "Gives with the planet in mind.",
                   giftingStyle: "Your gifts are made well, made ethically, or not made at all — experiences count.",
                   symbol: "leaf.fill", hue: 0.33),
         [.sustainability: 1.4, .experiential: 0.4, .practicality: 0.3]),
        (Archetype(id: "nurturer", name: "The Nurturer", tagline: "Looks after everyone, including you.",
                   giftingStyle: "Your gifts are comfort — cosy, restorative and a little bit indulgent.",
                   symbol: "cup.and.heat.waves.fill", hue: 0.05),
         [.agreeableness: 1.1, .stability: 0.5, .sentimentality: 0.5, .luxury: 0.3]),
    ]

    /// Picks the archetype whose trait profile best matches.
    public static func best(for traits: PersonaTraits) -> Archetype {
        all.max { score(traits, $0.1) < score(traits, $1.1) }!.0
    }

    /// Ranked archetypes with normalised scores, for "a bit of each" summaries.
    public static func ranked(for traits: PersonaTraits) -> [(Archetype, Double)] {
        all.map { ($0.0, score(traits, $0.1)) }.sorted { $0.1 > $1.1 }
    }

    static func score(_ traits: PersonaTraits, _ weights: [PersonaTraits.Key: Double]) -> Double {
        weights.reduce(0) { $0 + ($1.value * (traits[$1.key] - 0.5)) }
    }
}

/// Everything we've learned about the person giving gifts.
public struct PersonaProfile: Codable, Hashable, Sendable {
    public var displayName: String
    public var traits: PersonaTraits
    public var interests: [WeightedInterest]
    public var aesthetics: [Aesthetic]
    /// AI-written portrait, 2–3 sentences.
    public var summary: String?
    /// AI-written description of how this person's gifts feel.
    public var signature: String?
    /// Raw signals we learned from (photo labels, topics), kept for re-analysis.
    public var signals: [String]
    public var sources: Set<SignalSource>
    public var quizAnswers: [String: String]
    public var updatedAt: Date

    public init(
        displayName: String = "",
        traits: PersonaTraits = .neutral,
        interests: [WeightedInterest] = [],
        aesthetics: [Aesthetic] = [],
        summary: String? = nil,
        signature: String? = nil,
        signals: [String] = [],
        sources: Set<SignalSource> = [],
        quizAnswers: [String: String] = [:],
        updatedAt: Date = .now
    ) {
        self.displayName = displayName
        self.traits = traits
        self.interests = interests
        self.aesthetics = aesthetics
        self.summary = summary
        self.signature = signature
        self.signals = signals
        self.sources = sources
        self.quizAnswers = quizAnswers
        self.updatedAt = updatedAt
    }

    public var archetype: Archetype { Archetype.best(for: traits) }

    /// 0–1 completeness, used to nudge people to add another signal.
    public var completeness: Double {
        var score = 0.0
        if sources.contains(.quiz) { score += 0.4 }
        if sources.contains(.photos) || sources.contains(.instagramExport) { score += 0.3 }
        if sources.contains(.orderHistory) || sources.contains(.wishlist) { score += 0.15 }
        if interests.count >= 3 { score += 0.15 }
        return min(1, score)
    }

    public var topInterests: [Interest] { interests.prefix(6).map(\.interest) }
}
