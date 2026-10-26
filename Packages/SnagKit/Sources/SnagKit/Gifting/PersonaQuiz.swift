import Foundation

/// A short "this or that" quiz. Each choice nudges trait dimensions; the
/// result is a trait vector plus aesthetics. Ten taps, under a minute.
public struct PersonaQuiz: Sendable {
    public struct Question: Identifiable, Sendable, Hashable {
        public var id: String
        public var prompt: String
        public var choices: [Choice]
        public var allowsMultiple: Bool
    }

    public struct Choice: Identifiable, Sendable, Hashable {
        public var id: String
        public var title: String
        public var symbol: String
        public var effects: [PersonaTraits.Key: Double]
        public var aesthetic: Aesthetic?
        public var interests: [Interest]

        init(_ id: String, _ title: String, _ symbol: String, _ effects: [PersonaTraits.Key: Double] = [:], aesthetic: Aesthetic? = nil, interests: [Interest] = []) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.effects = effects
            self.aesthetic = aesthetic
            self.interests = interests
        }
    }

    public var questions: [Question]

    public static let standard = PersonaQuiz(questions: [
        Question(id: "saturday", prompt: "A free Saturday looks like…", choices: [
            Choice("plans", "Packed with plans and people", "person.3.fill", [.extraversion: 0.35, .experiential: 0.2]),
            Choice("slow", "A slow day at home", "sofa.fill", [.extraversion: -0.3, .stability: 0.15], aesthetic: .cozy, interests: [.home]),
            Choice("outside", "Somewhere outdoors", "mountain.2.fill", [.experiential: 0.3, .openness: 0.1], aesthetic: .natural, interests: [.hiking]),
            Choice("project", "Finally starting that project", "hammer.fill", [.conscientiousness: 0.2, .practicality: 0.2], interests: [.diy, .crafts]),
        ], allowsMultiple: false),
        Question(id: "surprise", prompt: "When you give a gift, you'd rather it…", choices: [
            Choice("surprise", "Be a surprise nobody saw coming", "sparkles", [.openness: 0.3, .playfulness: 0.15]),
            Choice("asked", "Be exactly what they asked for", "checklist", [.practicality: 0.35, .conscientiousness: 0.15]),
            Choice("tears", "Make them a little teary", "heart.fill", [.sentimentality: 0.4, .agreeableness: 0.15]),
            Choice("laugh", "Make them laugh out loud", "face.smiling.inverse", [.playfulness: 0.4, .extraversion: 0.1]),
        ], allowsMultiple: false),
        Question(id: "desk", prompt: "Your desk right now is…", choices: [
            Choice("tidy", "Everything has its place", "square.grid.2x2.fill", [.conscientiousness: 0.35], aesthetic: .minimal),
            Choice("chaos", "Creative chaos", "scribble.variable", [.openness: 0.25, .conscientiousness: -0.25], aesthetic: .bold),
            Choice("gadgets", "Cables, screens and gadgets", "desktopcomputer", [.openness: 0.1], aesthetic: .techy, interests: [.tech]),
            Choice("plants", "Plants and a candle", "leaf.fill", [.stability: 0.1], aesthetic: .natural, interests: [.plants]),
        ], allowsMultiple: false),
        Question(id: "souvenir", prompt: "Best souvenir from a trip?", choices: [
            Choice("memory", "The memories — no souvenir needed", "photo.on.rectangle.angled", [.experiential: 0.4, .sustainability: 0.15], interests: [.travel]),
            Choice("craft", "Something handmade by a local", "hands.sparkles.fill", [.sentimentality: 0.2, .sustainability: 0.2], aesthetic: .vintage, interests: [.crafts]),
            Choice("food", "Food and drink to bring home", "takeoutbag.and.cup.and.straw.fill", [.playfulness: 0.1, .experiential: 0.1], interests: [.foodie]),
            Choice("designer", "One beautiful, well-made thing", "bag.fill", [.luxury: 0.35], aesthetic: .luxe),
        ], allowsMultiple: false),
        Question(id: "splurge", prompt: "You'd splurge on…", choices: [
            Choice("lasting", "Quality that lasts a decade", "hourglass", [.practicality: 0.2, .luxury: 0.2, .sustainability: 0.15]),
            Choice("fun", "Something fun, right now", "bolt.fill", [.playfulness: 0.3, .conscientiousness: -0.1]),
            Choice("experience", "A night out or a trip", "ticket.fill", [.experiential: 0.35, .extraversion: 0.15]),
            Choice("treat", "A proper treat for myself", "crown.fill", [.luxury: 0.35], aesthetic: .luxe, interests: [.wellness]),
        ], allowsMultiple: false),
        Question(id: "news", prompt: "Big news! You tell people by…", choices: [
            Choice("everyone", "Group chat, immediately", "bubble.left.and.bubble.right.fill", [.extraversion: 0.3]),
            Choice("close", "Telling a couple of close friends", "person.2.fill", [.agreeableness: 0.15, .extraversion: -0.1]),
            Choice("post", "A carefully composed post", "camera.fill", [.openness: 0.1, .conscientiousness: 0.1], interests: [.photography]),
            Choice("later", "Whenever it comes up", "moon.zzz.fill", [.stability: 0.25, .extraversion: -0.2]),
        ], allowsMultiple: false),
        Question(id: "eco", prompt: "How much does sustainability shape what you buy?", choices: [
            Choice("lots", "A lot — I check", "leaf.arrow.triangle.circlepath", [.sustainability: 0.45], interests: [.sustainability]),
            Choice("some", "When it's easy", "arrow.3.trianglepath", [.sustainability: 0.15]),
            Choice("little", "Honestly, not much", "cart.fill", [.sustainability: -0.2]),
        ], allowsMultiple: false),
        Question(id: "aesthetic", prompt: "Pick the rooms you'd live in", choices: [
            Choice("minimal", "Clean and minimal", "square.on.square", aesthetic: .minimal),
            Choice("cozy", "Warm and cosy", "flame.fill", aesthetic: .cozy),
            Choice("bold", "Bold colour", "paintpalette.fill", [.openness: 0.1], aesthetic: .bold),
            Choice("vintage", "Vintage finds", "clock.arrow.circlepath", aesthetic: .vintage),
            Choice("natural", "Natural materials", "tree.fill", aesthetic: .natural),
            Choice("techy", "Smart and techy", "cpu.fill", aesthetic: .techy),
            Choice("luxe", "Hotel-lobby luxe", "sparkles", [.luxury: 0.1], aesthetic: .luxe),
            Choice("playful", "Playful and fun", "balloon.2.fill", [.playfulness: 0.1], aesthetic: .playful),
        ], allowsMultiple: true),
        Question(id: "love", prompt: "You feel most cared for when someone…", choices: [
            Choice("time", "Spends real time with you", "clock.fill", [.experiential: 0.25, .agreeableness: 0.1]),
            Choice("words", "Writes you something heartfelt", "envelope.open.fill", [.sentimentality: 0.35]),
            Choice("help", "Takes something off your plate", "hand.raised.fill", [.practicality: 0.3]),
            Choice("gift", "Remembers the perfect thing", "gift.fill", [.openness: 0.1, .sentimentality: 0.15]),
        ], allowsMultiple: false),
        Question(id: "passions", prompt: "Which of these are you into?", choices: [
            Choice("p-outdoors", "Outdoors", "figure.hiking", interests: [.hiking, .camping]),
            Choice("p-food", "Food & drink", "fork.knife", interests: [.cooking, .foodie]),
            Choice("p-coffee", "Coffee", "cup.and.saucer.fill", interests: [.coffee]),
            Choice("p-music", "Music", "music.note", interests: [.music, .concerts]),
            Choice("p-books", "Books", "book.fill", interests: [.reading]),
            Choice("p-games", "Games", "gamecontroller.fill", interests: [.gaming, .boardGames]),
            Choice("p-fitness", "Fitness", "figure.run", interests: [.fitness, .running]),
            Choice("p-style", "Style", "tshirt.fill", interests: [.fashion]),
            Choice("p-art", "Art & design", "paintpalette.fill", interests: [.art, .design]),
            Choice("p-tech", "Tech", "cpu.fill", interests: [.tech]),
            Choice("p-travel", "Travel", "airplane", interests: [.travel]),
            Choice("p-pets", "Pets", "pawprint.fill", interests: [.dogs, .cats]),
        ], allowsMultiple: true),
    ])

    /// Scores a set of answers (question id → choice ids).
    public func evaluate(_ answers: [String: [String]]) -> (traits: PersonaTraits, aesthetics: [Aesthetic], interests: [WeightedInterest]) {
        var traits = PersonaTraits.neutral
        var aestheticCounts: [Aesthetic: Int] = [:]
        var interests: [WeightedInterest] = []

        for question in questions {
            guard let picked = answers[question.id], !picked.isEmpty else { continue }
            let choices = question.choices.filter { picked.contains($0.id) }
            // Multi-select questions shouldn't swamp single-choice ones.
            let damping = question.allowsMultiple ? 1 / Double(max(1, choices.count)) : 1
            for choice in choices {
                for (key, delta) in choice.effects {
                    traits[key] = traits[key] + delta * damping
                }
                if let a = choice.aesthetic { aestheticCounts[a, default: 0] += 1 }
                interests += choice.interests.map { WeightedInterest($0, weight: question.allowsMultiple ? 0.8 : 0.55, sources: [.quiz]) }
            }
        }

        let aesthetics = aestheticCounts.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }.map(\.key)
        return (traits, Array(aesthetics.prefix(3)), InterestMatcher.merge(interests))
    }
}
