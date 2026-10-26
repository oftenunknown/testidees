import Foundation

/// Deterministic recommender. Scores catalog templates against the
/// recipient (what they like) and the giver (what feels like them), then picks
/// a diverse set. Used offline, as the free tier, and to seed AI prompts.
public enum GiftRecommender {
    public struct Scored: Sendable {
        public var template: GiftTemplate
        public var score: Double
        public var matchedInterests: [Interest]
        public var sharedInterest: Interest?
    }

    public static func recommend(
        for recipient: RecipientProfile,
        from giver: PersonaProfile,
        count: Int = 8,
        templates: [GiftTemplate] = GiftCatalog.templates
    ) -> [GiftIdea] {
        let picks = diversify(score(templates, recipient: recipient, giver: giver), count: count)
        return picks.map { idea(from: $0, recipient: recipient, giver: giver) }
    }

    public static func score(_ templates: [GiftTemplate], recipient: RecipientProfile, giver: PersonaProfile) -> [Scored] {
        let recipientWeights = Dictionary(recipient.interests.map { ($0.interest, $0.weight) }, uniquingKeysWith: max)
        let giverWeights = Dictionary(giver.interests.map { ($0.interest, $0.weight) }, uniquingKeysWith: max)
        let isMinor = recipient.ageBand.map { !$0.isAdult } ?? false
        let dislikes = recipient.dislikes.map { $0.lowercased() }.filter { !$0.isEmpty }
        let pastGiftTokens = recipient.pastGifts.map(tokens)

        return templates.compactMap { t in
            if isMinor && t.adultsOnly { return nil }
            let text = (t.title + " " + t.pitch + " " + t.query + " " + t.interests.map(\.title).joined(separator: " ")).lowercased()
            if dislikes.contains(where: { text.contains($0) }) { return nil }

            // What they like.
            let matched = t.interests.filter { recipientWeights[$0] != nil }.sorted { recipientWeights[$0]! > recipientWeights[$1]! }
            let interestScore: Double
            if recipientWeights.isEmpty {
                interestScore = 0.3
            } else if let top = matched.first {
                interestScore = min(1, recipientWeights[top]! + 0.15 * Double(matched.count - 1))
            } else {
                interestScore = 0
            }

            // Who they are.
            let recipientTraitScore = recipient.traits.map { affinityScore(t.affinity, $0) } ?? 0.5

            // Who you are — the "from you" part.
            var giverScore = affinityScore(t.affinity, giver.traits)
            let shared = t.interests.first { giverWeights[$0] != nil && recipientWeights[$0] != nil }
            if t.shared, shared != nil { giverScore += 0.25 * recipient.relationship.intimacy }
            if !Set(t.aesthetics).isDisjoint(with: giver.aesthetics) { giverScore += 0.1 }

            let aestheticScore = recipient.aesthetics.isEmpty || t.aesthetics.isEmpty
                ? 0.5
                : (Set(t.aesthetics).isDisjoint(with: recipient.aesthetics) ? 0.2 : 1)

            let budget = budgetFit(price: CurrencyHint.fromUSD(t.typicalPrice, to: recipient.currency), min: recipient.budgetMin, max: recipient.budgetMax)
            let occasion = occasionFit(t, occasion: recipient.occasion)

            var total = 0.38 * interestScore
                + 0.14 * recipientTraitScore
                + 0.18 * min(1, giverScore)
                + 0.08 * aestheticScore
                + 0.14 * budget
                + 0.08 * occasion

            // Very personal gifts are awkward for a boss or colleague.
            if (t.kind == .personalised || (t.affinity[.sentimentality] ?? 0) > 0.6) && recipient.relationship.intimacy < 0.3 {
                total -= 0.15
            }
            // Don't repeat last year's gift.
            let templateTokens = tokens(t.title + " " + t.query)
            if pastGiftTokens.contains(where: { jaccard($0, templateTokens) > 0.34 }) { total -= 0.3 }

            return Scored(template: t, score: total, matchedInterests: matched, sharedInterest: shared)
        }
        .sorted { $0.score > $1.score }
    }

    /// Greedy selection that avoids five near-identical ideas.
    static func diversify(_ scored: [Scored], count: Int) -> [Scored] {
        var remaining = scored
        var picked: [Scored] = []
        while picked.count < count, !remaining.isEmpty {
            let adjusted = remaining.enumerated().map { index, s -> (Int, Double) in
                let sameKind = picked.filter { $0.template.kind == s.template.kind }.count
                let samePrimary = picked.filter { $0.template.interests.first == s.template.interests.first }.count
                return (index, s.score - 0.05 * Double(sameKind) - 0.09 * Double(samePrimary))
            }
            guard let best = adjusted.max(by: { $0.1 < $1.1 }) else { break }
            picked.append(remaining.remove(at: best.0))
        }
        return picked
    }

    static func idea(from s: Scored, recipient: RecipientProfile, giver: PersonaProfile) -> GiftIdea {
        let t = s.template
        let name = recipient.name.isEmpty ? "They" : recipient.name
        let archetype = giver.archetype

        let whyThem: String
        if let first = s.matchedInterests.first {
            if let second = s.matchedInterests.dropFirst().first {
                whyThem = "Hits two of \(name)'s things at once: \(first.title.lowercased()) and \(second.title.lowercased())."
            } else {
                whyThem = "Built around \(name)'s love of \(first.title.lowercased())."
            }
        } else if let traits = recipient.traits, let trait = traits.dominant(1).first, (t.affinity[trait] ?? 0) > 0.3 {
            whyThem = "Suits how \(name) is — \(trait.title.lowercased()) through and through."
        } else {
            whyThem = "A well-loved pick for a \(recipient.relationship.title.lowercased())."
        }

        let whyYou: String
        if t.shared, let shared = s.sharedInterest {
            whyYou = "You're both into \(shared.title.lowercased()), so this comes with a plan to do it together."
        } else {
            whyYou = signatureLine(for: archetype)
        }

        let personalisedBoost = (t.kind == .personalised || t.kind == .experience) ? 0.15 : 0
        let delight = min(1, 0.35 + giver.traits.openness * 0.3 + personalisedBoost + (s.matchedInterests.count > 1 ? 0.1 : 0))

        return GiftIdea(
            title: t.title,
            pitch: t.pitch,
            whyThem: whyThem,
            whyYou: whyYou,
            kind: t.kind,
            interests: t.interests,
            estimatedPrice: CurrencyHint.fromUSD(t.typicalPrice, to: recipient.currency).rounded(),
            currency: recipient.currency,
            searchQuery: t.query,
            personalTouch: t.personalTouch,
            cardMessage: cardMessage(recipient: recipient, archetype: archetype),
            delight: delight,
            fit: min(1, max(0, s.score / 0.85)),
            origin: .catalog
        )
    }

    public static func signatureLine(for archetype: Archetype) -> String {
        switch archetype.id {
        case "adventurer": "Very you: it's an invitation, not just a box."
        case "curator": "Very you: a find with a story they won't have seen."
        case "sentimentalist": "Very you: the personal touch is the whole point."
        case "pragmatist": "Very you: they'll use it every single day."
        case "entertainer": "Very you: it gets a laugh first and becomes a favourite later."
        case "connoisseur": "Very you: one exceptional thing beats three good ones."
        case "conscious": "Very you: made to last and kind to the planet."
        default: "Very you: pure comfort, a little indulgent."
        }
    }

    public static func cardMessage(recipient: RecipientProfile, archetype: Archetype) -> String {
        let name = recipient.name.isEmpty ? "you" : recipient.name
        let opener: String
        switch recipient.occasion {
        case .birthday: opener = "Happy birthday, \(name)!"
        case .anniversary: opener = "Happy anniversary, \(name)."
        case .christmas: opener = "Happy holidays, \(name)!"
        case .valentines: opener = "To \(name), with love."
        case .mothersDay: opener = "Happy Mother's Day!"
        case .fathersDay: opener = "Happy Father's Day!"
        case .graduation: opener = "You did it, \(name)!"
        case .wedding: opener = "To a lifetime of adventures together."
        case .housewarming: opener = "Welcome home, \(name)!"
        case .newBaby: opener = "Congratulations on your little one!"
        case .thankYou: opener = "Thank you, \(name)."
        case .justBecause: opener = "No reason, \(name) — just because."
        }
        let closer: String
        switch archetype.id {
        case "adventurer": closer = "Here's to the next adventure."
        case "sentimentalist": closer = "Something to keep, because you matter."
        case "pragmatist": closer = "Saw this and knew you'd actually use it."
        case "entertainer": closer = "Try not to laugh. (You will.)"
        case "connoisseur": closer = "Only the good stuff for you."
        case "conscious": closer = "Made well, made to last — like us."
        case "curator": closer = "Found this and thought of you instantly."
        default: closer = "Look after yourself — you deserve it."
        }
        return opener + " " + closer
    }

    // MARK: - Scoring helpers

    /// Maps trait alignment to 0–1 with 0.5 meaning neutral.
    static func affinityScore(_ affinity: [PersonaTraits.Key: Double], _ traits: PersonaTraits) -> Double {
        guard !affinity.isEmpty else { return 0.5 }
        let totalWeight = affinity.values.map(abs).reduce(0, +)
        let raw = affinity.reduce(0) { $0 + $1.value * (traits[$1.key] - 0.5) * 2 } / max(totalWeight, 0.001)
        return min(1, max(0, 0.5 + raw / 2))
    }

    static func budgetFit(price: Double, min lower: Double, max upper: Double) -> Double {
        guard price > 0, upper > 0 else { return 0.5 }
        let lo = Swift.min(lower, upper), hi = Swift.max(lower, upper)
        if price >= lo * 0.9 && price <= hi * 1.05 { return 1 }
        let anchor = price < lo ? Swift.max(lo, 1) : hi
        let ratio = abs(log(price / anchor))
        return exp(-ratio * 2.2)
    }

    static func occasionFit(_ t: GiftTemplate, occasion: Occasion) -> Double {
        switch occasion {
        case .anniversary, .valentines:
            return t.shared || t.kind == .personalised || (t.affinity[.sentimentality] ?? 0) > 0.5 ? 1 : 0.4
        case .housewarming:
            return t.interests.contains(.home) || t.interests.contains(.plants) || t.interests.contains(.cooking) ? 1 : 0.3
        case .newBaby:
            return t.interests.contains(.parenting) ? 1 : 0.2
        case .graduation:
            return t.kind == .experience || t.interests.contains(.travel) || t.interests.contains(.tech) ? 0.9 : 0.5
        case .thankYou:
            return t.kind == .consumable || t.typicalPrice <= 50 ? 1 : 0.3
        case .wedding:
            return t.shared || t.interests.contains(.home) ? 0.9 : 0.4
        case .mothersDay, .fathersDay:
            return (t.affinity[.sentimentality] ?? 0) > 0.3 || t.kind == .experience ? 0.9 : 0.6
        case .birthday, .christmas, .justBecause:
            return 0.7
        }
    }

    static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b).count
        return union == 0 ? 0 : Double(a.intersection(b).count) / Double(union)
    }
}

/// Very rough currency scaling for budget matching only — never shown as a price.
public enum CurrencyHint {
    public static func fromUSD(_ amount: Double, to currency: String) -> Double {
        switch currency.uppercased() {
        case "GBP": amount * 0.8
        case "EUR": amount * 0.92
        default: amount
        }
    }
}
