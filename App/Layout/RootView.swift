import SwiftData
import SwiftUI
import SnagKit

/// Top-level navigation. One TabView for every device:
/// - iPhone 18 Pro / Duo outer display: Liquid Glass tab bar with Scan as the
///   prominent tab (on Duo's outer display the system moves it into the
///   vertical side bar).
/// - Duo inner display / Pro Max landscape: the same tabs adapt to regular
///   width and each tab shows two panes.
/// Selection lives in `AppModel`, so folding or unfolding keeps your place.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<WishItem> { !$0.isPurchased }) private var watched: [WishItem]

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Today", systemImage: "sparkles", value: AppTab.today) {
                TodayView()
            }
            Tab("Wishlist", systemImage: "heart.text.square.fill", value: AppTab.wishlist) {
                WishlistView()
            }
            .badge(dropCount)
            Tab("Gifts", systemImage: "gift.fill", value: AppTab.gifts) {
                GiftStudioView()
            }
            Tab("Perks", systemImage: "ticket.fill", value: AppTab.perks) {
                PerksView()
            }
            Tab("Scan", systemImage: "barcode.viewfinder", value: AppTab.scan, role: .prominent) {
                ScanView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(DeviceContextReader())
        .overlay(alignment: .top) {
            if let toast = model.toast {
                GlassToast(symbol: toast.symbol, text: toast.text)
                    .padding(.top, 6)
                    .padding(.horizontal)
            }
        }
        .modifier(CheckoutPresenter())
        .modifier(PaywallPresenter())
        .fullScreenCover(isPresented: Binding(get: { !settings.hasOnboarded }, set: { settings.hasOnboarded = !$0 })) {
            OnboardingView()
        }
        .tint(Theme.teal)
    }

    private var dropCount: Int {
        watched.filter { ($0.dropSinceAdded ?? 0) >= 0.02 }.count
    }
}
