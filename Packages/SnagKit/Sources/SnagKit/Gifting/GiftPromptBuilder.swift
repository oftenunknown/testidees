import Foundation

/// Builds the language-model prompt for gift ideas. Shared by the on-device
/// model, Private Cloud Compute and the optional server so they all see the
/// same brief.
public enum GiftPromptBuilder {
    public static let instructions = """
    You are a gifting expert with exceptional taste who knows what is currently \
    available to buy. Recommend specific, buyable gifts that feel personal and \
    surprising but are still right for the recipient. Each idea must fit both \
    what the recipient loves and the giver's personality, so the gift feels \
    unmistakably from them. Avoid generic gifts (gift cards, mugs, socks, \
    candles) unless there is a specific, personal twist. Never invent brand \
    names or prices you are unsure of; give realistic price estimates and a \
    shop search query that would find the item. Keep every text field short.
    """

    public static func prompt(
        recipient: RecipientProfile,
        giver: PersonaProfile,
        seeds: [GiftIdea] = [],
        count: Int = 6,
        avoid: [String] = []
    ) -> String {
        var lines: [String] = []
        lines.append("Suggest \(count) gift ideas.")
        lines.append("")
        lines.append("RECIPIENT")
        lines.append("- Name: \(recipient.name.isEmpty ? "unnamed" : recipient.name)")
        lines.append("- Relationship to giver: \(recipient.relationship.title)")
        if let age = recipient.ageBand { lines.append("- Age: \(age.title)") }
        lines.append("- Occasion: \(recipient.occasion.title)")
        lines.append("- Budget: \(format(recipient.budgetMin)) to \(format(recipient.budgetMax)) \(recipient.currency)")
        if !recipient.interests.isEmpty {
            lines.append("- Loves: " + recipient.interests.prefix(8).map { describe($0) }.joined(separator: ", "))
        }
        if !recipient.aesthetics.isEmpty {
            lines.append("- Style: " + recipient.aesthetics.map(\.title).joined(separator: ", "))
        }
        if let traits = recipient.traits, !traits.dominant().isEmpty {
            lines.append("- Personality: " + traits.dominant().map(\.title).joined(separator: ", "))
        }
        if !recipient.signals.isEmpty {
            lines.append("- Seen in their photos/posts: " + recipient.signals.prefix(15).joined(separator: ", "))
        }
        if !recipient.notes.isEmpty { lines.append("- Notes from the giver: \(recipient.notes)") }
        if !recipient.dislikes.isEmpty { lines.append("- Dislikes, avoid: " + recipient.dislikes.joined(separator: ", ")) }
        if !recipient.pastGifts.isEmpty { lines.append("- Already given, don't repeat: " + recipient.pastGifts.joined(separator: ", ")) }

        lines.append("")
        lines.append("GIVER")
        let archetype = giver.archetype
        lines.append("- Gifting archetype: \(archetype.name) — \(archetype.giftingStyle)")
        if !giver.traits.dominant().isEmpty {
            lines.append("- Personality: " + giver.traits.dominant().map(\.title).joined(separator: ", "))
        }
        if !giver.interests.isEmpty {
            lines.append("- Their own interests: " + giver.interests.prefix(6).map(\.interest.title).joined(separator: ", "))
        }
        if !giver.aesthetics.isEmpty { lines.append("- Their taste: " + giver.aesthetics.map(\.title).joined(separator: ", ")) }
        if let summary = giver.summary, !summary.isEmpty { lines.append("- About them: \(summary)") }

        if !seeds.isEmpty {
            lines.append("")
            lines.append("Starting points (improve on these, make them more specific, don't just copy):")
            for seed in seeds.prefix(5) { lines.append("- \(seed.title)") }
        }
        if !avoid.isEmpty {
            lines.append("")
            lines.append("Already suggested, give different ideas: " + avoid.joined(separator: "; "))
        }

        lines.append("")
        lines.append("""
        Mix it up: at least one experience, at least one personalised idea, and one \
        wildcard they'd never think of. For each idea say why it suits the recipient \
        and how it reflects the giver.
        """)
        return lines.joined(separator: "\n")
    }

    /// Prompt for turning raw signals into a persona portrait.
    public static func personaPrompt(_ profile: PersonaProfile) -> String {
        var lines = ["Write a warm, specific two-sentence portrait of this person as a gift-giver, in the second person (\"You…\")."]
        lines.append("Archetype: \(profile.archetype.name)")
        lines.append("Strong traits: " + profile.traits.dominant(4).map(\.title).joined(separator: ", "))
        if !profile.interests.isEmpty {
            lines.append("Interests: " + profile.interests.prefix(8).map(\.interest.title).joined(separator: ", "))
        }
        if !profile.aesthetics.isEmpty { lines.append("Taste: " + profile.aesthetics.map(\.title).joined(separator: ", ")) }
        if !profile.signals.isEmpty { lines.append("Things in their photos: " + profile.signals.prefix(20).joined(separator: ", ")) }
        lines.append("Then give a short signature line describing how their gifts feel to receive, and an image prompt (one short phrase) for an illustrated avatar that captures their vibe without depicting a real person.")
        return lines.joined(separator: "\n")
    }

    static func describe(_ w: WeightedInterest) -> String {
        w.weight >= 0.75 ? "\(w.interest.title) (a lot)" : w.interest.title
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
