import Charts
import SwiftData
import SwiftUI
import SnagKit

/// A watched item: price history, alert, all offers with your perks, and buy.
/// Two columns on the Duo inner display; the hero and chart glide into place
/// as you unfold (AnyLayout keeps identity).
struct ProductDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Bindable var item: WishItem

    @State private var isRefreshing = false
    @State private var eligibilityFilter: Set<Eligibility> = []

    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        ScrollView {
            AdaptiveStack(isWide: isWide, spacing: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    chartSection
                    AlertEditor(item: item)
                }
                .frame(maxWidth: isWide ? .infinity : nil)

                VStack(alignment: .leading, spacing: 14) {
                    offersSection
                    notesSection
                }
                .frame(maxWidth: isWide ? .infinity : nil)
            }
            .padding()
            .animation(.smooth(duration: 0.45), value: isWide)
        }
        .ambientBackground(intensity: 0.6)
        .navigationTitle(item.brand ?? "Item")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .disabled(isRefreshing)
                    .symbolEffect(.rotate, isActive: isRefreshing)
                if let best = rankedOffers.first, best.offer.url != nil {
                    Button("Buy", systemImage: "cart.fill") { model.buy(best.offer, productTitle: item.title) }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Purchased", systemImage: "checkmark.circle", isOn: $item.isPurchased)
            }
        }
        .modifier(VerticalBarReader())
    }

    private var rankedOffers: [RankedOffer] {
        var options = model.rankingOptions
        options.eligibilityFilter = eligibilityFilter
        return OfferRanker.rank(item.offers, currency: item.currency, options: options)
    }

    // MARK: Sections

    private var hero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                ProductHeader(product: item.product, bestPrice: nil, currency: item.currency)
                if let best = rankedOffers.first {
                    PriceLabel(price: best.effectivePrice, currency: item.currency, was: item.addedPrice, font: .largeTitle.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 8) {
                        Text("at \(best.offer.merchant)").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if let drop = item.dropSinceAdded { DropBadge(fraction: drop) }
                    }
                    if let discount = best.bestDiscount {
                        Label("Includes \(discount.title.lowercased())\(discount.isEstimate ? " (estimated)" : "")", systemImage: "ticket.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.teal)
                    }
                } else if let price = item.bestPrice {
                    HStack {
                        PriceLabel(price: price, currency: item.currency, font: .largeTitle.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        if let drop = item.dropSinceAdded { DropBadge(fraction: drop) }
                    }
                } else {
                    Text("No price yet").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let checked = item.lastCheckedAt {
                    Text("Checked \(checked.relativeShort)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        let history = item.history
        let summary = PriceHistory.summary(history)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Price history", subtitle: adviceText(summary), symbol: "chart.xyaxis.line")
            if history.count >= 2 {
                PriceHistoryChart(history: history, currency: item.currency, target: item.alert?.thresholdPrice)
                    .frame(height: 200)
            } else {
                ContentCard {
                    Text("We'll draw the chart as we check prices over the next few days.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func adviceText(_ summary: PriceHistorySummary) -> String? {
        switch summary.advice {
        case .buyNow: "At or near the lowest price we've seen."
        case .wait: summary.trend == .falling ? "Prices are falling. Waiting may pay off." : "Higher than usual right now."
        case .reasonable: "A typical price for this item."
        case .notEnoughData: nil
        }
    }

    private var offersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Where to buy", subtitle: "Effective price after your perks", symbol: "cart.fill")
            let perks = Eligibility.relevant(in: settings.region).filter { settings.eligibilities.contains($0) && $0 != .newCustomer }
            if !perks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(perks) { perk in
                                GlassChip(title: perk.title, symbol: perk.symbol, isOn: eligibilityFilter.contains(perk)) {
                                    withAnimation(.snappy) {
                                        if eligibilityFilter.contains(perk) { eligibilityFilter.remove(perk) } else { eligibilityFilter.insert(perk) }
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
            if rankedOffers.isEmpty {
                ContentCard {
                    Text(eligibilityFilter.isEmpty ? "No shops found yet." : "No shops with those discounts for this item.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(rankedOffers) { ranked in
                OfferRow(ranked: ranked, productTitle: item.title)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notes", symbol: "note.text")
            TextField("Size, colour, who it's for…", text: $item.note, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(.background.secondary.opacity(0.7), in: .rect(cornerRadius: 16))
        }
    }

    private func refresh() async {
        isRefreshing = true
        let offers = await model.search.refreshOffers(for: item.product, region: settings.region)
        item.apply(offers: offers, at: .now)
        try? context.save()
        isRefreshing = false
    }
}

/// History line with the alert threshold drawn as a rule.
struct PriceHistoryChart: View {
    var history: [PricePoint]
    var currency: String
    var target: Double?
    @State private var selected: Date?

    var body: some View {
        let low = history.map(\.price).min() ?? 0
        let high = history.map(\.price).max() ?? 1
        Chart {
            ForEach(history, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Base", low * 0.97), yEnd: .value("Price", point.price))
                    .foregroundStyle(LinearGradient(colors: [Theme.teal.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date), y: .value("Price", point.price))
                    .foregroundStyle(Theme.brandGradient)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let target {
                RuleMark(y: .value("Alert", target))
                    .foregroundStyle(Theme.coral.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Alert \(target.money(currency))").font(.caption2.weight(.semibold)).foregroundStyle(Theme.coral)
                    }
            }
            if let selected, let point = history.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                RuleMark(x: .value("Selected", point.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(point.price.money(currency)).font(.caption.weight(.bold))
                            Text(point.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2)
                            if let merchant = point.merchant { Text(merchant).font(.caption2).foregroundStyle(.secondary) }
                        }
                        .padding(6)
                        .glassEffect(.regular, in: .rect(cornerRadius: 10))
                    }
            }
        }
        .chartYScale(domain: (min(low, target ?? low) * 0.95)...(high * 1.04))
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(v.money(currency)) }
                }
            }
        }
        .accessibilityLabel("Price history from \(low.money(currency)) to \(high.money(currency))")
    }
}

/// Inline alert editor: off / any drop / % drop / target price / all-time low.
struct AlertEditor: View {
    @Environment(AppModel.self) private var model
    @Bindable var item: WishItem

    enum Mode: String, CaseIterable, Identifiable {
        case off, percent, target, anyDrop, lowest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Off"
            case .percent: "% off"
            case .target: "Target"
            case .anyDrop: "Any"
            case .lowest: "Lowest"
            }
        }
    }

    @State private var mode: Mode = .percent
    @State private var percent: Double = 10
    @State private var target: Double = 0
    @State private var loaded = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Price alert", systemImage: mode == .off ? "bell.slash" : "bell.badge.fill")
                    .font(.headline)
                    .contentTransition(.symbolEffect(.replace))
                Picker("Alert", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .percent:
                    VStack(alignment: .leading) {
                        Text("Tell me when it's \(Int(percent))% cheaper" + thresholdSuffix(base * (1 - percent / 100)))
                            .font(.subheadline)
                        Slider(value: $percent, in: 5...60, step: 5)
                    }
                case .target:
                    VStack(alignment: .leading) {
                        Text("Tell me when it's \(target.money(item.currency)) or less").font(.subheadline)
                        Slider(value: $target, in: max(1, base * 0.3)...max(base, 2), step: stepSize)
                    }
                case .anyDrop:
                    Text("Tell me whenever the price drops.").font(.subheadline)
                case .lowest:
                    Text("Only when it beats every price we've seen.").font(.subheadline)
                case .off:
                    Text("No alerts for this item.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: mode) { save() }
        .onChange(of: percent) { save() }
        .onChange(of: target) { save() }
    }

    private var base: Double { item.alert?.baselinePrice ?? item.bestPrice ?? 100 }
    private var stepSize: Double { base > 200 ? 5 : base > 50 ? 1 : 0.5 }

    private func thresholdSuffix(_ price: Double) -> String {
        " (\(price.money(item.currency)))"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        target = (base * 0.85).rounded()
        guard let rule = item.alert else {
            mode = .off
            return
        }
        if !rule.isEnabled { mode = .off; return }
        switch rule.trigger {
        case .percentDrop(let f): mode = .percent; percent = (f * 100).rounded()
        case .targetPrice(let p): mode = .target; target = p
        case .anyDrop: mode = .anyDrop
        case .allTimeLow: mode = .lowest
        }
    }

    private func save() {
        guard loaded else { return }
        let baseline = item.alert?.baselinePrice ?? item.bestPrice ?? base
        let trigger: PriceAlertRule.Trigger
        switch mode {
        case .off:
            if var rule = item.alert { rule.isEnabled = false; item.alert = rule }
            return
        case .percent: trigger = .percentDrop(percent / 100)
        case .target: trigger = .targetPrice(target)
        case .anyDrop: trigger = .anyDrop
        case .lowest: trigger = .allTimeLow
        }
        item.alert = PriceAlertRule(trigger: trigger, baselinePrice: baseline, currency: item.currency)
        model.registerServerWatch(item)
    }
}
