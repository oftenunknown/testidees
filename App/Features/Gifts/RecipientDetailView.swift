import SwiftData
import SwiftUI
import SnagKit

/// Ideas for one person, each with today's best price. Premium unlocks the
/// AI engine; free users get curated ideas.
struct RecipientDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var record: RecipientRecord
    var onEdit: () -> Void

    @State private var engine: AIService.Engine?
    @State private var isGenerating = false
    @Namespace private var cards

    private var profile: RecipientProfile { record.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if record.ideas.isEmpty && !isGenerating {
                    generatePrompt
                } else {
                    ideasGrid
                }
                if !record.savedIdeas.isEmpty {
                    SectionHeader(title: "Saved ideas", symbol: "bookmark.fill")
                    ForEach(record.savedIdeas) { idea in
                        GiftIdeaCard(idea: idea, recipient: profile, isSaved: true, onSave: { toggleSave(idea) })
                    }
                }
            }
            .padding()
        }
        .ambientBackground(tint: Theme.violet, intensity: 0.6)
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Edit", systemImage: "slider.horizontal.3", action: onEdit)
                Button("New ideas", systemImage: "sparkles") { Task { await generate(more: !record.ideas.isEmpty) } }
                    .disabled(isGenerating)
            }
        }
        .modifier(VerticalBarReader())
    }

    private var header: some View {
        GlassCard(tint: Theme.violet) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(profile.occasion.title) · \(profile.relationship.title)").font(.subheadline.weight(.semibold))
                        Text("Budget \(profile.budgetMin.money(profile.currency))–\(profile.budgetMax.money(profile.currency))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let days = profile.daysUntilOccasion() {
                        VStack {
                            Text("\(days)").font(.title.weight(.bold)).monospacedDigit()
                            Text(days == 1 ? "day" : "days").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if !profile.interests.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(profile.interests.prefix(8)) { w in
                            InterestTag(interest: w.interest)
                        }
                    }
                }
                HStack(spacing: 6) {
                    PersonaAvatar(symbol: model.persona.archetype.symbol, color: Theme.color(for: model.persona.archetype), size: 22)
                    Text("Blended with your persona: \(model.persona.archetype.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var generatePrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Theme.brandGradient)
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)))
            Text("Ideas for \(profile.name)").font(.title3.weight(.semibold))
            Text("We'll mix what \(profile.name) loves with your gifting style, then check prices.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                Task { await generate(more: false) }
            } label: {
                Label(model.isPremium ? "Find gift ideas" : "Find ideas (free preview)", systemImage: "wand.and.stars")
                    .frame(maxWidth: 320)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var ideasGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Ideas", subtitle: engine?.label ?? record.ideas.first.map { originLabel($0.origin) }, symbol: "wand.and.stars")
                if isGenerating { ProgressView() }
            }
            if !model.isPremium {
                Button { model.paywallReason = "Unlock AI gift ideas tailored to \(profile.name) and your personality." } label: {
                    Label("Free preview. Premium uses Apple Intelligence for ideas made just for \(profile.name).", systemImage: "crown.fill")
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.yellow.opacity(0.2)).interactive(), in: .rect(cornerRadius: 14))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 320 : 300), spacing: 14)], spacing: 14) {
                ForEach(record.ideas) { idea in
                    GiftIdeaCard(idea: idea, recipient: profile, isSaved: record.savedIdeas.contains { $0.id == idea.id }, onSave: { toggleSave(idea) })
                        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                }
                if isGenerating {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .fill(.background.secondary.opacity(0.5))
                            .frame(height: 220)
                            .overlay(ProgressView())
                    }
                }
            }
        }
    }

    private func originLabel(_ origin: GiftIdea.Origin) -> String {
        switch origin {
        case .cloudAI: AIService.Engine.privateCloud.label
        case .onDeviceAI: AIService.Engine.onDevice.label
        case .catalog: AIService.Engine.catalog.label
        }
    }

    private func generate(more: Bool) async {
        isGenerating = true
        let count = model.isPremium ? 6 : 3
        let avoid = more ? record.ideas.map(\.title) : []
        let (ideas, usedEngine) = await model.ai.giftIdeas(for: profile, from: model.persona, premium: model.isPremium, count: count, avoid: avoid, backend: model.search.backend)
        withAnimation(.spring(duration: 0.6, bounce: 0.25)) {
            record.ideas = more && model.isPremium ? record.ideas + ideas : ideas
            record.ideasGeneratedAt = .now
            engine = usedEngine
        }
        try? context.save()
        isGenerating = false
    }

    private func toggleSave(_ idea: GiftIdea) {
        if record.savedIdeas.contains(where: { $0.id == idea.id }) {
            record.savedIdeas.removeAll { $0.id == idea.id }
        } else {
            record.savedIdeas.append(idea)
            model.showToast("Saved for \(profile.name)", symbol: "bookmark.fill")
        }
    }
}

/// One idea with why it fits both of you, and a live best price.
struct GiftIdeaCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    var idea: GiftIdea
    var recipient: RecipientProfile
    var isSaved: Bool
    var onSave: () -> Void

    @State private var match: PriceSearchService.Result?
    @State private var lookedUp = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label(idea.kind.title, systemImage: idea.kind.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.violet)
                Spacer()
                if idea.delight >= 0.75 {
                    Label("Wildcard", systemImage: "sparkles").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                }
                Button(action: onSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? "Unsave" : "Save")
            }
            Text(idea.title).font(.headline)
            Text(idea.pitch).font(.subheadline).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                reason(symbol: "person.fill", color: Theme.teal, text: idea.whyThem)
                reason(symbol: "heart.fill", color: Theme.coral, text: idea.whyYou)
                if let touch = idea.personalTouch, expanded {
                    reason(symbol: "signature", color: Theme.violet, text: touch)
                }
                if let message = idea.cardMessage, expanded {
                    reason(symbol: "envelope.fill", color: .orange, text: "Card: “\(message)”")
                }
            }
            .padding(.top, 2)

            Divider()

            priceRow
        }
        .padding(16)
        .background(.background.secondary.opacity(0.8), in: .rect(cornerRadius: Theme.cardRadius))
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .task(id: idea.id) { await lookUpPrice() }
    }

    private func reason(symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color).frame(width: 14)
            Text(text).font(.footnote)
        }
    }

    @ViewBuilder
    private var priceRow: some View {
        let best = match.flatMap { OfferRanker.rank($0.offers, currency: settings.currency, options: model.rankingOptions).first }
        HStack {
            if let best {
                VStack(alignment: .leading, spacing: 2) {
                    PriceLabel(price: best.effectivePrice, currency: best.offer.currency, font: .headline)
                    Text("at \(best.offer.merchant)").font(.caption).foregroundStyle(.secondary)
                }
            } else if let estimate = idea.estimatedPrice {
                VStack(alignment: .leading, spacing: 2) {
                    Text("~\(estimate.money(idea.currency))").font(.headline)
                    Text(lookedUp ? "Estimate" : "Checking prices…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let match, let best {
                Button("Watch", systemImage: "bell") {
                    model.watch(product: match.product, offers: match.offers, context: context, recipientID: recipient.id)
                }
                .buttonStyle(.glass)
                .labelStyle(.iconOnly)
                if best.offer.url != nil {
                    Button("Buy") { model.buy(best.offer, productTitle: idea.title) }
                        .buttonStyle(.glassProminent)
                }
            } else {
                Link(destination: shopSearchURL) {
                    Label("Find it", systemImage: "magnifyingglass")
                }
                .buttonStyle(.glass)
            }
        }
        .controlSize(.small)
    }

    private var shopSearchURL: URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "tbm", value: "shop"), URLQueryItem(name: "q", value: idea.searchQuery)]
        return components.url!
    }

    private func lookUpPrice() async {
        guard !lookedUp else { return }
        defer { lookedUp = true }
        guard let results = await model.cachedSearch(idea.searchQuery) else { return }
        // Only trust a match whose price is plausible for the idea.
        match = results.first { result in
            guard let estimate = idea.estimatedPrice,
                  let best = PriceAnalyzer.comparableOffers(result.offers, currency: settings.currency).map(\.totalPrice).min()
            else { return !result.offers.isEmpty }
            return best > estimate * 0.25 && best < estimate * 3
        }
    }
}
