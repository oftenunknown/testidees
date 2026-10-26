import SwiftData
import SwiftUI
import SnagKit

/// Home: search anything, see what dropped, what's coming up, and recent scans.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: #Predicate<WishItem> { !$0.isPurchased }, sort: \WishItem.createdAt, order: .reverse) private var watched: [WishItem]
    @Query(sort: \ScanRecord.date, order: .reverse) private var scans: [ScanRecord]
    @Query(sort: \RecipientRecord.name) private var recipients: [RecipientRecord]

    @State private var query = ""
    @State private var searchResults: [PriceSearchService.Result] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var showSettings = false

    private var drops: [WishItem] {
        watched.filter { ($0.dropSinceAdded ?? 0) >= 0.02 }.sorted { ($0.dropSinceAdded ?? 0) > ($1.dropSinceAdded ?? 0) }
    }

    private var upcoming: [(RecipientRecord, Int)] {
        recipients.compactMap { r in r.profile.daysUntilOccasion().map { (r, $0) } }
            .filter { $0.1 <= 60 }
            .sorted { $0.1 < $1.1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !query.isEmpty || !searchResults.isEmpty {
                    searchSection
                } else {
                    if sizeClass == .regular {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 20) {
                                scanHero
                                watchingSummary
                                if !upcoming.isEmpty { upcomingSection }
                                if model.persona.completeness < 0.4 { personaTeaser }
                                if !scans.isEmpty { recentScans }
                            }
                            VStack(alignment: .leading, spacing: 20) {
                                if !drops.isEmpty { dropsSection }
                            }
                        }
                        .padding()
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            scanHero
                            if !drops.isEmpty { dropsSection }
                            if !upcoming.isEmpty { upcomingSection }
                            if model.persona.completeness < 0.4 { personaTeaser }
                            watchingSummary
                            if !scans.isEmpty { recentScans }
                        }
                        .padding()
                    }
                }
            }
            .ambientBackground()
            .navigationTitle("Today")
            .searchable(text: $query, prompt: "Search any product")
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { _, q in if q.isEmpty { searchResults = []; searchError = nil } }
            .refreshable { await model.refreshWatchedPrices(force: true) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .navigationDestination(for: PriceSearchService.Result.self) { result in
                PriceCheckView(product: result.product, offers: result.offers, degradedSources: result.degradedSources, shelfPrice: .constant(nil))
            }
            .navigationDestination(for: String.self) { productID in
                if let item = watched.first(where: { $0.productID == productID }) {
                    ProductDetailView(item: item)
                }
            }
            .modifier(VerticalBarReader())
        }
    }

    // MARK: - Search

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        searchError = nil
        Task {
            do {
                if GTIN.normalize(q) != nil, q.allSatisfy({ $0.isNumber }) {
                    searchResults = [try await model.search.lookup(code: q, region: settings.region)]
                } else {
                    searchResults = try await model.search.search(query: q, region: settings.region)
                }
                if searchResults.isEmpty { searchError = "No products matched “\(q)”." }
            } catch {
                searchError = (error as? LocalizedError)?.errorDescription ?? "Search failed."
            }
            isSearching = false
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isSearching {
                ProgressView("Checking shops…").frame(maxWidth: .infinity).padding(.top, 40)
            } else if let searchError {
                EmptyStateView(symbol: "magnifyingglass", title: "Nothing yet", message: searchError)
                    .frame(maxWidth: .infinity)
            } else if searchResults.isEmpty {
                Text("Press Search to compare prices for “\(query)”.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(searchResults, id: \.product.id) { result in
                NavigationLink(value: result) {
                    HStack(spacing: 12) {
                        ProductThumbnail(url: result.product.imageURLs.first, size: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.product.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            let best = OfferRanker.rank(result.offers, currency: settings.currency, options: model.rankingOptions).first
                            if let best {
                                Text("from \(best.effectivePrice.money(settings.currency)) at \(best.offer.merchant)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.background.secondary.opacity(0.7), in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    // MARK: - Cards

    private var scanHero: some View {
        Button { model.selectedTab = .scan } label: {
            HStack(spacing: 16) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.brandGradient, in: .rect(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 4) {
                    Text("In a shop?").font(.headline)
                    Text("Scan a barcode or price tag to see if it's a good price.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.cardRadius))
        .accessibilityHint("Opens the scanner")
    }

    private var dropsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Price drops", subtitle: "Since you started watching", symbol: "arrow.down.circle.fill")
            ForEach(drops.prefix(4)) { item in
                Button {
                    model.wishlistSelection = item.productID
                    model.selectedTab = .wishlist
                } label: {
                    WishRow(item: item)
                        .padding(12)
                        .background(.background.secondary.opacity(0.7), in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Coming up", subtitle: "Gift ideas ready with today's prices", symbol: "calendar")
            ForEach(upcoming, id: \.0.id) { record, days in
                Button {
                    model.recipientSelection = record.id
                    model.selectedTab = .gifts
                } label: {
                    HStack {
                        Image(systemName: record.profile.occasion.symbol)
                            .font(.title3)
                            .foregroundStyle(Theme.coral)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular, in: .circle)
                        VStack(alignment: .leading) {
                            Text("\(record.name)'s \(record.profile.occasion.title.lowercased())").font(.subheadline.weight(.semibold))
                            Text(days == 0 ? "Today!" : days == 1 ? "Tomorrow" : "In \(days) days")
                                .font(.caption).foregroundStyle(days <= 7 ? Theme.coral : .secondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles").foregroundStyle(Theme.violet)
                    }
                    .padding(12)
                    .background(.background.secondary.opacity(0.7), in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var personaTeaser: some View {
        Button { model.selectedTab = .gifts } label: {
            GlassCard(tint: Theme.violet) {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.badge.questionmark.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Theme.violet)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What kind of gift-giver are you?").font(.headline)
                        Text("Ten taps to build your gifting persona — it makes every recommendation feel like it came from you.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var watchingSummary: some View {
        GlassCard {
            HStack(spacing: 16) {
                stat(value: "\(watched.count)", label: "watching", symbol: "eye.fill")
                Divider().frame(height: 40)
                stat(value: "\(drops.count)", label: "dropped", symbol: "arrow.down.right")
                Divider().frame(height: 40)
                stat(value: savedTotal, label: "saved", symbol: "banknote.fill")
            }
        }
    }

    private var savedTotal: String {
        let total = watched.compactMap { item -> Double? in
            guard let added = item.addedPrice, let best = item.bestPrice, added > best else { return nil }
            return added - best
        }.reduce(0, +)
        return total.money(settings.currency)
    }

    private func stat(value: String, label: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var recentScans: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent scans", symbol: "clock.arrow.circlepath")
            ForEach(scans.prefix(5)) { scan in
                HStack(spacing: 12) {
                    ProductThumbnail(url: scan.imageURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scan.title).font(.subheadline).lineLimit(1)
                        HStack(spacing: 6) {
                            if let price = scan.userPrice { Text("Shelf \(price.money(scan.currency))") }
                            if let best = scan.bestPrice { Text("· best \(best.money(scan.currency))") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let verdict = scan.verdict { VerdictPill(level: verdict) }
                }
            }
        }
    }
}
