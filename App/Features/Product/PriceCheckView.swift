import SwiftData
import SwiftUI
import SnagKit

/// The answer screen: what it is, whether the price in front of you is good,
/// and the cheapest way to buy it with your perks applied — plus one-tap
/// Watch / Buy / Gift.
struct PriceCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    var product: Product
    var offers: [Offer]
    var history: [PricePoint] = []
    var degradedSources: [String] = []
    @Binding var shelfPrice: Double?

    @State private var priceText = ""
    @State private var showAllOffers = false
    @State private var showGiftPicker = false
    @FocusState private var priceFocused: Bool

    private var currency: String { settings.currency }

    private var verdict: PriceVerdict? {
        guard let shelfPrice else { return nil }
        return PriceAnalyzer.verdict(userPrice: shelfPrice, currency: currency, offers: offers, history: history,
                                     recordedLow: product.recordedLow, includeUsed: settings.includeUsed)
    }

    private var ranked: [RankedOffer] {
        OfferRanker.rank(offers, currency: currency, options: model.rankingOptions)
    }

    private var inStore: [Offer] {
        offers.filter { $0.channel == .inStore && $0.currency == currency }.prefix(3).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProductHeader(product: product, bestPrice: ranked.first?.effectivePrice, currency: currency)

                if let verdict {
                    verdictCard(verdict)
                } else {
                    shelfPriceEntry
                }

                // Actions sit right under the answer so they're visible
                // even at the sheet's smallest height.
                actionBar

                if !ranked.isEmpty {
                    SectionHeader(title: "Best prices", subtitle: perksSubtitle, symbol: "cart.fill")
                    VStack(spacing: 10) {
                        ForEach(ranked.prefix(showAllOffers ? 20 : 3)) { ranked in
                            OfferRow(ranked: ranked, productTitle: product.title)
                        }
                        if ranked.count > 3 {
                            Button(showAllOffers ? "Show fewer" : "All \(ranked.count) offers") {
                                withAnimation(.snappy) { showAllOffers.toggle() }
                            }
                            .buttonStyle(.glass)
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    ContentCard {
                        Label("No online prices found yet. Watch it and we'll keep looking.", systemImage: "binoculars")
                            .font(.subheadline)
                    }
                }

                if !inStore.isEmpty {
                    SectionHeader(title: "Seen in shops nearby", subtitle: "Shelf prices shared by shoppers", symbol: "storefront.fill")
                    ForEach(inStore) { offer in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(offer.merchant).font(.subheadline.weight(.semibold))
                                Text([offer.location, offer.updatedAt?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(offer.price.money(offer.currency)).font(.headline).monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !degradedSources.isEmpty {
                    Label("Some sources were busy (\(degradedSources.joined(separator: ", "))). Prices may be incomplete.", systemImage: "exclamationmark.icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(product.brand ?? "Result")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGiftPicker) {
            GiftForPicker(product: product, offers: offers)
                .presentationDetents([.medium])
        }
    }

    private var perksSubtitle: String? {
        let perks = settings.eligibilities.subtracting([.newCustomer])
        guard !perks.isEmpty else { return "Including delivery" }
        return "With your " + perks.map(\.title).sorted().joined(separator: ", ") + " perks"
    }

    // MARK: - Verdict

    @ViewBuilder
    private func verdictCard(_ verdict: PriceVerdict) -> some View {
        GlassCard(tint: Theme.color(for: verdict.level)) {
            HStack(alignment: .top, spacing: 16) {
                VerdictGauge(verdict: verdict, compact: true)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(verdict.level.headline)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.color(for: verdict.level))
                        Spacer()
                        Button("Edit", systemImage: "pencil") {
                            priceText = String(format: "%.2f", verdict.userPrice)
                            shelfPrice = nil
                            priceFocused = true
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .accessibilityLabel("Change the shelf price")
                    }
                    VerdictExplanation(verdict: verdict)
                    if verdict.level >= .fair, let best = verdict.bestOffer, best.url != nil {
                        Button {
                            model.buy(best, productTitle: product.title)
                        } label: {
                            Label("Buy at \(best.merchant) for \(best.totalPrice.money(best.currency))", systemImage: "cart.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .transition(.blurReplace)
    }

    private var shelfPriceEntry: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("In a shop? Check the price you're paying.", systemImage: "tag")
                    .font(.headline)
                HStack {
                    TextField("Price on the shelf", text: $priceText)
                        .keyboardType(.decimalPad)
                        .focused($priceFocused)
                        .font(.title3.monospacedDigit())
                        .padding(12)
                        .background(.background.opacity(0.6), in: .rect(cornerRadius: 14))
                        .onSubmit(applyPrice)
                    Button("Check", action: applyPrice)
                        .buttonStyle(.glassProminent)
                        .disabled(Double(priceText.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Check", action: applyPrice)
            }
        }
    }

    private func applyPrice() {
        guard let value = Double(priceText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
        withAnimation(.spring(duration: 0.5)) { shelfPrice = value }
        priceFocused = false
        let best = ranked.first?.effectivePrice
        context.insert(ScanRecord(product: product, code: product.gtin, userPrice: value, bestPrice: best, currency: currency, verdict: verdict?.level))
    }

    // MARK: - Actions

    private var actionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    model.watch(product: product, offers: offers, context: context)
                } label: {
                    Label("Watch price", systemImage: "bell.badge.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button { showGiftPicker = true } label: {
                    Label("Gift", systemImage: "gift.fill")
                }
                .buttonStyle(.glass)

                if let url = ranked.first?.offer.url ?? product.imageURLs.first {
                    ShareLink(item: url, subject: Text(product.title), message: Text(shareMessage)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Share")
                }
            }
            .controlSize(.large)
        }
    }

    private var shareMessage: String {
        guard let best = ranked.first else { return product.title }
        return "\(product.title) — \(best.effectivePrice.money(currency)) at \(best.offer.merchant) (found with Snag)"
    }
}

/// Image, name and headline price.
struct ProductHeader: View {
    var product: Product
    var bestPrice: Double?
    var currency: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ProductThumbnail(url: product.imageURLs.first, size: 86)
            VStack(alignment: .leading, spacing: 6) {
                if let brand = product.brand {
                    Text(brand.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(product.title)
                    .font(.headline)
                    .lineLimit(3)
                if let bestPrice {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("from").font(.subheadline).foregroundStyle(.secondary)
                        PriceLabel(price: bestPrice, currency: currency, font: .title3.weight(.bold))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One shop's offer with any discount we can apply.
struct OfferRow: View {
    @Environment(AppModel.self) private var model
    var ranked: RankedOffer
    var productTitle: String

    var body: some View {
        let offer = ranked.offer
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(offer.merchant).font(.subheadline.weight(.semibold))
                    if ranked.isBest {
                        Text("BEST").font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.mint.opacity(0.25), in: .capsule)
                    }
                    if offer.condition != .new && offer.condition != .unknown {
                        Text(offer.condition.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let discount = ranked.bestDiscount {
                    Label(discount.title + (discount.isEstimate ? " (est.)" : ""), systemImage: discount.eligibility?.symbol ?? "ticket.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.teal)
                        .lineLimit(1)
                } else {
                    Text(deliveryText(offer)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                PriceLabel(price: ranked.effectivePrice, currency: offer.currency, was: ranked.bestDiscount == nil ? nil : offer.totalPrice, font: .headline)
                if offer.url != nil {
                    Button("Buy") { model.buy(offer, productTitle: productTitle) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.background.secondary.opacity(0.7), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Buy") { model.buy(offer, productTitle: productTitle) }
    }

    private func deliveryText(_ offer: Offer) -> String {
        var parts: [String] = []
        switch offer.shipping {
        case .some(0): parts.append("Free delivery")
        case .some(let s): parts.append("+\(s.money(offer.currency)) delivery")
        case .none: break
        }
        if let updated = offer.updatedAt { parts.append("seen \(updated.relativeShort)") }
        return parts.isEmpty ? "Online" : parts.joined(separator: " · ")
    }
}

/// "Who's it for?" — adds the product to a recipient's list.
private struct GiftForPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecipientRecord.name) private var recipients: [RecipientRecord]
    var product: Product
    var offers: [Offer]

    var body: some View {
        NavigationStack {
            List {
                if recipients.isEmpty {
                    Text("Add people in the Gifts tab to save gift ideas for them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(recipients) { recipient in
                    Button {
                        model.watch(product: product, offers: offers, context: context, recipientID: recipient.id)
                        model.showToast("Saved as a gift for \(recipient.name)", symbol: "gift.fill")
                        dismiss()
                    } label: {
                        Label(recipient.name, systemImage: "person.crop.circle")
                    }
                }
            }
            .navigationTitle("Gift for…")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
