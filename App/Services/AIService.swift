import CoreGraphics
import Foundation
import FoundationModels
import SnagKit

// MARK: - Guided generation schemas

@Generable
nonisolated enum DraftGiftKind {
    case object, experience, consumable, subscription, personalised
}

@Generable
nonisolated struct GiftIdeaDraft {
    @Guide(description: "Specific, buyable gift. Max 8 words.")
    var title: String
    @Guide(description: "One-sentence hook that makes the gift sound irresistible.")
    var pitch: String
    @Guide(description: "Why it suits the recipient, naming their interests or personality. Max 20 words.")
    var whyThem: String
    @Guide(description: "How it reflects the giver's personality, so it feels like it came from them. Max 20 words.")
    var whyYou: String
    var kind: DraftGiftKind
    @Guide(description: "Realistic price estimate in the recipient's currency, as a number.")
    var estimatedPrice: Double
    @Guide(description: "What to type into a shop's search box to find exactly this item.")
    var searchQuery: String
    @Guide(description: "A small, specific way to make it personal. Max 15 words.")
    var personalTouch: String
    @Guide(description: "How surprising-yet-right this is, from 0 to 1.", .range(0...1))
    var delight: Double
}

@Generable
nonisolated struct GiftIdeaBatch {
    @Guide(description: "Distinct gift ideas, varied in kind and price.")
    var ideas: [GiftIdeaDraft]
}

@Generable
nonisolated struct PersonaPortrait {
    @Guide(description: "Two warm, specific sentences in the second person describing them as a gift-giver.")
    var summary: String
    @Guide(description: "One short line describing how their gifts feel to receive.")
    var signature: String
    @Guide(description: "A short visual prompt for an illustrated avatar that captures their vibe. No real people, no names.")
    var avatarPrompt: String
    @Guide(description: "Up to five extra interests you can infer, as single words.")
    var extraInterests: [String]
}

/// Picks the best available model: Apple's Private Cloud Compute model for
/// premium (larger, still private), the on-device model otherwise, and the
/// built-in catalog when neither is available.
@Observable
final class AIService {
    enum Engine: String {
        case privateCloud, onDevice, server, catalog

        var label: String {
            switch self {
            case .privateCloud: "Apple Intelligence · Private Cloud"
            case .onDevice: "Apple Intelligence · on device"
            case .server: "Snag cloud ideas"
            case .catalog: "Snag curated ideas"
            }
        }
    }

    private(set) var isWorking = false

    func bestEngine(premium: Bool) -> Engine {
        if premium {
            let pcc = PrivateCloudComputeLanguageModel()
            if pcc.isAvailable && !pcc.quotaUsage.isLimitReached { return .privateCloud }
        }
        if SystemLanguageModel.default.isAvailable { return .onDevice }
        return .catalog
    }

    var onDeviceUnavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings for AI gift ideas."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading. Try again shortly."
        case .unavailable(.deviceNotEligible): "This device can't run Apple Intelligence, so you'll get curated ideas instead."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    /// Gift ideas. Always returns something: falls back to the catalog.
    func giftIdeas(
        for recipient: RecipientProfile,
        from giver: PersonaProfile,
        premium: Bool,
        count: Int = 6,
        avoid: [String] = [],
        backend: SnagBackendClient? = nil
    ) async -> (ideas: [GiftIdea], engine: Engine) {
        let seeds = GiftRecommender.recommend(for: recipient, from: giver, count: 5)
        let engine = bestEngine(premium: premium)
        guard engine != .catalog else {
            // No Apple Intelligence here: premium users can still get cloud ideas from the Snag server.
            if premium, let backend {
                isWorking = true
                defer { isWorking = false }
                if let ideas = try? await backend.giftIdeas(.init(recipient: recipient, giver: giver, count: count, avoid: avoid)), !ideas.isEmpty {
                    return (ideas, .server)
                }
            }
            return (GiftRecommender.recommend(for: recipient, from: giver, count: count).filter { !avoid.contains($0.title) }, .catalog)
        }

        isWorking = true
        defer { isWorking = false }

        let prompt = GiftPromptBuilder.prompt(recipient: recipient, giver: giver, seeds: seeds, count: count, avoid: avoid)
        do {
            let batch: GiftIdeaBatch
            switch engine {
            case .privateCloud:
                let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: GiftPromptBuilder.instructions)
                batch = try await session.respond(to: prompt, generating: GiftIdeaBatch.self).content
            default:
                let session = LanguageModelSession(instructions: GiftPromptBuilder.instructions)
                batch = try await session.respond(to: prompt, generating: GiftIdeaBatch.self, options: GenerationOptions(temperature: 0.9)).content
            }
            let origin: GiftIdea.Origin = engine == .privateCloud ? .cloudAI : .onDeviceAI
            let ideas = batch.ideas.prefix(count).map { draft in
                GiftIdea(
                    title: draft.title,
                    pitch: draft.pitch,
                    whyThem: draft.whyThem,
                    whyYou: draft.whyYou,
                    kind: Self.kind(draft.kind),
                    interests: InterestMatcher.interests(fromTexts: [draft.title, draft.searchQuery, draft.pitch], source: .ai).prefix(3).map(\.interest),
                    estimatedPrice: draft.estimatedPrice > 0 ? draft.estimatedPrice : nil,
                    currency: recipient.currency,
                    searchQuery: draft.searchQuery,
                    personalTouch: draft.personalTouch.isEmpty ? nil : draft.personalTouch,
                    cardMessage: GiftRecommender.cardMessage(recipient: recipient, archetype: giver.archetype),
                    delight: draft.delight,
                    fit: 0.8,
                    origin: origin
                )
            }
            if ideas.isEmpty { throw CancellationError() }
            return (Array(ideas), engine)
        } catch {
            return (GiftRecommender.recommend(for: recipient, from: giver, count: count), .catalog)
        }
    }

    /// AI-written persona portrait. Optionally looks at photos when the model
    /// supports vision; otherwise uses the labels we already extracted.
    func portrait(for profile: PersonaProfile, photos: [CGImage] = [], premium: Bool) async -> PersonaPortrait? {
        let engine = bestEngine(premium: premium)
        guard engine != .catalog else { return nil }
        isWorking = true
        defer { isWorking = false }

        let text = GiftPromptBuilder.personaPrompt(profile)
        do {
            if engine == .privateCloud {
                let model = PrivateCloudComputeLanguageModel()
                let session = LanguageModelSession(model: model, instructions: "You are a perceptive, kind stylist and gifting expert.")
                if model.capabilities.contains(.vision), !photos.isEmpty {
                    let attachments = photos.prefix(6).map { Attachment($0) }
                    return try await session.respond(generating: PersonaPortrait.self) {
                        text
                        "Here are some of their photos:"
                        for attachment in attachments { attachment }
                    }.content
                }
                return try await session.respond(to: text, generating: PersonaPortrait.self).content
            }
            let session = LanguageModelSession(instructions: "You are a perceptive, kind stylist and gifting expert.")
            return try await session.respond(to: text, generating: PersonaPortrait.self).content
        } catch {
            return nil
        }
    }

    /// Turns messy OCR from a product photo into a clean shopping query.
    func productQuery(fromText lines: [String], labels: [String]) async -> String? {
        let raw = lines.prefix(12).joined(separator: " | ")
        guard SystemLanguageModel.default.isAvailable else { return Self.heuristicQuery(lines: lines, labels: labels) }
        let session = LanguageModelSession(instructions: "You turn text read from product packaging into a short shopping search query: brand, product line, model and size. Reply with the query only.")
        let prompt = "Packaging text: \(raw)\nThe photo looks like: \(labels.prefix(5).joined(separator: ", "))"
        do {
            let answer = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 40)).content
            let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
            return cleaned.isEmpty ? Self.heuristicQuery(lines: lines, labels: labels) : cleaned
        } catch {
            return Self.heuristicQuery(lines: lines, labels: labels)
        }
    }

    static func heuristicQuery(lines: [String], labels: [String]) -> String? {
        // Longest few lines that look like words, not prices or codes.
        let wordy = lines.filter { line in
            let letters = line.filter(\.isLetter).count
            return letters >= 3 && Double(letters) / Double(max(line.count, 1)) > 0.5
        }
        let picked = wordy.sorted { $0.count > $1.count }.prefix(2)
        let query = picked.joined(separator: " ")
        return query.isEmpty ? labels.first : query
    }

    static func kind(_ k: DraftGiftKind) -> GiftIdea.Kind {
        switch k {
        case .object: .object
        case .experience: .experience
        case .consumable: .consumable
        case .subscription: .subscription
        case .personalised: .personalised
        }
    }
}
