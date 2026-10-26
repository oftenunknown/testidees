import SwiftData
import SwiftUI
import SnagKit

/// Everything you're watching. List + detail, which collapses to a single
/// stack on the Duo outer display and tiles on the inner display. Selection
/// is held in `AppModel`, so unfolding mid-browse keeps you on the same item.
struct WishlistView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WishItem.createdAt, order: .reverse) private var items: [WishItem]
    @State private var sort: Sort = .recent
    @State private var showPurchased = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum Sort: String, CaseIterable, Identifiable {
        case recent, biggestDrop, price
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recent: "Recently added"
            case .biggestDrop: "Biggest drop"
            case .price: "Price"
            }
        }
    }

    private var visible: [WishItem] {
        let filtered = items.filter { $0.isPurchased == showPurchased }
        switch sort {
        case .recent: return filtered
        case .biggestDrop: return filtered.sorted { ($0.dropSinceAdded ?? -1) > ($1.dropSinceAdded ?? -1) }
        case .price: return filtered.sorted { ($0.bestPrice ?? .infinity) < ($1.bestPrice ?? .infinity) }
        }
    }

    var body: some View {
        @Bindable var model = model
        // Keep the list visible next to the detail on wide screens (Duo inner
        // display, iPad portrait) instead of hiding it behind a toggle.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if visible.isEmpty {
                    EmptyStateView(
                        symbol: "heart.text.square",
                        title: showPurchased ? "Nothing bought yet" : "Nothing watched yet",
                        message: "Scan or search for something and tap Watch price. We'll keep checking and tell you when it drops.",
                        actionTitle: "Scan something"
                    ) { model.selectedTab = .scan }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $model.wishlistSelection) {
                        ForEach(visible) { item in
                            WishRow(item: item)
                                .tag(item.productID)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(item) } label: { Label("Delete", systemImage: "trash") }
                                    Button { item.isPurchased.toggle() } label: {
                                        Label(item.isPurchased ? "Not bought" : "Bought", systemImage: "checkmark.circle")
                                    }
                                    .tint(Theme.teal)
                                }
                                .swipeActions(edge: .leading) {
                                    if let best = OfferRanker.rank(item.offers, currency: item.currency, options: model.rankingOptions).first, best.offer.url != nil {
                                        Button { model.buy(best.offer, productTitle: item.title) } label: { Label("Buy", systemImage: "cart.fill") }
                                            .tint(.green)
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 310, max: 400)
                    .scrollContentBackground(.hidden)
                }
            }
            .ambientBackground(intensity: 0.5)
            .navigationTitle(showPurchased ? "Bought" : "Wishlist")
            .refreshable { await model.refreshWatchedPrices(force: true) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Sort", systemImage: "arrow.up.arrow.down") {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Show bought items", isOn: $showPurchased)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Check prices", systemImage: "arrow.clockwise") {
                        Task { await model.refreshWatchedPrices(force: true) }
                    }
                }
            }
            .modifier(VerticalBarReader())
            .sideBarPriority(toolbarItems: false)
        } detail: {
            Group {
                if let id = model.wishlistSelection, let item = items.first(where: { $0.productID == id }) {
                    NavigationStack {
                        ProductDetailView(item: item)
                    }
                    .id(item.productID)
                } else {
                    EmptyStateView(symbol: "hand.point.left", title: "Pick something", message: "Choose an item to see its price history, alert and every offer.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ambientBackground(intensity: 0.5)
                }
            }
            // Lets the list and detail tile side by side on narrower wide screens.
            .navigationSplitViewColumnWidth(min: 360, ideal: 520)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func delete(_ item: WishItem) {
        if model.wishlistSelection == item.productID { model.wishlistSelection = nil }
        context.delete(item)
        try? context.save()
    }
}

struct WishRow: View {
    var item: WishItem

    var body: some View {
        HStack(spacing: 12) {
            ProductThumbnail(url: item.imageURL, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    if let price = item.bestPrice {
                        Text(price.money(item.currency))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let merchant = item.bestMerchant {
                        Text(merchant).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let rule = item.alert, rule.isEnabled {
                    Label(alertSummary(rule), systemImage: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let drop = item.dropSinceAdded { DropBadge(fraction: drop) }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func alertSummary(_ rule: PriceAlertRule) -> String {
        switch rule.trigger {
        case .percentDrop(let f): "Alert at −\(f.percentString)"
        case .targetPrice(let p): "Alert at \(p.money(rule.currency))"
        case .anyDrop: "Alert on any drop"
        case .allTimeLow: "Alert at lowest ever"
        }
    }
}
